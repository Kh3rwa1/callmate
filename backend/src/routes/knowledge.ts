import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { r2KeyFromFileUrl } from '../utils/r2';
import { ingestKnowledge } from '../services/knowledge';
import { parseJsonBody, parseData, createKnowledgeSchema } from '../schemas/validation';
import { hitRateLimit } from '../utils/rate_limit';
import { parseLimit, MAX_LIST_LIMIT } from '../utils/pagination';

/** Ingestion fetches/indexes content, so cap it per business. */
export const KNOWLEDGE_INGEST_LIMIT_PER_HOUR = 30;

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
  const limit = parseLimit(c.req.query('limit'), MAX_LIST_LIMIT, MAX_LIST_LIMIT);
  const { results } = await c.env.DB.prepare(
    'SELECT * FROM knowledge_sources WHERE business_id = ? ORDER BY created_at DESC LIMIT ?'
  ).bind(user.business_id, limit).all<any>();
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

  const slot = await hitRateLimit(c.env.DB, `knowledge:biz:${user.business_id}`, KNOWLEDGE_INGEST_LIMIT_PER_HOUR, 3600);
  if (!slot.allowed) {
    c.header('Retry-After', String(slot.retryAfter));
    return c.json({ message: 'Too many knowledge uploads. Please try again later.', code: 'rate_limited' }, 429);
  }

  let type = 'text';
  let title = 'Knowledge';
  let content: string | null = null;
  let url: string | null = null;
  let detail: string | null = null;
  let fileUrl: string | null = null;

  if (contentType.includes('multipart/form-data')) {
    const formData = await c.req.parseBody();
    const field = (k: string) => (typeof formData[k] === 'string' && formData[k] ? (formData[k] as string) : undefined);
    const fields = parseData(c, createKnowledgeSchema, {
      type: field('type'), title: field('title'), content: field('content'), url: field('url'),
    });
    if (!fields.success) return fields.response;
    type = fields.data.type;
    title = fields.data.title || 'Knowledge';
    content = fields.data.content || null;
    url = fields.data.url || null;

    const file = formData['file'];
    if (file instanceof File) {
      if (file.size > 10 * 1024 * 1024) {
        return c.json({ message: 'File size exceeds 10 MB limit.', code: 'file_too_large' }, 400);
      }
      const allowedMimes = new Set(['application/pdf', 'text/plain', 'text/markdown', 'text/csv']);
      if (!allowedMimes.has(file.type)) {
        return c.json({ message: 'Unsupported file type. Allowed: PDF, TXT, MD, CSV.', code: 'invalid_file_type' }, 400);
      }

      const safeName = file.name.replace(/[^\w.\-]/g, '_').slice(0, 100);
      detail = `${safeName} · ${(file.size / 1024).toFixed(0)} KB`;
      const key = `${user.business_id}/${crypto.randomUUID()}-${safeName}`;

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
    const parsed = await parseJsonBody(c, createKnowledgeSchema);
    if (!parsed.success) return parsed.response;
    type = parsed.data.type;
    title = parsed.data.title || 'Knowledge';
    content = parsed.data.content || null;
    url = parsed.data.url || null;
    detail = url || (content ? `${content.split(/\s+/).length} words` : null);
  }

  const id = `kn_${crypto.randomUUID().slice(0, 12)}`;

  await c.env.DB.prepare(
    `INSERT INTO knowledge_sources (id, business_id, type, title, detail, status, progress, content, file_url, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 'processing', 0.1, ?, ?, datetime('now'), datetime('now'))`
  ).bind(id, user.business_id, type, title, detail, content, fileUrl).run();

  const sourceData = { id, type, content, url, file_url: fileUrl };
  try {
    c.executionCtx.waitUntil(ingestKnowledge(c.env, user.business_id, sourceData));
  } catch {
    await ingestKnowledge(c.env, user.business_id, sourceData);
  }

  const created = await c.env.DB.prepare('SELECT * FROM knowledge_sources WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatKnowledge(created));
});

// DELETE /knowledge/:id
knowledgeApp.delete('/knowledge/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const existing = await c.env.DB.prepare(
    'SELECT id, file_url FROM knowledge_sources WHERE id = ? AND business_id = ?'
  ).bind(id, user.business_id).first<{ id: string; file_url: string | null }>();
  if (!existing) {
    return c.json({ message: 'Knowledge source not found.', code: 'not_found' }, 404);
  }
  await c.env.DB.prepare('DELETE FROM knowledge_sources WHERE id = ? AND business_id = ?').bind(id, user.business_id).run();

  const key = r2KeyFromFileUrl(existing.file_url);
  if (key && c.env.KNOWLEDGE_BUCKET) {
    await c.env.KNOWLEDGE_BUCKET.delete(key);
  }

  // Delete related knowledge_chunks and knowledge_fts rows if tables exist (Phase 6)
  try {
    await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM knowledge_chunks WHERE source_id = ? AND business_id = ?').bind(id, user.business_id),
      c.env.DB.prepare('DELETE FROM knowledge_fts WHERE source_id = ? AND business_id = ?').bind(id, user.business_id),
    ]);
  } catch {}

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
  const fileName = (path.split('/').pop() || 'download').replace(/[^\w.\-]/g, '_');
  return new Response(obj.body, {
    headers: {
      'Content-Type': obj.httpMetadata?.contentType || 'application/octet-stream',
      // Never let a browser render user-uploaded content inline (stored XSS / MIME sniffing).
      'X-Content-Type-Options': 'nosniff',
      'Content-Disposition': `attachment; filename="${fileName}"`,
    },
  });
});

export { knowledgeApp };
