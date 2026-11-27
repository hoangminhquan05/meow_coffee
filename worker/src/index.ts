// Cloudflare Worker – API bán online Meow Coffee.
//   GET  /health                         kiểm tra Worker đang chạy
//   POST /orders                         khách tạo đơn online (Firebase ID token)
//   POST /orders/{id}/cancel             khách hủy đơn khi quán chưa xác nhận
//   POST /webhooks/sepay                 SePay báo tiền vào (header Authorization: Apikey …)
//   POST /admin/payments/{id}/resolve    admin xử lý giao dịch cần kiểm tra
//   POST /shipper/shift                  shipper bắt đầu / kết thúc ca
//   POST /shipper/orders/{id}            shipper: đã lấy hàng / đến nơi / gọi / đã giao / giao thất bại
//   POST /dispatch/{id}                  NV/admin: pha xong (gán shipper), mời lại, gán tay, giao lại, hủy
//   POST /dispatch/{id}/respond          shipper: nhận / từ chối / hết giờ lời mời
//   cron mỗi phút                         hủy đơn VietQR quá hạn; kết thúc ca shipper mất GPS;
//                                         lời mời quá 60s → mời người tiếp; đơn chưa có shipper → mời lại
import { AuthError, verifyIdToken, type FirebaseUserClaims } from './firebase/idToken';
import { Firestore, FirestoreError } from './firebase/firestore';
import { cancelOrder } from './orders/cancelOrder';
import { createOrder } from './orders/createOrder';
import { OrderRuleError } from './orders/rules';
import { expireUnpaidOrders } from './payments/expire';
import { resolvePayment } from './payments/resolve';
import { checkSepayAuth, handleSepayWebhook, type SepayPayload } from './payments/sepay';
import { endStaleShifts, handleShift } from './shipper/shift';
import { handleShipperOrder } from './shipper/delivery';
import { isConflict, respondOffer, runDispatchCron } from './dispatch/dispatch';
import { handleStaffDispatch } from './dispatch/staff';

export interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT?: string;
  SEPAY_API_KEY?: string;
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

async function requireUser(request: Request, env: Env): Promise<FirebaseUserClaims> {
  const auth = request.headers.get('authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) throw new AuthError('Bạn chưa đăng nhập');
  return verifyIdToken(token, env.FIREBASE_PROJECT_ID);
}

const db = (env: Env) => new Firestore(env.FIREBASE_PROJECT_ID, env.FIREBASE_SERVICE_ACCOUNT);

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    const started = Date.now();
    const res = await route(request, env, ctx, url);
    // Nhật ký thời gian xử lý (xem bằng `npx wrangler tail`) – không ghi dữ liệu khách.
    console.log(`${request.method} ${url.pathname} ${res.status} ${Date.now() - started}ms`);
    return res;
  },

  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    await runScheduled(env, ctx);
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env, ctx: ExecutionContext, url: URL): Promise<Response> {
  // Việc làm tiếp sau khi đã trả lời app (ví dụ mời shipper kế tiếp).
  const defer = (p: Promise<unknown>) => ctx.waitUntil(p);
  try {
    if (request.method === 'GET' && url.pathname === '/health') {
      return json(200, { ok: true, project: env.FIREBASE_PROJECT_ID });
    }

    if (request.method === 'POST' && url.pathname === '/orders') {
      const claims = await requireUser(request, env);
      const body = await request.json().catch(() => null);
      return json(201, await createOrder(db(env), claims, body));
    }

    const cancelMatch = /^\/orders\/([^/]+)\/cancel$/.exec(url.pathname);
    if (request.method === 'POST' && cancelMatch) {
      const claims = await requireUser(request, env);
      const body = await request.json().catch(() => null);
      return json(200, await cancelOrder(db(env), claims, decodeURIComponent(cancelMatch[1]), body));
    }

    if (request.method === 'POST' && url.pathname === '/webhooks/sepay') {
      if (!checkSepayAuth(request.headers.get('authorization'), env.SEPAY_API_KEY)) {
        return json(401, { success: false, message: 'Unauthorized' });
      }
      const payload = (await request.json().catch(() => null)) as SepayPayload | null;
      if (!payload || typeof payload.id !== 'number') {
        return json(400, { success: false, message: 'Invalid payload' });
      }
      const result = await handleSepayWebhook(db(env), payload);
      console.log('sepay webhook', payload.id, result);
      // SePay coi là thành công khi HTTP 200/201 và body có success: true.
      return json(200, { success: true, ...result });
    }

    const resolveMatch = /^\/admin\/payments\/([^/]+)\/resolve$/.exec(url.pathname);
    if (request.method === 'POST' && resolveMatch) {
      const claims = await requireUser(request, env);
      const body = await request.json().catch(() => null);
      return json(200, await resolvePayment(db(env), claims, decodeURIComponent(resolveMatch[1]), body));
    }

    if (request.method === 'POST' && url.pathname === '/shipper/shift') {
      const claims = await requireUser(request, env);
      const body = await request.json().catch(() => null);
      return json(200, await handleShift(db(env), claims, body));
    }

    const shipperOrder = /^\/shipper\/orders\/([^/]+)$/.exec(url.pathname);
    if (request.method === 'POST' && shipperOrder) {
      const claims = await requireUser(request, env);
      const body = await request.json().catch(() => null);
      return json(200, await handleShipperOrder(db(env), claims, decodeURIComponent(shipperOrder[1]), body));
    }

    const respond = /^\/dispatch\/([^/]+)\/respond$/.exec(url.pathname);
    if (request.method === 'POST' && respond) {
      const claims = await requireUser(request, env);
      const body = await request.json().catch(() => null);
      return json(
        200,
        await respondOffer(db(env), claims, decodeURIComponent(respond[1]), body, new Date(), defer),
      );
    }

    const dispatch = /^\/dispatch\/([^/]+)$/.exec(url.pathname);
    if (request.method === 'POST' && dispatch) {
      const claims = await requireUser(request, env);
      const body = await request.json().catch(() => null);
      return json(
        200,
        await handleStaffDispatch(db(env), claims, decodeURIComponent(dispatch[1]), body, new Date(), defer),
      );
    }

    return error(404, 'not_found', 'Không tìm thấy');
  } catch (e) {
    if (e instanceof AuthError) return error(401, 'unauthenticated', e.message);
    if (e instanceof OrderRuleError) return error(e.status, e.code, e.message);
    if (isConflict(e)) {
      return error(409, 'conflict', 'Dữ liệu vừa thay đổi, vui lòng thử lại');
    }
    console.error('Unhandled error', e instanceof FirestoreError ? `${e.status} ${e.message}` : e);
    // Lỗi tạm thời → 500 để SePay tự gửi lại.
    return error(500, 'internal', 'Máy chủ gặp lỗi, vui lòng thử lại sau');
  }
}

async function runScheduled(env: Env, ctx: ExecutionContext): Promise<void> {
  ctx.waitUntil(
    expireUnpaidOrders(db(env)).then((n) => {
      if (n > 0) console.log(`expired ${n} unpaid order(s)`);
    }),
  );
  ctx.waitUntil(
    endStaleShifts(db(env)).then((n) => {
      if (n > 0) console.log(`auto-ended ${n} shipper shift(s)`);
    }),
  );
  ctx.waitUntil(
    runDispatchCron(db(env)).then((r) => {
      if (r.timeouts || r.offers) console.log(`dispatch: ${r.timeouts} timeout(s), ${r.offers} offer(s)`);
    }),
  );
}
