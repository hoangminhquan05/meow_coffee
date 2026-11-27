# meow-coffee-api (Cloudflare Worker)

API bán online cho Meow Coffee – xem [docs/ke-hoach-ban-online.md](../docs/ke-hoach-ban-online.md).

| Endpoint | Việc |
|---|---|
| `GET /health` | Kiểm tra Worker đang chạy |
| `POST /orders` | Khách tạo đơn online (header `Authorization: Bearer <Firebase ID token>`) |
| `POST /orders/{id}/cancel` | Khách hủy đơn khi quán chưa xác nhận |
| `POST /webhooks/sepay` | SePay báo tiền vào (header `Authorization: Apikey <SEPAY_API_KEY>`) |
| `POST /admin/payments/{id}/resolve` | Admin gắn giao dịch lệch vào đơn / đánh dấu đã xử lý |
| `POST /shipper/shift` | Shipper bắt đầu ca `{action:"start", location:{lat,lng}}` / kết thúc ca `{action:"end"}` |
| `POST /dispatch/{id}` | NV/admin: `{action:"ready"}` pha xong + mời shipper, `retry`, `assign` (+`shipper_id`), `redeliver`, `cancel` (+`reason`) |
| `POST /dispatch/{id}/respond` | Shipper trả lời lời mời `{offer_id, action:"accept"|"decline"|"timeout"}` |
| `POST /shipper/orders/{id}` | Shipper: `picked_up`, `arrived`, `call`, `delivered` (+`collected:true`), `failed` (+`reason`) |
| cron mỗi phút | Hủy đơn VietQR quá hạn chuyển khoản; tự kết thúc ca shipper mất GPS > 15 phút; lời mời quá hạn → mời người tiếp, đơn chưa có shipper → mời lại |

Bí mật: `FIREBASE_SERVICE_ACCOUNT`, `SEPAY_API_KEY` (xem docs/huong-dan-cai-dat.md Phần G).

`POST /orders` body:

```json
{
  "items": [{ "product_id": "abc", "size": "M", "quantity": 2, "note": "ít đá" }],
  "address_id": "id trong users/{uid}/addresses",
  "payment_method": "cash",
  "note": "gọi trước khi tới"
}
```

Worker tự đọc giá món, địa chỉ, cài đặt quán, tính quãng đường (OSRM), kiểm giờ mở cửa / bán kính /
đơn tối thiểu, rồi sinh mã `ON-ddMMyy-NNN` và ghi đơn trong một transaction.

## Cài đặt lần đầu

```powershell
cd worker
npm install
```

### 1. Service account (bí mật – không commit, không đưa vào app)

1. Firebase Console → ⚙ Project settings → **Service accounts** → **Generate new private key** → tải file JSON.
2. Nạp lên Cloudflare:

   ```powershell
   npx wrangler login
   Get-Content -Raw D:\duong-dan\service-account.json | npx wrangler secret put FIREBASE_SERVICE_ACCOUNT
   ```

3. Chạy local: tạo file `worker/.dev.vars` (đã gitignore) chứa một dòng
   `FIREBASE_SERVICE_ACCOUNT=` + nội dung JSON viết trên **một dòng**.
4. Xóa file JSON tải về sau khi nạp xong.

### 2. Chạy thử / deploy

```powershell
npm test           # unit test
npm run typecheck
npm run dev        # http://localhost:8787  (máy ảo Android: http://10.0.2.2:8787)
npm run deploy     # in ra URL https://meow-coffee-api.<subdomain>.workers.dev
```

Sau khi deploy, điền URL vào `ORDER_API_BASE_URL` trong file `.env` của app.
