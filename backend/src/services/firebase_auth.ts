/**
 * Verifies Firebase Authentication ID tokens (RS256) without the Admin SDK.
 * Rules: https://firebase.google.com/docs/auth/admin/verify-id-tokens#verify_id_tokens_using_a_third-party_jwt_library
 */
const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const CLOCK_SKEW_SECONDS = 300;

export interface FirebaseIdentity {
  uid: string;
  email: string | null;
  emailVerified: boolean;
  name: string | null;
  provider: string | null;
}

let jwksCache: { keys: Record<string, CryptoKey>; expiresAt: number } | null = null;

/** Test hook: drop cached signing keys. */
export function resetFirebaseKeyCache(): void {
  jwksCache = null;
}

async function signingKeys(): Promise<Record<string, CryptoKey>> {
  if (jwksCache && jwksCache.expiresAt > Date.now()) return jwksCache.keys;
  const res = await fetch(JWKS_URL, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new Error(`firebase_jwks_http_${res.status}`);
  const body: any = await res.json();
  const keys: Record<string, CryptoKey> = {};
  for (const jwk of body.keys ?? []) {
    keys[jwk.kid] = await crypto.subtle.importKey(
      'jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']
    );
  }
  const maxAge = Number(/max-age=(\d+)/.exec(res.headers.get('Cache-Control') || '')?.[1] ?? 3600);
  jwksCache = { keys, expiresAt: Date.now() + maxAge * 1000 };
  return keys;
}

function b64urlDecode(s: string): Uint8Array {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4);
  return Uint8Array.from(atob(b64), (ch) => ch.charCodeAt(0));
}

/** Returns the verified identity, or null for any invalid, expired or foreign token. */
export async function verifyFirebaseIdToken(token: string, projectId: string): Promise<FirebaseIdentity | null> {
  const parts = token.split('.');
  if (parts.length !== 3 || !projectId) return null;
  let header: any;
  let payload: any;
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1])));
  } catch {
    return null;
  }
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') return null;

  const keys = await signingKeys();
  let key = keys[header.kid];
  if (!key) {
    // Google rotates keys; refetch once before rejecting.
    resetFirebaseKeyCache();
    key = (await signingKeys())[header.kid];
    if (!key) return null;
  }
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5', key, b64urlDecode(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`)
  );
  if (!ok) return null;

  const now = Math.floor(Date.now() / 1000);
  if (payload.aud !== projectId) return null;
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) return null;
  if (typeof payload.sub !== 'string' || !payload.sub || payload.sub.length > 128) return null;
  if (typeof payload.exp !== 'number' || payload.exp < now - CLOCK_SKEW_SECONDS) return null;
  if (typeof payload.iat !== 'number' || payload.iat > now + CLOCK_SKEW_SECONDS) return null;
  if (typeof payload.auth_time === 'number' && payload.auth_time > now + CLOCK_SKEW_SECONDS) return null;

  return {
    uid: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : null,
    emailVerified: payload.email_verified === true,
    name: typeof payload.name === 'string' ? payload.name : null,
    provider: payload.firebase?.sign_in_provider ?? null,
  };
}
