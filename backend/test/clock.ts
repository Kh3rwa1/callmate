import { vi } from 'vitest';

/**
 * Dial paths clamp every calling window to TRAI's 09:00-21:00 IST, so tests that expect a dial
 * to go through fail when CI runs in the evening. Move the clock to 12:00 IST (06:30 UTC) on
 * today's UTC date and let it keep ticking, so expiries and rate-limit windows still behave.
 */
export function useIndianBusinessHours(): void {
  const noonIst = new Date();
  noonIst.setUTCHours(6, 30, 0, 0);
  vi.useFakeTimers({ toFake: ['Date'], shouldAdvanceTime: true });
  vi.setSystemTime(noonIst);
}

export function useRealClock(): void {
  vi.useRealTimers();
}
