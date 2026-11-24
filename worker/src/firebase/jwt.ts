// Tiện ích JWT/base64url dùng chung (Web Crypto, chạy được trên Workers).

export function base64UrlEncode(data: ArrayBuffer | Uint8Array | string): string {
  const bytes =
    typeof data === 'string'
      ? new TextEncoder().encode(data)
      : data instanceof Uint8Array
        ? data
        : new Uint8Array(data);
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function base64UrlDecode(input: string): Uint8Array {
  const b64 = input.replace(/-/g, '+').replace(/_/g, '/');
  const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export interface DecodedJwt {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
  signingInput: Uint8Array;
  signature: Uint8Array;
}

/** Tách JWT, không kiểm chữ ký. Sai định dạng → throw. */
export function decodeJwt(token: string): DecodedJwt {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('JWT must have 3 parts');
  const json = (s: string) =>
    JSON.parse(new TextDecoder().decode(base64UrlDecode(s))) as Record<string, unknown>;
  return {
    header: json(parts[0]),
    payload: json(parts[1]),
    signingInput: new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    signature: base64UrlDecode(parts[2]),
  };
}
