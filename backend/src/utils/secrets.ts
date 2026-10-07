export function requireSecret(env: Record<string, any>, name: string, minLen = 32): string {
  const v = env[name];
  if (typeof v !== 'string' || v.trim().length < minLen) {
    throw new Error(`${name} is missing or shorter than ${minLen} chars. Refusing to operate.`);
  }
  return v.trim();
}

/** Debug affordances ONLY when explicitly in development/test. Missing or typo'd env = production behaviour. */
export function isDevEnv(env: { ENVIRONMENT?: string }): boolean {
  return env.ENVIRONMENT === 'development' || env.ENVIRONMENT === 'test';
}

/**
 * Sarvam dialing is simulated only in development/test with no key or a placeholder key.
 * In any other environment a placeholder key is a misconfiguration and must never silently "succeed".
 */
export function isMockSarvam(env: { ENVIRONMENT?: string; SARVAM_API_KEY?: string }): boolean {
  if (!isDevEnv(env)) return false;
  const key = env.SARVAM_API_KEY;
  return !key || key.startsWith('mock-') || key.startsWith('sk_test_');
}
