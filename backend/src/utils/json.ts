/**
 * Safe JSON parser helper with fallback defaults to prevent server crashes on malformed DB columns.
 */

export function safeJsonParse<T>(raw: string | null | undefined, fallback: T): T {
  if (raw === null || raw === undefined || raw === '') {
    return fallback;
  }
  try {
    const parsed = JSON.parse(raw);
    return parsed !== null && parsed !== undefined ? parsed : fallback;
  } catch {
    return fallback;
  }
}
