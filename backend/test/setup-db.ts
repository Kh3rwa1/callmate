import { env } from 'cloudflare:test';
import sql0001 from '../migrations/0001_initial.sql?raw';
import sql0003 from '../migrations/0003_otp_and_security.sql?raw';
import sql0004 from '../migrations/0004_compliance_and_billing.sql?raw';
import sql0005 from '../migrations/0005_reliability.sql?raw';

function cleanSql(sql: string): string[] {
  const noComments = sql
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/--.*$/gm, '');
  return noComments
    .split(';')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export async function migrateTestDb() {
  const scripts = [sql0001, sql0003, sql0004, sql0005];

  for (const script of scripts) {
    const statements = cleanSql(script);
    for (const stmt of statements) {
      try {
        await env.DB.prepare(stmt).run();
      } catch (err: any) {
        if (!err.message?.includes('duplicate column') && !err.message?.includes('already exists')) {
          // ignore duplicate column or table
        }
      }
    }
  }
}
