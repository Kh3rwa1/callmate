import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { parseJsonBody, ownerTestCallSchema } from '../schemas/validation';
import { normalizePhone } from './leads';
import { placeLeadCall } from './calls';
import { DEFAULT_BUSINESS_TIMEZONE, estimatedValue, localMidnightUtc, periodResults, PeriodResults } from '../services/results';

const resultsApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

const RANGE_DAYS: Record<string, number> = { today: 1, week: 7, month: 30 };

function view(r: PeriodResults, avg: number | null) {
  return {
    enquiries: r.enquiries,
    calls: r.calls,
    calls_connected: r.calls_connected,
    interested: r.interested,
    ready_to_buy: r.ready_to_buy,
    followups_sent: r.followups_sent,
    estimated_value_inr: estimatedValue(r.ready_to_buy, avg),
  };
}

// GET /dashboard/results?range=today|week|month
// The current period ends now and starts at local midnight (range days - 1) ago; `previous` is the
// same-length period just before it (week = the last 7 days vs the 7 days before).
resultsApp.get('/dashboard/results', async (c) => {
  const user = c.get('user');
  const range = c.req.query('range') || 'week';
  const days = RANGE_DAYS[range];
  if (!days) {
    return c.json({ message: 'range must be today, week or month.', code: 'validation_error' }, 400);
  }

  const now = new Date();
  const tz = DEFAULT_BUSINESS_TIMEZONE;
  const start = localMidnightUtc(now, -(days - 1), tz);
  const prevStart = localMidnightUtc(now, -(2 * days - 1), tz);

  const biz = await c.env.DB.prepare('SELECT avg_deal_value_inr FROM businesses WHERE id = ?')
    .bind(user.business_id).first<{ avg_deal_value_inr: number | null }>();
  const avg = biz?.avg_deal_value_inr ?? null;

  const current = await periodResults(c.env.DB, user.business_id, start, now);
  const previous = await periodResults(c.env.DB, user.business_id, prevStart, start);
  const anyCall = await c.env.DB.prepare(
    `SELECT 1 AS x FROM calls WHERE business_id = ?1
       AND lead_id NOT IN (SELECT id FROM leads WHERE business_id = ?1 AND is_owner_test = 1) LIMIT 1`
  ).bind(user.business_id).first();

  return c.json({
    range,
    since: start.toISOString(),
    ...view(current, avg),
    avg_deal_value_inr: avg,
    has_calls: Boolean(anyCall),
    previous: view(previous, avg),
  });
});

/** Owner test calls per business per rolling 24 hours. */
export const OWNER_TEST_CALLS_PER_DAY = 3;
const testCallBucket = (businessId: string) => `owner_test_call:${businessId}`;

async function testCallsLeft(db: D1Database, businessId: string): Promise<number> {
  const row = await db.prepare(
    `SELECT COUNT(*) AS n FROM rate_limits WHERE bucket = ? AND created_at > datetime('now', '-1 day')`
  ).bind(testCallBucket(businessId)).first<{ n: number }>();
  return Math.max(0, OWNER_TEST_CALLS_PER_DAY - Number(row?.n ?? 0));
}

// GET /agent/test-call: what the "Call me now" sheet needs (the signed-in owner's phone, calls left).
resultsApp.get('/agent/test-call', async (c) => {
  const user = c.get('user');
  const phone = user.phone ? normalizePhone(user.phone) : null;
  return c.json({
    phone,
    remaining_today: await testCallsLeft(c.env.DB, user.business_id),
    limit: OWNER_TEST_CALLS_PER_DAY,
  });
});

// POST /agent/test-call {phone}: the AI employee calls the owner, through the same dial path and
// guards as POST /leads/:id/call. The owner's number is kept as a hidden lead (is_owner_test = 1,
// consent opt_in) that never shows up in customers, stats, results, the digest or campaigns.
resultsApp.post('/agent/test-call', async (c) => {
  const user = c.get('user');
  const parsed = await parseJsonBody(c, ownerTestCallSchema);
  if (!parsed.success) return parsed.response;

  const phone = normalizePhone(parsed.data.phone);
  if (!phone) return c.json({ message: 'Invalid phone number format.', code: 'invalid_phone' }, 400);

  const existing = await c.env.DB.prepare('SELECT id, is_owner_test FROM leads WHERE business_id = ? AND phone = ?')
    .bind(user.business_id, phone).first<{ id: string; is_owner_test: number }>();
  if (existing && existing.is_owner_test !== 1) {
    return c.json({
      message: 'This number is one of your customers. Call them from the Customers tab instead.',
      code: 'phone_is_customer',
    }, 409);
  }

  // Claim a slot first (one statement, so concurrent taps cannot both pass); released if no call is placed.
  const slotId = crypto.randomUUID();
  const bucket = testCallBucket(user.business_id);
  const claim = await c.env.DB.prepare(
    `INSERT INTO rate_limits (id, bucket)
     SELECT ?, ?
     WHERE (SELECT COUNT(*) FROM rate_limits WHERE bucket = ? AND created_at > datetime('now', '-1 day')) < ?`
  ).bind(slotId, bucket, bucket, OWNER_TEST_CALLS_PER_DAY).run();
  if ((claim.meta?.changes ?? 0) === 0) {
    return c.json({
      message: `You can hear your AI ${OWNER_TEST_CALLS_PER_DAY} times a day. Try again tomorrow, or talk to it in the app.`,
      code: 'test_call_limit',
    }, 429);
  }
  const releaseSlot = () => c.env.DB.prepare('DELETE FROM rate_limits WHERE id = ?').bind(slotId).run();

  let leadId = existing?.id;
  if (!leadId) {
    const biz = await c.env.DB.prepare('SELECT owner_name FROM businesses WHERE id = ?').bind(user.business_id).first<{ owner_name: string | null }>();
    leadId = `lead_${crypto.randomUUID().slice(0, 12)}`;
    try {
      await c.env.DB.prepare(
        `INSERT INTO leads (id, business_id, name, phone, source, status, consent, timezone, is_owner_test, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'Owner test call', 'new', 'opt_in', 'Asia/Kolkata', 1, datetime('now'), datetime('now'))`
      ).bind(leadId, user.business_id, biz?.owner_name?.trim() || 'Owner', phone).run();
    } catch (err) {
      await releaseSlot();
      // Lost a race with a concurrent request for the same number: let the owner retry.
      if (/UNIQUE constraint failed/i.test(String((err as any)?.message ?? err))) {
        return c.json({ message: 'Please try again.', code: 'conflict' }, 409);
      }
      throw err;
    }
  } else {
    // The owner asked for this call: never blocked by an earlier "don't call me" on their own test lead.
    await c.env.DB.prepare(
      `UPDATE leads SET consent = 'opt_in', do_not_call = 0, updated_at = datetime('now') WHERE id = ? AND business_id = ?`
    ).bind(leadId, user.business_id).run();
  }

  let res: Response;
  try {
    res = await placeLeadCall(c, leadId);
  } catch (err) {
    await releaseSlot();
    throw err;
  }
  if (!res.ok) {
    await releaseSlot();
    return res;
  }
  const body: any = await res.json();
  return c.json({
    ...body,
    lead_id: leadId,
    remaining_today: await testCallsLeft(c.env.DB, user.business_id),
  });
});

export { resultsApp };
