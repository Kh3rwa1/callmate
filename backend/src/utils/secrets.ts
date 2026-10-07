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
