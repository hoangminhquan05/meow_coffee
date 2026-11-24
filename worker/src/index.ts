// Cloudflare Worker – API bán online Meow Coffee.
//   GET  /health   kiểm tra Worker đang chạy
//   POST /orders   khách tạo đơn online (cần Firebase ID token)
//   POST /orders/{id}/cancel   khách hủy đơn khi quán chưa xác nhận
import { AuthError, verifyIdToken } from './firebase/idToken';
import { Firestore, FirestoreError } from './firebase/firestore';
import { cancelOrder } from './orders/cancelOrder';
import { createOrder } from './orders/createOrder';
import { OrderRuleError } from './orders/rules';

export interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT?: string;
}

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type',
  'access-control-max-age': '86400',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...CORS },
  });
}

const error = (status: number, code: string, message: string) =>
  json(status, { error: { code, message } });

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    try {
      if (request.method === 'GET' && url.pathname === '/health') {
        return json(200, { ok: true, project: env.FIREBASE_PROJECT_ID });
      }

      if (request.method === 'POST' && url.pathname === '/orders') {
        const auth = request.headers.get('authorization') ?? '';
        const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
        if (!token) return error(401, 'unauthenticated', 'Bạn chưa đăng nhập');
        const claims = await verifyIdToken(token, env.FIREBASE_PROJECT_ID);
        const body = await request.json().catch(() => null);
        const db = new Firestore(env.FIREBASE_PROJECT_ID, env.FIREBASE_SERVICE_ACCOUNT);
        const result = await createOrder(db, claims, body);
        return json(201, result);
      }

      const cancelMatch = /^\/orders\/([^/]+)\/cancel$/.exec(url.pathname);
      if (request.method === 'POST' && cancelMatch) {
        const auth = request.headers.get('authorization') ?? '';
        const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
        if (!token) return error(401, 'unauthenticated', 'Bạn chưa đăng nhập');
        const claims = await verifyIdToken(token, env.FIREBASE_PROJECT_ID);
        const body = await request.json().catch(() => null);
        const db = new Firestore(env.FIREBASE_PROJECT_ID, env.FIREBASE_SERVICE_ACCOUNT);
        const result = await cancelOrder(db, claims, decodeURIComponent(cancelMatch[1]), body);
        return json(200, result);
      }

      return error(404, 'not_found', 'Không tìm thấy');
    } catch (e) {
      if (e instanceof AuthError) return error(401, 'unauthenticated', e.message);
      if (e instanceof OrderRuleError) return error(e.status, e.code, e.message);
      console.error('Unhandled error', e instanceof FirestoreError ? `${e.status} ${e.message}` : e);
      return error(500, 'internal', 'Máy chủ gặp lỗi, vui lòng thử lại sau');
    }
  },
} satisfies ExportedHandler<Env>;
