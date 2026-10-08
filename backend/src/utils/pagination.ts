/** Parses a `?limit=` query value: NaN/missing -> fallback, then clamped to [1, max]. */
export function parseLimit(raw: string | undefined, fallback: number, max: number): number {
  const n = parseInt(raw ?? '', 10);
  if (!Number.isFinite(n)) return Math.min(fallback, max);
  return Math.min(Math.max(1, n), max);
}

/** Hard cap for list endpoints that are not cursor-paginated. */
export const MAX_LIST_LIMIT = 200;
