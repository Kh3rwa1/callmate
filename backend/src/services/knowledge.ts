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
    env.DB.prepare('DELETE FROM knowledge_chunks WHERE source_id = ? AND business_id = ?').bind(sourceId, businessId),
    env.DB.prepare('DELETE FROM knowledge_fts WHERE source_id = ? AND business_id = ?').bind(sourceId, businessId),
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

/**
 * Best knowledge snippets when there is no user question yet (an outbound call): FTS matches for
 * `query` (the lead's interest) if any, else the business's first indexed chunks, else the raw text
 * of ready sources that were never chunked.
 */
export async function topKnowledge(
  env: Pick<Env, 'DB'>,
  businessId: string,
  query: string | null | undefined,
  k = 3
): Promise<string[]> {
  if (query) {
    const hits = await retrieveKnowledge(env, businessId, query, k).catch(() => [] as string[]);
    if (hits.length) return hits;
  }
  const chunks = await env.DB.prepare(
    'SELECT content FROM knowledge_chunks WHERE business_id = ? ORDER BY chunk_index, rowid LIMIT ?'
  ).bind(businessId, k).all<{ content: string }>();
  if (chunks.results?.length) return chunks.results.map((r) => r.content);
  const sources = await env.DB.prepare(
    `SELECT content FROM knowledge_sources
     WHERE business_id = ? AND status = 'ready' AND content IS NOT NULL AND content != ''
     ORDER BY created_at LIMIT ?`
  ).bind(businessId, k).all<{ content: string }>();
  return (sources.results ?? []).map((r) => r.content);
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

export const WEBSITE_MAX_BYTES = 2_000_000;
export const WEBSITE_MAX_REDIRECTS = 3;
export const WEBSITE_TIMEOUT_MS = 10_000;

function isPrivateIpv4(host: string): boolean {
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!m) return false;
  const [a, b] = [Number(m[1]), Number(m[2])];
  return a === 0 || a === 10 || a === 127 || a >= 224
    || (a === 100 && b >= 64 && b <= 127)   // CGNAT
    || (a === 169 && b === 254)             // link-local / cloud metadata
    || (a === 172 && b >= 16 && b <= 31)
    || (a === 192 && b === 168)
    || (a === 198 && (b === 18 || b === 19));
}

/**
 * Only public https URLs on the default port may be fetched. Rejects localhost / internal names,
 * private or reserved IPv4 literals, any IPv6 literal, and embedded credentials.
 */
export function assertSafePublicUrl(raw: string): URL {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new Error('Invalid URL.');
  }
  if (u.protocol !== 'https:') throw new Error('Only https:// website URLs are supported.');
  if (u.username || u.password || (u.port && u.port !== '443')) throw new Error('This website address is not allowed.');
  const host = u.hostname.toLowerCase().replace(/\.$/, '');
  if (
    !host || !host.includes('.') || host.startsWith('[') ||
    host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local') ||
    host.endsWith('.internal') || host.endsWith('.home.arpa') || isPrivateIpv4(host)
  ) {
    throw new Error('This website address is not allowed.');
  }
  return u;
}

/** Fetches a public web page with manual, re-validated redirects, a timeout and a size cap. */
export async function fetchPublicPage(rawUrl: string): Promise<string> {
  let url = assertSafePublicUrl(rawUrl);
  for (let hop = 0; ; hop++) {
    const res = await fetch(url.toString(), {
      headers: { 'User-Agent': 'CallPilot-Knowledge-Bot/1.0' },
      redirect: 'manual',
      signal: AbortSignal.timeout(WEBSITE_TIMEOUT_MS),
    });
    if (res.status >= 300 && res.status < 400) {
      const location = res.headers.get('Location');
      if (!location || hop >= WEBSITE_MAX_REDIRECTS) throw new Error('Too many redirects fetching URL');
      url = assertSafePublicUrl(new URL(location, url).toString());
      continue;
    }
    if (!res.ok) throw new Error(`HTTP ${res.status} fetching URL`);
    const declared = Number(res.headers.get('Content-Length') || 0);
    if (declared > WEBSITE_MAX_BYTES) throw new Error('Website page is too large (max 2 MB).');
    if (!res.body) return '';
    const reader = res.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > WEBSITE_MAX_BYTES) {
        await reader.cancel();
        throw new Error('Website page is too large (max 2 MB).');
      }
      chunks.push(value);
    }
    const buf = new Uint8Array(total);
    let off = 0;
    for (const ch of chunks) { buf.set(ch, off); off += ch.byteLength; }
    return new TextDecoder().decode(buf);
  }
}

export async function ingestKnowledge(
  env: Env,
  businessId: string,
  source: { id: string; type: string; content?: string | null; url?: string | null; file_url?: string | null }
): Promise<void> {
  const setStatus = (status: string, progress: number, detail?: string) =>
    env.DB.prepare("UPDATE knowledge_sources SET status = ?, progress = ?, detail = ?, updated_at = datetime('now') WHERE id = ? AND business_id = ?")
      .bind(status, progress, detail ?? null, source.id, businessId).run();

  try {
    await setStatus('processing', 0.1, 'Extracting text...');
    let text = '';

    if (source.type === 'text' || source.type === 'faq' || source.type === 'business_info' || source.type === 'notes') {
      text = source.content || '';
    } else if (source.type === 'website') {
      if (!source.url) throw new Error('Invalid URL. Only https:// is supported.');
      const html = await fetchPublicPage(source.url);
      text = htmlToText(html);
    } else if (source.type === 'document' || source.type === 'file' || source.type === 'pdf') {
      const key = source.file_url ? r2KeyFromFileUrl(source.file_url) : null;
      if (source.type === 'pdf' || (key && key.endsWith('.pdf'))) {
        throw new Error('PDF reading coming soon. Paste the text instead.');
      }
      if (!key || !env.KNOWLEDGE_BUCKET) throw new Error('Missing file in storage');
      const obj = await env.KNOWLEDGE_BUCKET.get(key);
      if (!obj) throw new Error('File not found in storage');
      const buf = await obj.arrayBuffer();
      text = new TextDecoder().decode(buf);
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
