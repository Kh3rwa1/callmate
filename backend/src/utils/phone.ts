/**
 * Lead phone normalisation: bare digits with country code (India by default), e.g. 919876543210.
 * Shared by every way a lead is created (POST /leads, import, the public enquiry form and webhook).
 */
export function normalizePhone(p: string): string | null {
  const digits = p.replace(/\D/g, '');
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 11 && digits.startsWith('0')) return `91${digits.slice(1)}`;
  if (digits.startsWith('91') && digits.length === 12) return digits;
  if (digits.length >= 8 && digits.length <= 15) return digits;
  return null;
}
