import 'online_order_service.dart';

/// NV/admin thao tác giao hàng qua Worker (`POST /dispatch/{id}`, bước 9).
class DispatchService {
  DispatchService._();

  static Future<Map<String, dynamic>> _post(String orderId, Map<String, dynamic> body) =>
      OnlineOrderService.post('/dispatch/$orderId', body, okStatus: 200);

  /// Pha xong → Sẵn sàng, Worker mời shipper ngay.
  static Future<void> markReady(String orderId) => _post(orderId, {'action': 'ready'});

  /// Mời lại từ đầu (kể cả shipper đã từ chối).
  static Future<void> retry(String orderId) => _post(orderId, {'action': 'retry'});

  /// Gán thẳng cho shipper trong ca (đơn chưa lấy hàng).
  static Future<void> assign(String orderId, String shipperId) =>
      _post(orderId, {'action': 'assign', 'shipper_id': shipperId});

  /// Giao thất bại → giao lại (+1 lần phí ship nếu đang bật phí – O33).
  static Future<void> redeliver(String orderId) => _post(orderId, {'action': 'redeliver'});

  /// Hủy đơn Sẵn sàng (hoàn tiền nếu đã trả) hoặc Giao thất bại (không hoàn – O21).
  static Future<void> cancel(String orderId, String reason) =>
      _post(orderId, {'action': 'cancel', 'reason': reason});
}
