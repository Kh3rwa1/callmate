export async function hitRateLimit(db: D1Database, bucket: string, limit: number, windowSeconds: number):
  Promise<{ allowed: boolean; retryAfter: number }> {
  const row = await db.prepare(
    `SELECT COUNT(*) AS cnt FROM rate_limits WHERE bucket = ? AND created_at > datetime('now', ?)`
  ).bind(bucket, `-${windowSeconds} seconds`).first<{ cnt: number }>();
  if ((row?.cnt ?? 0) >= limit) return { allowed: false, retryAfter: windowSeconds };
  await db.prepare('INSERT INTO rate_limits (id, bucket) VALUES (?, ?)').bind(crypto.randomUUID(), bucket).run();
  return { allowed: true, retryAfter: 0 };
}
