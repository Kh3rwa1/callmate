export async function deleteR2Prefix(bucket: R2Bucket | undefined, prefix: string): Promise<number> {
  if (!bucket) return 0;
  let cursor: string | undefined;
  let deleted = 0;
  do {
    const page = await bucket.list({ prefix, cursor, limit: 1000 });
    const keys = page.objects.map((o) => o.key);
    if (keys.length) { await bucket.delete(keys); deleted += keys.length; }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return deleted;
}

export function r2KeyFromFileUrl(fileUrl: string | null): string | null {
  return fileUrl?.startsWith('/r2/') ? fileUrl.slice(4) : null;
}
