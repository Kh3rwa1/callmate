import { Env } from '../types';
import { r2KeyFromFileUrl } from '../utils/r2';

export function chunkText(text: string, size = 900, overlap = 150): string[] {
  const clean = text.replace(/\r/g, '').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
  if (!clean) return [];
  const chunks: string[] = [];
  let i = 0;
  while (i < clean.length) {
    let end = Math.min(clean.length, i + size);
    // prefer breaking on a sentence/paragraph boundary
    const slice = clean.slice(i, end);
    const lastBreak = Math.max(slice.lastIndexOf('\n'), slice.lastIndexOf('. '), slice.lastIndexOf('। '));
    if (end < clean.length && lastBreak > size * 0.5) end = i + lastBreak + 1;
    chunks.push(clean.slice(i, end).trim());
    if (end >= clean.length) break;
    i = Math.max(i + 1, end - overlap);
  }
  return chunks.filter(Boolean);
}

export function htmlToText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

/** Escapes special FTS5 operators and tokens to build an OR query. */
export function toFtsQuery(query: string): string | null {
  const words = query
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter((w) => w.length > 1)
    .map((w) => `"${w.toLowerCase().replace(/"/g, '""')}"`);
  return words.length ? words.join(' OR ') : null;
}

export async function indexKnowledgeSource(
  env: Pick<Env, 'DB'>,
  businessId: string,
  sourceId: string,
  text: string
): Promise<number> {
  const chunks = chunkText(text);
  if (!chunks.length) return 0;

  // clear any previous chunks
  await env.DB.batch([
    env.DB.prepare('DELETE FROM knowledge_chunks WHERE source_id = ?').bind(sourceId),
    env.DB.prepare('DELETE FROM knowledge_fts WHERE source_id = ?').bind(sourceId),
  ]);

  const chunkStmts: D1PreparedStatement[] = [];
  for (let i = 0; i < chunks.length; i++) {
    const c = chunks[i];
    const id = `chk_${crypto.randomUUID()}`;
    chunkStmts.push(
      env.DB.prepare(
        'INSERT INTO knowledge_chunks (id, business_id, source_id, chunk_index, content) VALUES (?, ?, ?, ?, ?)'
      ).bind(id, businessId, sourceId, i, c),
      env.DB.prepare(
        'INSERT INTO knowledge_fts (rowid, content, business_id, source_id, chunk_id) VALUES (NULL, ?, ?, ?, ?)'
      ).bind(c, businessId, sourceId, id)
    );
  }

  // batch in chunks of 50 statements (Cloudflare D1 batch size limit)
  for (let i = 0; i < chunkStmts.length; i += 50) {
    await env.DB.batch(chunkStmts.slice(i, i + 50));
  }
  return chunks.length;
}

export async function retrieveKnowledge(
  env: Pick<Env, 'DB'>,
  businessId: string,
  question: string,
  k = 5
): Promise<string[]> {
  const q = toFtsQuery(question);
  if (!q) return [];
  const rows = await env.DB.prepare(
    `SELECT content FROM knowledge_fts
     WHERE business_id = ? AND knowledge_fts MATCH ?
     ORDER BY bm25(knowledge_fts)
     LIMIT ?`
  ).bind(businessId, q, k).all<{ content: string }>();
  return (rows.results || []).map((r) => r.content);
}

export async function extractPdfText(env: Pick<Env, 'AI'>, buffer: ArrayBuffer): Promise<string> {
  try {
    const bytes = new Uint8Array(buffer);
    const text = new TextDecoder('latin1').decode(bytes);
    // rudimentary stream extraction from uncompressed PDF
    const matches = [...text.matchAll(/stream[\r\n]+([\s\S]*?)[\r\n]+endstream/g)];
    const extracted = matches.map((m) => m[1].replace(/[^\x20-\x7E\n]/g, ' ')).join(' ');
    if (extracted.trim().length > 50) return extracted;
  } catch { /* ignore */ }
  return '';
}

export async function ingestKnowledge(
  env: Env,
  businessId: string,
  source: { id: string; type: string; content?: string | null; url?: string | null; file_url?: string | null }
): Promise<void> {
  const setStatus = (status: string, progress: number, detail?: string) =>
    env.DB.prepare('UPDATE knowledge_sources SET status = ?, progress = ?, detail = ?, updated_at = datetime("now") WHERE id = ?')
      .bind(status, progress, detail ?? null, source.id).run();

  try {
    await setStatus('processing', 0.1, 'Extracting text...');
    let text = '';

    if (source.type === 'text') {
      text = source.content || '';
    } else if (source.type === 'website') {
      if (!source.url || !/^https?:\/\//i.test(source.url)) {
        throw new Error('Invalid URL. Only http:// and https:// are supported.');
      }
      const res = await fetch(source.url, { headers: { 'User-Agent': 'CallPilot-Knowledge-Bot/1.0' } });
      if (!res.ok) throw new Error(`HTTP ${res.status} fetching URL`);
      const html = await res.text();
      text = htmlToText(html);
    } else if (source.type === 'document' || source.type === 'file') {
      const key = source.file_url ? r2KeyFromFileUrl(source.file_url) : null;
      if (!key || !env.KNOWLEDGE_BUCKET) throw new Error('Missing file in storage');
      const obj = await env.KNOWLEDGE_BUCKET.get(key);
      if (!obj) throw new Error('File not found in storage');
      const buf = await obj.arrayBuffer();
      text = key.endsWith('.pdf') ? await extractPdfText(env, buf) : new TextDecoder().decode(buf);
    }

    if (!text.trim()) {
      await setStatus('failed', 0, 'No extractable text found.');
      return;
    }

    await setStatus('processing', 0.5, 'Chunking & indexing...');
    const count = await indexKnowledgeSource(env, businessId, source.id, text);
    await setStatus('ready', 1.0, `${count} sections learned.`);
  } catch (err: any) {
    await setStatus('failed', 0, err.message || 'Ingestion failed');
  }
}
