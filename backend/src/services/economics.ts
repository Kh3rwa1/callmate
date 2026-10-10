/**
 * Unit economics: what each call costs us, the long-call watchdog and the admin margin report.
 *
 * Cost model (estimate, set per environment): every started minute of a call that actually rang
 * through costs COST_PER_MIN_SARVAM_INR + COST_PER_MIN_TELEPHONY_INR, whether or not the owner is
 * billed for it. Rounded up to whole minutes, which is conservative for margin.
 */
import { Env } from '../types';

export const DEFAULT_COST_PER_MIN_SARVAM_INR = 2;
export const DEFAULT_COST_PER_MIN_TELEPHONY_INR = 0.6;
export const DEFAULT_MAX_CALL_MINUTES = 8;

function numVar(raw: string | undefined, fallback: number, min = 0): number {
  const s = String(raw ?? '').trim();
  const n = s === '' ? NaN : Number(s);
  return Number.isFinite(n) && n >= min ? n : fallback;
}

export function costRates(env: Pick<Env, 'COST_PER_MIN_SARVAM_INR' | 'COST_PER_MIN_TELEPHONY_INR'>) {
  const sarvam = numVar(env.COST_PER_MIN_SARVAM_INR, DEFAULT_COST_PER_MIN_SARVAM_INR);
  const telephony = numVar(env.COST_PER_MIN_TELEPHONY_INR, DEFAULT_COST_PER_MIN_TELEPHONY_INR);
  return { sarvam, telephony, total: sarvam + telephony };
}

export function maxCallMinutes(env: Pick<Env, 'MAX_CALL_MINUTES'>): number {
  return numVar(env.MAX_CALL_MINUTES, DEFAULT_MAX_CALL_MINUTES, 1);
}

/** Real call length in whole seconds from a webhook duration (null/garbage → 0). */
export function callDurationSeconds(raw: unknown): number {
  const n = typeof raw === 'number' ? raw : Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

/** Our cost of a call of `seconds`, in INR (2 decimals). */
export function callCostInr(env: Pick<Env, 'COST_PER_MIN_SARVAM_INR' | 'COST_PER_MIN_TELEPHONY_INR'>, seconds: number): number {
  if (!(seconds > 0)) return 0;
  return round2(Math.ceil(seconds / 60) * costRates(env).total);
}

// ------------------------------------------------------------------ long-call watchdog

/**
 * Cron: calls still 'calling' after MAX_CALL_MINUTES are logged once (calls.overrun_flagged_at).
 * Sarvam's instant-outbound API has no end-call endpoint (checked docs.sarvam.ai, Oct 2026), so we
 * cannot hang up; the log is the signal to tighten the agent's own end-of-call rules.
 * Returns the number of calls flagged this run.
 */
export async function runLongCallWatchdog(env: Env): Promise<number> {
  const limit = maxCallMinutes(env);
  const { results } = await env.DB.prepare(
    `UPDATE calls SET overrun_flagged_at = datetime('now')
     WHERE status = 'calling' AND overrun_flagged_at IS NULL
       AND started_at < datetime('now', ?)
     RETURNING id, business_id, campaign_id, started_at`
  ).bind(`-${Math.round(limit * 60)} seconds`).all<{ id: string; business_id: string; campaign_id: string | null; started_at: string }>();
  for (const r of results ?? []) {
    console.warn(JSON.stringify({
      msg: 'call_over_max_duration', call_id: r.id, business_id: r.business_id,
      campaign_id: r.campaign_id, started_at: r.started_at, max_call_minutes: limit,
    }));
  }
  return results?.length ?? 0;
}

// ------------------------------------------------------------------ margin report

export interface MarginLine {
  revenue_inr: number;
  minutes_billed: number;
  cost_inr: number;
  gross_margin_inr: number;
  /** null when there is no revenue. */
  gross_margin_pct: number | null;
  wasted_minutes: number;
  wasted_cost_inr: number;
  calls: number;
}

function line(revenuePaise: number, minutes: number, cost: number, wastedMin: number, wastedCost: number, calls: number): MarginLine {
  const revenue = round2(revenuePaise / 100);
  const margin = round2(revenue - cost);
  return {
    revenue_inr: revenue,
    minutes_billed: minutes,
    cost_inr: round2(cost),
    gross_margin_inr: margin,
    gross_margin_pct: revenue > 0 ? Math.round((margin / revenue) * 1000) / 10 : null,
    wasted_minutes: wastedMin,
    wasted_cost_inr: round2(wastedCost),
    calls,
  };
}

/**
 * Revenue is cash received in the window, excluding GST (GST is collected for the government).
 * An annual payment counts in full in the window it was paid. Payments are grouped by the plan
 * family they bought (starter / growth); top-ups are their own group. Usage is grouped by the
 * plan the business was on when the call was billed (usage_ledger.plan_id).
 */
export async function economicsReport(env: Env, days: number) {
  const since = `-${days} days`;
  const { results: pays } = await env.DB.prepare(
    `SELECT plan_id, kind, COUNT(*) AS n,
            SUM(COALESCE(base_paise, amount_paise)) AS base_paise,
            SUM(COALESCE(gst_paise, 0)) AS gst_paise
     FROM payments
     WHERE status = 'paid' AND created_at >= datetime('now', ?)
     GROUP BY plan_id, kind`
  ).bind(since).all<{ plan_id: string; kind: string; n: number; base_paise: number; gst_paise: number }>();

  const { results: usage } = await env.DB.prepare(
    `SELECT COALESCE(plan_id, 'unknown') AS plan_id,
            COUNT(*) AS calls,
            SUM(billed_minutes) AS minutes,
            SUM(cost_inr) AS cost,
            SUM(CASE WHEN billed_minutes = 0 THEN (duration_seconds + 59) / 60 ELSE 0 END) AS wasted_minutes,
            SUM(CASE WHEN billed_minutes = 0 THEN cost_inr ELSE 0 END) AS wasted_cost
     FROM usage_ledger
     WHERE created_at >= datetime('now', ?)
     GROUP BY COALESCE(plan_id, 'unknown')`
  ).bind(since).all<{ plan_id: string; calls: number; minutes: number; cost: number; wasted_minutes: number; wasted_cost: number }>();

  const family = (p: { plan_id: string; kind: string }) =>
    p.kind === 'topup' ? 'topup' : (p.plan_id.startsWith('growth') ? 'growth' : 'starter');

  const groups = new Map<string, { rev: number; min: number; cost: number; wMin: number; wCost: number; calls: number }>();
  const g = (k: string) => {
    if (!groups.has(k)) groups.set(k, { rev: 0, min: 0, cost: 0, wMin: 0, wCost: 0, calls: 0 });
    return groups.get(k)!;
  };
  let gst = 0;
  let payments = 0;
  const byProduct = (pays ?? []).map((p) => {
    g(family(p)).rev += Number(p.base_paise ?? 0);
    gst += Number(p.gst_paise ?? 0);
    payments += Number(p.n ?? 0);
    return {
      product_id: p.plan_id, kind: p.kind, payments: Number(p.n ?? 0),
      revenue_inr: round2(Number(p.base_paise ?? 0) / 100), gst_inr: round2(Number(p.gst_paise ?? 0) / 100),
    };
  });
  for (const u of usage ?? []) {
    const x = g(u.plan_id);
    x.min += Number(u.minutes ?? 0);
    x.cost += Number(u.cost ?? 0);
    x.wMin += Number(u.wasted_minutes ?? 0);
    x.wCost += Number(u.wasted_cost ?? 0);
    x.calls += Number(u.calls ?? 0);
  }

  const total = { rev: 0, min: 0, cost: 0, wMin: 0, wCost: 0, calls: 0 };
  const byPlan = [...groups.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([plan_id, x]) => {
    total.rev += x.rev; total.min += x.min; total.cost += x.cost;
    total.wMin += x.wMin; total.wCost += x.wCost; total.calls += x.calls;
    return { plan_id, ...line(x.rev, x.min, x.cost, x.wMin, x.wCost, x.calls) };
  });

  return {
    days,
    revenue_basis: 'cash_ex_gst',
    cost_per_min_inr: costRates(env),
    total: { ...line(total.rev, total.min, total.cost, total.wMin, total.wCost, total.calls), gst_collected_inr: round2(gst / 100), payments },
    by_plan: byPlan,
    by_product: byProduct,
    time: new Date().toISOString(),
  };
}
