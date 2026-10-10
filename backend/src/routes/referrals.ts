import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { referralSummary } from '../services/referrals';

const referralsApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// GET /referrals → { code, link, bonus_minutes, signed_up, rewarded, minutes_earned }
referralsApp.get('/referrals', async (c) => {
  const user = c.get('user');
  const base = c.env.PUBLIC_API_BASE_URL?.trim() || new URL(c.req.url).origin;
  return c.json(await referralSummary(c.env, user.business_id, base));
});

export { referralsApp };
