/**
 * At-rest encryption for sensitive columns (transcripts, raw_metadata) using AES-GCM (Web Crypto API).
 */

const ALGORITHM = 'AES-GCM';
const IV_LENGTH = 12; // 96-bit IV recommended for AES-GCM
const PREFIX = 'enc:v1:';

async function deriveKey(secret: string): Promise<CryptoKey> {
  const enc = new TextEncoder();
  // Hash the secret with SHA-256 to ensure exact 256-bit key length
  const keyMaterial = await crypto.subtle.digest('SHA-256', enc.encode(secret));
  return crypto.subtle.importKey(
    'raw',
    keyMaterial,
    { name: ALGORITHM },
    false,
    ['encrypt', 'decrypt']
  );
}

function toBase64(bytes: Uint8Array): string {
  let binary = '';
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function fromBase64(str: string): Uint8Array {
  const binary = atob(str);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * Encrypts a plaintext string with AES-256-GCM.
 * Output format: enc:v1:<base64-iv>:<base64-ciphertext>
 */
export async function encryptAtRest(plaintext: string | null | undefined, secret?: string): Promise<string | null> {
  if (plaintext === null || plaintext === undefined) return null;
  const keySecret = secret || 'default-fallback-must-provide-secret';
  
  const key = await deriveKey(keySecret);
  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));
  const enc = new TextEncoder();
  const encryptedBuf = await crypto.subtle.encrypt(
    { name: ALGORITHM, iv },
    key,
    enc.encode(plaintext)
  );

  const ivB64 = toBase64(iv);
  const dataB64 = toBase64(new Uint8Array(encryptedBuf));

  return `${PREFIX}${ivB64}:${dataB64}`;
}

/**
 * Decrypts an encrypted ciphertext string.
 * If data is not encrypted (e.g. unencrypted legacy string), returns it as-is.
 */
export async function decryptAtRest(ciphertext: string | null | undefined, secret?: string): Promise<string | null> {
  if (ciphertext === null || ciphertext === undefined) return null;
  if (!ciphertext.startsWith(PREFIX)) {
    // Unencrypted legacy data
    return ciphertext;
  }

  const keySecret = secret || 'default-fallback-must-provide-secret';
  const parts = ciphertext.slice(PREFIX.length).split(':');
  if (parts.length !== 2) return ciphertext;

  try {
    const iv = fromBase64(parts[0]);
    const data = fromBase64(parts[1]);
    const key = await deriveKey(keySecret);
    const decryptedBuf = await crypto.subtle.decrypt(
      { name: ALGORITHM, iv },
      key,
      data
    );
    const dec = new TextDecoder();
    return dec.decode(decryptedBuf);
  } catch (err) {
    console.warn('[AES-GCM Decryption Warning] Failed to decrypt data, returning raw:', err);
    return ciphertext;
  }
}
