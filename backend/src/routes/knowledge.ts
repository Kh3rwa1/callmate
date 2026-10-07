import { Hono } from 'hono';
import { Env, AuthUser } from '../types';

const knowledgeApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

function formatKnowledge(row: any) {
  if (!row) return null;
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    detail: row.detail,
    status: row.status,
    progress: row.progress ?? 1.0,
    updated_at: row.updated_at,
  };
}

// GET /knowledge
knowledgeApp.get('/knowledge', async (c) => {
  const user = c.get('user');
  const { results } = await c.env.DB.prepare(
    'SELECT * FROM knowledge_sources WHERE business_id = ? ORDER BY created_at DESC'
  ).bind(user.business_id).all<any>();
  return c.json(results.map(formatKnowledge));
});

// GET /knowledge/:id
knowledgeApp.get('/knowledge/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const row = await c.env.DB.prepare(
    'SELECT * FROM knowledge_sources WHERE id = ? AND business_id = ?'
  ).bind(id, user.business_id).first();
  if (!row) return c.json({ message: 'Knowledge source not found.', code: 'not_found' }, 404);
  return c.json(formatKnowledge(row));
});

// POST /knowledge
knowledgeApp.post('/knowledge', async (c) => {
  const user = c.get('user');
  const contentType = c.req.header('Content-Type') || '';

  let type = 'text';
  let title = 'Knowledge';
  let content: string | null = null;
  let url: string | null = null;
  let detail: string | null = null;
  let fileUrl: string | null = null;

  if (contentType.includes('multipart/form-data')) {
    const formData = await c.req.parseBody();
    type = (formData['type'] as string) || 'text';
    title = (formData['title'] as string) || 'Knowledge';
    content = (formData['content'] as string) || null;
    url = (formData['url'] as string) || null;

    const file = formData['file'];
    if (file instanceof File) {
      detail = `${file.name} · ${(file.size / 1024).toFixed(0)} KB`;
      const key = `${user.business_id}/${crypto.randomUUID()}-${file.name}`;

      // Upload file to Cloudflare R2 if bucket binding is available
      if (c.env.KNOWLEDGE_BUCKET) {
        await c.env.KNOWLEDGE_BUCKET.put(key, file.stream(), {
          httpMetadata: { contentType: file.type },
        });
        fileUrl = `/r2/${key}`;
      }
    } else if (url) {
      detail = url;
    } else if (content) {
      detail = `${content.split(/\s+/).length} words`;
    }
  } else {
    const json = await c.req.json<any>().catch(() => ({}));
    type = json.type || 'text';
    title = json.title || 'Knowledge';
    content = json.content || null;
    url = json.url || null;
    detail = url || (content ? `${content.split(/\s+/).length} words` : null);
  }

  const id = `kn_${crypto.randomUUID().slice(0, 12)}`;

  await c.env.DB.prepare(
    `INSERT INTO knowledge_sources (id, business_id, type, title, detail, status, progress, content, file_url, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 'ready', 1.0, ?, ?, datetime('now'), datetime('now'))`
  ).bind(id, user.business_id, type, title, detail, content, fileUrl).run();

  const created = await c.env.DB.prepare('SELECT * FROM knowledge_sources WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatKnowledge(created));
});

// DELETE /knowledge/:id
knowledgeApp.delete('/knowledge/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const existing = await c.env.DB.prepare('SELECT id FROM knowledge_sources WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  if (!existing) {
    return c.json({ message: 'Knowledge source not found.', code: 'not_found' }, 404);
  }
  await c.env.DB.prepare('DELETE FROM knowledge_sources WHERE id = ? AND business_id = ?').bind(id, user.business_id).run();
  return c.json({ success: true });
});

// GET /r2/* (Tenant-isolated R2 access)
knowledgeApp.get('/r2/*', async (c) => {
  const user = c.get('user');
  const path = c.req.path.replace(/^\/(knowledge\/)?r2\//, '');
  if (!path.startsWith(`${user.business_id}/`)) {
    return c.json({ message: 'Access denied: foreign business resource.', code: 'forbidden' }, 403);
  }
  if (!c.env.KNOWLEDGE_BUCKET) {
    return c.json({ message: 'Storage not configured.', code: 'not_found' }, 404);
  }
  const obj = await c.env.KNOWLEDGE_BUCKET.get(path);
  if (!obj) return c.json({ message: 'File not found.', code: 'not_found' }, 404);
  return new Response(obj.body, {
    headers: {
      'Content-Type': obj.httpMetadata?.contentType || 'application/octet-stream',
    },
  });
});

export { knowledgeApp };
