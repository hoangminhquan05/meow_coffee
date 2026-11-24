// Xác thực Firebase ID token (app gửi trong header Authorization: Bearer ...).
// https://firebase.google.com/docs/auth/admin/verify-id-tokens#verify_id_tokens_using_a_third-party_jwt_library
import { decodeJwt } from './jwt';

const JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

interface Jwk extends JsonWebKey {
  kid: string;
}

let jwksCache: { keys: Jwk[]; expiresAt: number } | null = null;

async function getSigningKeys(): Promise<Jwk[]> {
  if (jwksCache && jwksCache.expiresAt > Date.now()) return jwksCache.keys;
  const res = await fetch(JWKS_URL);
  if (!res.ok) throw new Error(`Cannot fetch Firebase JWKS: ${res.status}`);
  const body = (await res.json()) as { keys: Jwk[] };
  const maxAge = /max-age=(\d+)/.exec(res.headers.get('cache-control') ?? '');
  jwksCache = {
    keys: body.keys,
    expiresAt: Date.now() + (maxAge ? Number(maxAge[1]) * 1000 : 3600_000),
  };
  return body.keys;
}

export interface FirebaseUserClaims {
  uid: string;
  email?: string;
  emailVerified: boolean;
  phoneNumber?: string;
}

export class AuthError extends Error {}

/** Kiểm chữ ký RS256, hạn dùng, aud/iss theo project. Trả về claims cần dùng. */
export async function verifyIdToken(
  token: string,
  projectId: string,
  nowSec = Math.floor(Date.now() / 1000),
): Promise<FirebaseUserClaims> {
  let decoded;
  try {
    decoded = decodeJwt(token);
  } catch {
    throw new AuthError('Token không hợp lệ');
  }
  const { header, payload } = decoded;
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') {
    throw new AuthError('Token không hợp lệ');
  }
  checkClaims(payload, projectId, nowSec);

  const jwk = (await getSigningKeys()).find((k) => k.kid === header.kid);
  if (!jwk) throw new AuthError('Token không hợp lệ (khóa không xác định)');
  const key = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    decoded.signature,
    decoded.signingInput,
  );
  if (!ok) throw new AuthError('Token không hợp lệ (sai chữ ký)');

  return {
    uid: payload.sub as string,
    email: payload.email as string | undefined,
    emailVerified: payload.email_verified === true,
    phoneNumber: payload.phone_number as string | undefined,
  };
}

/** Kiểm các claim theo hướng dẫn của Firebase (tách riêng để test). */
export function checkClaims(
  payload: Record<string, unknown>,
  projectId: string,
  nowSec: number,
): void {
  const exp = payload.exp as number;
  const iat = payload.iat as number;
  const authTime = payload.auth_time as number;
  const skew = 300; // cho phép lệch đồng hồ 5 phút
  if (typeof exp !== 'number' || exp + skew < nowSec) {
    throw new AuthError('Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại');
  }
  if (typeof iat !== 'number' || iat - skew > nowSec) throw new AuthError('Token không hợp lệ');
  if (typeof authTime !== 'number' || authTime - skew > nowSec) {
    throw new AuthError('Token không hợp lệ');
  }
  if (payload.aud !== projectId) throw new AuthError('Token không thuộc project này');
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new AuthError('Token không thuộc project này');
  }
  if (typeof payload.sub !== 'string' || payload.sub.length === 0) {
    throw new AuthError('Token không hợp lệ');
  }
}
