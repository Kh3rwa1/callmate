import { env } from 'cloudflare:test';
import sql0001 from '../migrations/0001_initial.sql?raw';
import sql0003 from '../migrations/0003_otp_and_security.sql?raw';
import sql0004 from '../migrations/0004_compliance_and_billing.sql?raw';
import sql0005 from '../migrations/0005_reliability.sql?raw';
import sql0006 from '../migrations/0006_knowledge_and_chat.sql?raw';
import sql0007 from '../migrations/0007_consent_and_attestation.sql?raw';
import sql0008 from '../migrations/0008_google_sign_in.sql?raw';
import sql0009 from '../migrations/0009_ops_alerts.sql?raw';
import sql0010 from '../migrations/0010_billing_plans.sql?raw';
import sql0011 from '../migrations/0011_lead_sources.sql?raw';
import sql0012 from '../migrations/0012_results_loop.sql?raw';
import sql0013 from '../migrations/0013_regulatory_hardening.sql?raw';
import sql0014 from '../migrations/0014_unit_economics.sql?raw';
import sql0015 from '../migrations/0015_referrals.sql?raw';
import sql0016 from '../migrations/0016_lead_integrations.sql?raw';

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
  const scripts = [sql0001, sql0003, sql0004, sql0005, sql0006, sql0007, sql0008, sql0009, sql0010, sql0011, sql0012, sql0013, sql0014, sql0015, sql0016];

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
