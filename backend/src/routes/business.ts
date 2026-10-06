import { Hono } from 'hono';
import { Env, AuthUser } from '../types';

const businessApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// Helper to format Business entity from D1 row
function formatBusiness(row: any) {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    category: row.category,
    address: row.address,
    offerings: row.offerings ? JSON.parse(row.offerings) : null,
    pricing: row.pricing,
    opening_hours: row.opening_hours,
    location: row.location,
    whatsapp_number: row.whatsapp_number,
    human_number: row.human_number,
    owner_name: row.owner_name,
  };
}

// Helper to format Agent entity from D1 row
function formatAgent(row: any) {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    role: row.role,
    status: row.status,
    template_id: row.template_id,
    role_kind: row.role_kind,
    skills: row.skills ? JSON.parse(row.skills) : [],
    languages: row.languages ? JSON.parse(row.languages) : ['English', 'Hindi'],
    goal: row.goal,
    formality: row.formality ?? 0.35,
    capabilities: row.capabilities ? JSON.parse(row.capabilities) : [],
    calling_hours_start: row.calling_hours_start ?? 10,
    calling_hours_end: row.calling_hours_end ?? 19,
    transfer_number: row.transfer_number,
    voice: row.voice || 'Friendly Female (Hindi/English)',
    calls_today: row.calls_today ?? 0,
  };
}

// GET /business
businessApp.get('/business', async (c) => {
  const user = c.get('user');
  const row = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first();
  return c.json(formatBusiness(row));
});

// PATCH /business
businessApp.patch('/business', async (c) => {
  const user = c.get('user');
  const body = await c.req.json<any>().catch(() => ({}));

  const existing = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first<any>();
  if (!existing) {
    return c.json({ message: 'Business not found.', code: 'not_found' }, 404);
  }

  const name = body.name !== undefined ? body.name : existing.name;
  const category = body.category !== undefined ? body.category : existing.category;
  const address = body.address !== undefined ? body.address : existing.address;
  const offerings = body.offerings !== undefined ? JSON.stringify(body.offerings) : existing.offerings;
  const pricing = body.pricing !== undefined ? body.pricing : existing.pricing;
  const openingHours = body.opening_hours !== undefined ? body.opening_hours : existing.opening_hours;
  const location = body.location !== undefined ? body.location : existing.location;
  const whatsappNumber = body.whatsapp_number !== undefined ? body.whatsapp_number : existing.whatsapp_number;
  const humanNumber = body.human_number !== undefined ? body.human_number : existing.human_number;
  const ownerName = body.owner_name !== undefined ? body.owner_name : existing.owner_name;

  await c.env.DB.prepare(
    `UPDATE businesses SET
      name = ?, category = ?, address = ?, offerings = ?, pricing = ?,
      opening_hours = ?, location = ?, whatsapp_number = ?, human_number = ?,
      owner_name = ?, updated_at = datetime('now')
     WHERE id = ?`
  ).bind(
    name, category, address, offerings, pricing,
    openingHours, location, whatsappNumber, humanNumber,
    ownerName, user.business_id
  ).run();

  const updated = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first();
  return c.json(formatBusiness(updated));
});

// GET /agent
businessApp.get('/agent', async (c) => {
  const user = c.get('user');
  const row = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first();
  return c.json(formatAgent(row));
});

// PATCH /agent
businessApp.patch('/agent', async (c) => {
  const user = c.get('user');
  const body = await c.req.json<any>().catch(() => ({}));

  let existing = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first<any>();
  if (!existing) {
    const agentId = `agent_${crypto.randomUUID().slice(0, 12)}`;
    await c.env.DB.prepare(
      `INSERT INTO agents (id, business_id, name, role, status, template_id, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'active', 'generic_sales_v1', datetime('now'), datetime('now'))`
    ).bind(agentId, user.business_id, body.name || 'Maya', body.role || 'Sales Assistant').run();
    existing = await c.env.DB.prepare('SELECT * FROM agents WHERE id = ?').bind(agentId).first<any>();
  }

  const name = body.name !== undefined ? body.name : existing.name;
  const role = body.role !== undefined ? body.role : existing.role;
  const status = body.status !== undefined ? body.status : existing.status;
  const templateId = body.template_id !== undefined ? body.template_id : existing.template_id;
  const roleKind = body.role_kind !== undefined ? body.role_kind : existing.role_kind;
  const skills = body.skills !== undefined ? JSON.stringify(body.skills) : existing.skills;
  const languages = body.languages !== undefined ? JSON.stringify(body.languages) : existing.languages;
  const goal = body.goal !== undefined ? body.goal : existing.goal;
  const formality = body.formality !== undefined ? body.formality : existing.formality;
  const capabilities = body.capabilities !== undefined ? JSON.stringify(body.capabilities) : existing.capabilities;
  const callingHoursStart = body.calling_hours_start !== undefined ? body.calling_hours_start : existing.calling_hours_start;
  const callingHoursEnd = body.calling_hours_end !== undefined ? body.calling_hours_end : existing.calling_hours_end;
  const transferNumber = body.transfer_number !== undefined ? body.transfer_number : existing.transfer_number;
  const voice = body.voice !== undefined ? body.voice : existing.voice;

  await c.env.DB.prepare(
    `UPDATE agents SET
      name = ?, role = ?, status = ?, template_id = ?, role_kind = ?,
      skills = ?, languages = ?, goal = ?, formality = ?, capabilities = ?,
      calling_hours_start = ?, calling_hours_end = ?, transfer_number = ?, voice = ?,
      updated_at = datetime('now')
     WHERE business_id = ?`
  ).bind(
    name, role, status, templateId, roleKind,
    skills, languages, goal, formality, capabilities,
    callingHoursStart, callingHoursEnd, transferNumber, voice,
    user.business_id
  ).run();

  const updated = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first();
  return c.json(formatAgent(updated));
});

export { businessApp };
