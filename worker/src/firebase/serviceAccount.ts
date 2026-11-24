// Đổi service account (JSON trong secret FIREBASE_SERVICE_ACCOUNT) lấy OAuth
// access token để gọi Firestore REST. Service account bỏ qua Firestore Rules.
import { base64UrlEncode } from './jwt';

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

let cached: { token: string; expiresAt: number; email: string } | null = null;

export function parseServiceAccount(raw: string | undefined): ServiceAccount {
  if (!raw) throw new Error('Thiếu secret FIREBASE_SERVICE_ACCOUNT');
  const sa = JSON.parse(raw) as ServiceAccount;
  if (!sa.client_email || !sa.private_key) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT thiếu client_email/private_key');
  }
  return sa;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\\n/g, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

export async function getAccessToken(rawServiceAccount: string | undefined): Promise<string> {
  const sa = parseServiceAccount(rawServiceAccount);
  if (cached && cached.email === sa.client_email && cached.expiresAt > Date.now() + 60_000) {
    return cached.token;
  }
  const tokenUri = sa.token_uri ?? 'https://oauth2.googleapis.com/token';
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64UrlEncode(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/datastore',
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const key = await importPrivateKey(sa.private_key);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${base64UrlEncode(signature)}`;

  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`Google OAuth ${res.status}: ${await res.text()}`);
  const body = (await res.json()) as { access_token: string; expires_in: number };
  cached = {
    token: body.access_token,
    expiresAt: Date.now() + body.expires_in * 1000,
    email: sa.client_email,
  };
  return body.access_token;
}
