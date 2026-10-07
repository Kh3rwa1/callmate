import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';

describe('Test DB Migration', () => {
  beforeAll(async () => {
    await migrateTestDb();
  });

  it('has users, otp_codes, and calls tables ready', async () => {
    const tables = await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE type='table'"
    ).all<{ name: string }>();
    const names = tables.results.map((r) => r.name);
    expect(names).toContain('users');
    expect(names).toContain('otp_codes');
    expect(names).toContain('calls');
    expect(names).toContain('leads');
    expect(names).toContain('campaigns');
    expect(names).toContain('usage');
  });
});
