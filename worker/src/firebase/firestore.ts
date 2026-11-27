// Firestore REST tối giản cho Worker (đọc doc, query, transaction commit).
// https://firebase.google.com/docs/firestore/reference/rest
import { getAccessToken } from './serviceAccount';

// ------------------------------------------------------------ Mã hoá giá trị

export type FsValue =
  | { nullValue: null }
  | { booleanValue: boolean }
  | { integerValue: string }
  | { doubleValue: number }
  | { timestampValue: string }
  | { stringValue: string }
  | { arrayValue: { values?: FsValue[] } }
  | { mapValue: { fields?: Record<string, FsValue> } };

/** Đánh dấu giá trị là timestamp khi encode. */
export class Ts {
  constructor(readonly date: Date) {}
}

export function encodeValue(v: unknown): FsValue {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Ts) return { timestampValue: v.date.toISOString() };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeValue) } };
  if (typeof v === 'object') return { mapValue: { fields: encodeFields(v as Record<string, unknown>) } };
  throw new Error(`Cannot encode ${typeof v}`);
}

export function encodeFields(obj: Record<string, unknown>): Record<string, FsValue> {
  const out: Record<string, FsValue> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v !== undefined) out[k] = encodeValue(v);
  }
  return out;
}

export function decodeValue(v: FsValue): unknown {
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('timestampValue' in v) return new Date(v.timestampValue);
  if ('stringValue' in v) return v.stringValue;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decodeValue);
  if ('mapValue' in v) return decodeFields(v.mapValue.fields ?? {});
  return undefined;
}

export function decodeFields(fields: Record<string, FsValue>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fields)) out[k] = decodeValue(v);
  return out;
}

// ------------------------------------------------------------ Client

export interface FsDoc {
  id: string;
  name: string;
  data: Record<string, unknown>;
  updateTime?: string;
}

export interface FsWrite {
  update: { name: string; fields: Record<string, FsValue> };
  /** Chỉ ghi các trường này (giữ nguyên phần còn lại của doc). */
  updateMask?: { fieldPaths: string[] };
  currentDocument?: { exists?: boolean; updateTime?: string };
  updateTransforms?: FsTransform[];
}

export type FsTransform =
  | { fieldPath: string; setToServerValue: 'REQUEST_TIME' }
  | { fieldPath: string; appendMissingElements: { values: FsValue[] } }
  | { fieldPath: string; removeAllFromArray: { values: FsValue[] } }
  | { fieldPath: string; increment: FsValue };

/** Biến { "a.b": 1, "c": 2 } thành { a: { b: 1 }, c: 2 } (để ghi theo updateMask). */
export function nestFields(flat: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [path, value] of Object.entries(flat)) {
    const parts = path.split('.');
    let cur = out;
    for (const p of parts.slice(0, -1)) {
      if (!cur[p] || typeof cur[p] !== 'object' || cur[p] instanceof Ts || Array.isArray(cur[p])) cur[p] = {};
      cur = cur[p] as Record<string, unknown>;
    }
    cur[parts[parts.length - 1]] = value;
  }
  return out;
}

/** Ghi một số trường (có thể lồng "a.b") của doc, giữ nguyên phần còn lại. */
export function patchWrite(
  name: string,
  flat: Record<string, unknown>,
  opts: {
    updateTime?: string;
    exists?: boolean;
    transforms?: FsTransform[];
  } = {},
): FsWrite {
  const precondition =
    opts.updateTime !== undefined
      ? { updateTime: opts.updateTime }
      : opts.exists !== undefined
        ? { exists: opts.exists }
        : undefined;
  return {
    update: { name, fields: encodeFields(nestFields(flat)) },
    updateMask: { fieldPaths: Object.keys(flat) },
    ...(precondition ? { currentDocument: precondition } : {}),
    ...(opts.transforms?.length ? { updateTransforms: opts.transforms } : {}),
  };
}

export const serverTime = (fieldPath: string): FsTransform => ({
  fieldPath,
  setToServerValue: 'REQUEST_TIME',
});
export const arrayAppend = (fieldPath: string, ...values: unknown[]): FsTransform => ({
  fieldPath,
  appendMissingElements: { values: values.map(encodeValue) },
});
export const arrayRemove = (fieldPath: string, ...values: unknown[]): FsTransform => ({
  fieldPath,
  removeAllFromArray: { values: values.map(encodeValue) },
});
export const increment = (fieldPath: string, by: number): FsTransform => ({
  fieldPath,
  increment: encodeValue(by),
});

export class FirestoreError extends Error {
  constructor(message: string, readonly status: number, readonly code?: string) {
    super(message);
  }
}

export class Firestore {
  readonly root: string;
  private readonly base: string;

  constructor(
    readonly projectId: string,
    private readonly serviceAccount: string | undefined,
  ) {
    this.root = `projects/${projectId}/databases/(default)/documents`;
    this.base = `https://firestore.googleapis.com/v1/${this.root}`;
  }

  /** Tên đầy đủ của doc từ đường dẫn tương đối "users/abc". */
  docName(path: string): string {
    return `${this.root}/${path}`;
  }

  private async call(url: string, init: RequestInit = {}): Promise<unknown> {
    const token = await getAccessToken(this.serviceAccount);
    const res = await fetch(url, {
      ...init,
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
        ...(init.headers ?? {}),
      },
    });
    const body = (await res.json().catch(() => ({}))) as {
      error?: { message?: string; status?: string };
    };
    if (!res.ok) {
      throw new FirestoreError(
        body.error?.message ?? `Firestore ${res.status}`,
        res.status,
        body.error?.status,
      );
    }
    return body;
  }

  /** Phiên đọc của runOptimistic: tên doc → updateTime lúc đọc (null = chưa có). */
  private readonly sessions = new Map<string, Map<string, string | null>>();

  /**
   * Đọc một doc; không tồn tại → null. `transaction` là mã transaction thật
   * (runTransaction) hoặc mã phiên của runOptimistic (đọc thường + ghi nhớ phiên bản).
   */
  async get(path: string, transaction?: string): Promise<FsDoc | null> {
    const session = transaction ? this.sessions.get(transaction) : undefined;
    if (session) {
      const doc = await this.get(path);
      session.set(this.docName(path), doc?.updateTime ?? null);
      return doc;
    }
    const qs = transaction ? `?transaction=${encodeURIComponent(transaction)}` : '';
    try {
      const doc = (await this.call(`${this.base}/${path}${qs}`)) as {
        name: string;
        fields?: Record<string, FsValue>;
        updateTime?: string;
      };
      return {
        name: doc.name,
        id: doc.name.split('/').pop()!,
        data: decodeFields(doc.fields ?? {}),
        updateTime: doc.updateTime,
      };
    } catch (e) {
      if (e instanceof FirestoreError && e.status === 404) return null;
      throw e;
    }
  }

  /** Đọc nhiều doc theo đường dẫn (batchGet), giữ thứ tự; thiếu → null. */
  async getMany(paths: string[]): Promise<(FsDoc | null)[]> {
    if (paths.length === 0) return [];
    const res = (await this.call(`${this.base}:batchGet`, {
      method: 'POST',
      body: JSON.stringify({ documents: paths.map((p) => this.docName(p)) }),
    })) as {
      found?: { name: string; fields?: Record<string, FsValue>; updateTime?: string };
      missing?: string;
    }[];
    const byName = new Map<string, FsDoc>();
    for (const r of res) {
      if (r.found) {
        byName.set(r.found.name, {
          name: r.found.name,
          id: r.found.name.split('/').pop()!,
          data: decodeFields(r.found.fields ?? {}),
          // Cần cho điều kiện ghi "doc chưa đổi" (currentDocument.updateTime).
          updateTime: r.found.updateTime,
        });
      }
    }
    return paths.map((p) => byName.get(this.docName(p)) ?? null);
  }

  /** Lấy các doc trong collection thỏa field == value (tối đa `limit`). */
  async findWhere(
    collection: string,
    field: string,
    value: unknown,
    limit = 50,
  ): Promise<FsDoc[]> {
    const res = (await this.call(`${this.base}:runQuery`, {
      method: 'POST',
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: collection }],
          where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: encodeValue(value) } },
          limit,
        },
      }),
    })) as { document?: { name: string; fields?: Record<string, FsValue>; updateTime?: string } }[];
    return res
      .filter((r) => r.document)
      .map((r) => ({
        name: r.document!.name,
        id: r.document!.name.split('/').pop()!,
        data: decodeFields(r.document!.fields ?? {}),
        updateTime: r.document!.updateTime,
      }));
  }

  /** Đếm doc trong collection thỏa field == value. */
  async countWhere(collection: string, field: string, value: unknown): Promise<number> {
    const res = (await this.call(`${this.base}:runAggregationQuery`, {
      method: 'POST',
      body: JSON.stringify({
        structuredAggregationQuery: {
          structuredQuery: {
            from: [{ collectionId: collection }],
            where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: encodeValue(value) } },
          },
          aggregations: [{ alias: 'n', count: {} }],
        },
      }),
    })) as { result?: { aggregateFields?: { n?: FsValue } } }[];
    const n = res[0]?.result?.aggregateFields?.n;
    return n ? Number(decodeValue(n)) : 0;
  }

  async beginTransaction(): Promise<string> {
    const res = (await this.call(`${this.base}:beginTransaction`, {
      method: 'POST',
      body: JSON.stringify({ options: { readWrite: {} } }),
    })) as { transaction: string };
    return res.transaction;
  }

  async commit(writes: FsWrite[], transaction?: string): Promise<void> {
    await this.call(`${this.base}:commit`, {
      method: 'POST',
      body: JSON.stringify({ writes, ...(transaction ? { transaction } : {}) }),
    });
  }

  async rollback(transaction: string): Promise<void> {
    await this.call(`${this.base}:rollback`, {
      method: 'POST',
      body: JSON.stringify({ transaction }),
    }).catch(() => undefined);
  }

  /**
   * Giống runTransaction nhưng KHÔNG giữ khóa: đọc thường, rồi ghi một lần kèm
   * điều kiện "doc chưa đổi kể từ lúc đọc" (currentDocument.updateTime) cho mọi
   * doc đã đọc; có người sửa xen giữa → đọc lại và thử lại.
   * Dùng cho các thao tác giao hàng: Worker bị ngắt giữa chừng (hết giờ, khách
   * đóng kết nối) không để lại khóa làm các request sau phải chờ.
   * Không dùng cho bộ đếm cần tăng tuần tự (createOrder vẫn dùng runTransaction).
   */
  async runOptimistic<T>(fn: (session: string) => Promise<{ writes: FsWrite[]; result: T }>): Promise<T> {
    for (let attempt = 0; attempt < 5; attempt++) {
      const session = `opt_${crypto.randomUUID()}`;
      const seen = new Map<string, string | null>();
      this.sessions.set(session, seen);
      try {
        const { writes, result } = await fn(session);
        if (writes.length > 0) {
          await this.commit(
            writes.map((w) =>
              w.currentDocument || !seen.has(w.update.name)
                ? w
                : {
                    ...w,
                    currentDocument: seen.get(w.update.name)
                      ? { updateTime: seen.get(w.update.name)! }
                      : { exists: false },
                  },
            ),
          );
        }
        return result;
      } catch (e) {
        const retryable =
          e instanceof FirestoreError &&
          (e.code === 'FAILED_PRECONDITION' || e.code === 'ABORTED' || e.status === 409);
        if (!retryable || attempt === 4) throw e;
        await new Promise((r) => setTimeout(r, 50 * 2 ** attempt));
      } finally {
        this.sessions.delete(session);
      }
    }
    throw new Error('unreachable');
  }

  /** Chạy transaction, tự thử lại khi bị ABORTED (xung đột ghi). */
  async runTransaction<T>(fn: (tx: string) => Promise<{ writes: FsWrite[]; result: T }>): Promise<T> {
    for (let attempt = 0; attempt < 5; attempt++) {
      const tx = await this.beginTransaction();
      try {
        const { writes, result } = await fn(tx);
        await this.commit(writes, tx);
        return result;
      } catch (e) {
        await this.rollback(tx);
        const retryable = e instanceof FirestoreError && (e.code === 'ABORTED' || e.status === 409);
        if (!retryable || attempt === 4) throw e;
        await new Promise((r) => setTimeout(r, 50 * 2 ** attempt));
      }
    }
    throw new Error('unreachable');
  }
}
