/**
 * GET /playbooks/current?lang=en|hi|bn
 *
 * The business's call playbook (services/playbooks.ts), picked from businesses.category, for the
 * app's read-only "Your call playbook" screen. Language: ?lang, else the employee's first
 * language, else English. Follow-up templates keep their {name} / {business} placeholders.
 */
import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { playbookFor, formatPlaybook } from '../services/playbooks';
import { parseLangParam } from '../services/page_lang';
import { callLang } from '../services/voice_persona';

const playbooksApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

playbooksApp.get('/playbooks/current', async (c) => {
  const user = c.get('user');
  const [business, agent] = await Promise.all([
    c.env.DB.prepare('SELECT name, category FROM businesses WHERE id = ?').bind(user.business_id)
      .first<{ name: string | null; category: string | null }>(),
    c.env.DB.prepare('SELECT languages FROM agents WHERE business_id = ? ORDER BY created_at LIMIT 1').bind(user.business_id)
      .first<{ languages: string | null }>(),
  ]);
  const lang = parseLangParam(c.req.query('lang')) ?? callLang(agent?.languages);
  const category = business?.category?.trim() || null;
  return c.json({
    ...formatPlaybook(playbookFor(category), lang, category),
    business_name: business?.name ?? '',
  });
});

export { playbooksApp };
