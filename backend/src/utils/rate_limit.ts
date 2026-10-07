/**
 * Sliding-window rate limit. The count check and the insert are ONE statement, so concurrent
 * requests cannot both observe "under the limit" and both get through (D1 serialises writes).
 */
export async function hitRateLimit(db: D1Database, bucket: string, limit: number, windowSeconds: number):
  Promise<{ allowed: boolean; retryAfter: number }> {
  const res = await db.prepare(
    `INSERT INTO rate_limits (id, bucket)
     SELECT ?, ?
     WHERE (SELECT COUNT(*) FROM rate_limits WHERE bucket = ? AND created_at > datetime('now', ?)) < ?`
  ).bind(crypto.randomUUID(), bucket, bucket, `-${windowSeconds} seconds`, limit).run();
  const allowed = (res.meta?.changes ?? 0) > 0;
  return { allowed, retryAfter: allowed ? 0 : windowSeconds };
}
