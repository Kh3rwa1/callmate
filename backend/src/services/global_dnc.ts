/**
 * Platform-wide do-not-call list (table global_dnc).
 *
 * Anyone can add their number on the public /stop page; checkCallCompliance then refuses to dial
 * it for every business. Only HMAC(secret, canonical digits) is stored, so the table can't be
 * turned back into a phone list without the Worker secret.
 */
import { Env } from '../types';
import { hmacHex } from './plans';

export type GlobalDncSource = 'web' | 'call' | 'admin';

/**
 * Canonical digits for a phone number, matching how leads are stored
 * (routes/leads.ts normalizePhone): 10 digits get the 91 prefix, a leading 0 trunk prefix is
 * swapped for 91, other 8-15 digit numbers are kept. Null if it can't be a phone number.
 */
export function canonicalPhone(raw: unknown): string | null {
  const digits = String(raw ?? '').replace(/\D/g, '');
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 11 && digits.startsWith('0')) return `91${digits.slice(1)}`;
  if (digits.length === 14 && digits.startsWith('0091')) return digits.slice(2);
  if (digits.length >= 8 && digits.length <= 15) return digits;
  return null;
}

/** HMAC key for phone hashes: OTP_PEPPER, else ENCRYPTION_KEY. Null when neither is usable. */
export function globalDncSecret(env: Pick<Env, 'OTP_PEPPER' | 'ENCRYPTION_KEY'>): string | null {
  const s = (env.OTP_PEPPER || env.ENCRYPTION_KEY || '').trim();
  return s.length >= 16 ? s : null;
}

export async function phoneHash(secret: string, phone: string): Promise<string | null> {
  const canonical = canonicalPhone(phone);
  return canonical ? hmacHex(secret, `dnc:phone:${canonical}`) : null;
}

/** Adds a number (idempotent). Returns false when the number is invalid. */
export async function addToGlobalDnc(db: D1Database, secret: string, phone: string, source: GlobalDncSource): Promise<boolean> {
  const hash = await phoneHash(secret, phone);
  if (!hash) return false;
  await db.prepare('INSERT OR IGNORE INTO global_dnc (phone_hash, source) VALUES (?, ?)').bind(hash, source).run();
  return true;
}

export async function isInGlobalDnc(db: D1Database, secret: string, phone: string): Promise<boolean> {
  const hash = await phoneHash(secret, phone);
  if (!hash) return false;
  const row = await db.prepare('SELECT 1 AS hit FROM global_dnc WHERE phone_hash = ?').bind(hash).first<{ hit: number }>();
  return row?.hit === 1;
}
