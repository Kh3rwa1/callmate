import { Context, Next } from 'hono';
import { Env, AuthUser, JWTPayload } from './types';

// Convert string secret to CryptoKey using Web Crypto API
async function getKey(secret: string): Promise<CryptoKey> {
  const enc = new TextEncoder();
  return crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify']
  );
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(str: string): Uint8Array {
  str = str.replace(/-/g, '+').replace(/_/g, '/');
  while (str.length % 4) str += '=';
  const binary = atob(str);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export async function signJWT(
  payload: Omit<JWTPayload, 'iat' | 'exp'>,
  secret: string,
  expiresInSeconds: number
): Promise<string> {
  const key = await getKey(secret);
  const now = Math.floor(Date.now() / 1000);
  const fullPayload: JWTPayload = {
    ...payload,
    iat: now,
    exp: now + expiresInSeconds,
  };

  const header = { alg: 'HS256', typ: 'JWT' };
  const enc = new TextEncoder();
  const headerPart = base64UrlEncode(enc.encode(JSON.stringify(header)));
  const payloadPart = base64UrlEncode(enc.encode(JSON.stringify(fullPayload)));
  const dataToSign = enc.encode(`${headerPart}.${payloadPart}`);

  const signature = await crypto.subtle.sign('HMAC', key, dataToSign);
  const signaturePart = base64UrlEncode(new Uint8Array(signature));

  return `${headerPart}.${payloadPart}.${signaturePart}`;
}

export async function verifyJWT(token: string, secret: string): Promise<JWTPayload | null> {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    const [headerPart, payloadPart, signaturePart] = parts;
    const key = await getKey(secret);
    const enc = new TextEncoder();
    const dataToVerify = enc.encode(`${headerPart}.${payloadPart}`);
    const signature = base64UrlDecode(signaturePart);

    const valid = await crypto.subtle.verify('HMAC', key, signature as ArrayBufferView, dataToVerify);
    if (!valid) return null;

    const payloadBytes = base64UrlDecode(payloadPart);
    const payload = JSON.parse(new TextDecoder().decode(payloadBytes)) as JWTPayload;

    const now = Math.floor(Date.now() / 1000);
    if (payload.exp && payload.exp < now) return null;

    return payload;
  } catch {
    return null;
  }
}

export function getJwtSecret(c: Context<any>): string {
  return c.env.JWT_SIGNING_KEY || 'callpilot-default-jwt-secret-key-change-in-env';
}

export async function authMiddleware(c: Context<{ Bindings: Env; Variables: { user: AuthUser } }>, next: Next) {
  const authHeader = c.req.header('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return c.json({ message: 'Authentication required. Missing token.', code: 'unauthorized' }, 401);
  }

  const token = authHeader.substring(7).trim();
  const secret = getJwtSecret(c);
  const payload = await verifyJWT(token, secret);

  if (!payload || payload.type !== 'access') {
    return c.json({ message: 'Your session expired. Please log in again.', code: 'token_expired' }, 401);
  }

  c.set('user', {
    id: payload.sub,
    phone: payload.phone,
    business_id: payload.business_id,
  });

  await next();
}
