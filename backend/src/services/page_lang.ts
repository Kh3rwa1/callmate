/**
 * Language for the public, server-rendered pages (hosted enquiry form /f/:slug and /stop).
 *
 * Picked in this order:
 *   1. `?lang=en|hi|bn` (the switcher links and the forms' own action URL carry it);
 *   2. the business's default: its AI employee's first language (agents.languages), when it is one
 *      of ours (only pages that belong to a business have this);
 *   3. the browser's Accept-Language;
 *   4. English.
 */
import { escapeHtml } from '../routes/legal';

export type PageLang = 'en' | 'hi' | 'bn';
export const PAGE_LANGS: readonly PageLang[] = ['en', 'hi', 'bn'];

/** Each language's name in itself, for the switcher. */
export const PAGE_LANG_NAMES: Record<PageLang, string> = { en: 'English', hi: 'हिन्दी', bn: 'বাংলা' };

export function isPageLang(v: unknown): v is PageLang {
  return typeof v === 'string' && (PAGE_LANGS as readonly string[]).includes(v);
}

/** Exact `en|hi|bn` (case-insensitive, trimmed), else null. */
export function parseLangParam(v: string | null | undefined): PageLang | null {
  const s = (v ?? '').trim().toLowerCase();
  return isPageLang(s) ? s : null;
}

/**
 * The first supported language in an Accept-Language header, by q-value (ties keep header order).
 * `bn-IN` and `bn` both count as Bengali. Null if none is supported.
 */
export function parseAcceptLanguage(header: string | null | undefined): PageLang | null {
  if (!header) return null;
  const ranked = header.split(',').slice(0, 20).map((part, index) => {
    const [tag, ...params] = part.trim().split(';');
    const qParam = params.map((p) => p.trim()).find((p) => p.startsWith('q='));
    const q = qParam ? Number(qParam.slice(2)) : 1;
    return { base: tag.trim().toLowerCase().split('-')[0], q: Number.isFinite(q) ? q : 0, index };
  }).filter((x) => x.q > 0)
    .sort((a, b) => b.q - a.q || a.index - b.index);
  for (const r of ranked) {
    if (isPageLang(r.base)) return r.base;
  }
  return null;
}

/**
 * The business's default page language from its employee's languages (stored as a JSON array of
 * names, e.g. '["Hindi","English"]'). Null when unset or the first language is not one we render.
 */
export function businessPageLang(languages: string | string[] | null | undefined): PageLang | null {
  let list: unknown = languages;
  if (typeof languages === 'string') {
    try { list = JSON.parse(languages); } catch { list = [languages]; }
  }
  const first = Array.isArray(list) ? String(list[0] ?? '').trim().toLowerCase() : '';
  if (first.startsWith('hindi') || first === 'हिन्दी' || first === 'हिंदी') return 'hi';
  if (first.startsWith('bengali') || first.startsWith('bangla') || first === 'বাংলা') return 'bn';
  if (first.startsWith('english')) return 'en';
  return null;
}

export function resolvePageLang(opts: {
  query?: string | null;
  businessDefault?: PageLang | null;
  acceptLanguage?: string | null;
}): PageLang {
  return parseLangParam(opts.query)
    ?? opts.businessDefault
    ?? parseAcceptLanguage(opts.acceptLanguage)
    ?? 'en';
}

/** `base` with `lang` set (base is a same-origin path such as /f/abc or /stop). */
export function withLang(base: string, lang: PageLang): string {
  return `${base}${base.includes('?') ? '&' : '?'}lang=${lang}`;
}

/**
 * Small "English · हिन्दी · বাংলা" links. Plain links (no script); the current language is marked
 * with aria-current and not linked.
 */
export function languageSwitcher(base: string, current: PageLang, label: string): string {
  const items = PAGE_LANGS.map((l) => (l === current
    ? `<strong lang="${l}" aria-current="true">${PAGE_LANG_NAMES[l]}</strong>`
    : `<a href="${escapeHtml(withLang(base, l))}" hreflang="${l}" lang="${l}">${PAGE_LANG_NAMES[l]}</a>`));
  return `<nav class="langs" aria-label="${escapeHtml(label)}">${items.join(' · ')}</nav>`;
}
