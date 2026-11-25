import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/env_config.dart';
import '../core/enums.dart';
import '../providers/customer_cart_provider.dart';

/// Lỗi gọi API đơn online (thông báo tiếng Việt từ Worker).
class OnlineOrderError implements Exception {
  final String code;
  final String message;
  const OnlineOrderError(this.code, this.message);
  @override
  String toString() => message;
}

class OnlineOrderResult {
  final String orderId;
  final String orderCode;
  final OrderStatus status;
  final int total;
  final PaymentMethod paymentMethod;
  final DateTime? paymentExpiresAt;
  final double distanceKm;

  const OnlineOrderResult({
    required this.orderId,
    required this.orderCode,
    required this.status,
    required this.total,
    required this.paymentMethod,
    required this.paymentExpiresAt,
    required this.distanceKm,
  });
}

/// Lý do khách hủy đơn (chọn nhanh; "Khác" thì gõ thêm).
const customerCancelReasons = [
  'Đổi ý, không muốn mua nữa',
  'Đặt nhầm món / số lượng',
  'Sai địa chỉ giao hàng',
  'Muốn đổi phương thức thanh toán',
  'Chờ quán xác nhận quá lâu',
  'Khác',
];

/// Gọi Cloudflare Worker (O28). App chỉ gửi mã món, size, số lượng, ghi chú,
/// mã địa chỉ – giá và tổng tiền do Worker tính.
class OnlineOrderService {
  OnlineOrderService._();

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    required int okStatus,
  }) async {
    final base = EnvConfig.orderApiBaseUrl.replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      throw const OnlineOrderError('config', 'Chưa cấu hình ORDER_API_BASE_URL trong .env');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const OnlineOrderError('unauthenticated', 'Bạn chưa đăng nhập');
    final token = await user.getIdToken();

    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$base$path'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const OnlineOrderError('network', 'Không kết nối được máy chủ, vui lòng thử lại');
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw OnlineOrderError('bad_response', 'Máy chủ trả lời không hợp lệ (${res.statusCode})');
    }
    if (res.statusCode != okStatus) {
      final err = json['error'] as Map<String, dynamic>? ?? const {};
      throw OnlineOrderError(
        err['code'] as String? ?? 'error',
        err['message'] as String? ?? 'Có lỗi xảy ra (${res.statusCode})',
      );
    }
    return json;
  }

  /// `POST /orders` – tạo đơn online.
  static Future<OnlineOrderResult> create({
    required List<CustomerCartLine> items,
    required String addressId,
    required PaymentMethod method,
    String note = '',
  }) async {
    final body = await _post(
      '/orders',
      {
        'items': [for (final i in items) i.toMap()],
        'address_id': addressId,
        'payment_method': method.value,
        'note': note.trim(),
      },
      okStatus: 201,
    );
    final expires = body['payment_expires_at'] as String?;
    return OnlineOrderResult(
      orderId: body['order_id'] as String,
      orderCode: body['order_code'] as String,
      status: OrderStatus.fromValue(body['status'] as String?),
      total: (body['total'] as num).round(),
      paymentMethod: PaymentMethod.fromValue(body['payment_method'] as String?),
      paymentExpiresAt: expires == null ? null : DateTime.parse(expires).toLocal(),
      distanceKm: (body['distance_km'] as num).toDouble(),
    );
  }

  /// `POST /orders/{id}/cancel` – khách hủy khi quán chưa xác nhận (O15).
  static Future<void> cancel(String orderId, String reason) async {
    await _post('/orders/$orderId/cancel', {'reason': reason.trim()}, okStatus: 200);
  }

  /// Admin gắn giao dịch lệch vào một đơn (đơn thành đã trả, chờ xác nhận).
  static Future<void> attachPayment(String txId, String orderCode, {String note = ''}) async {
    await _post(
      '/admin/payments/$txId/resolve',
      {'action': 'attach', 'order_code': orderCode.trim().toUpperCase(), 'note': note.trim()},
      okStatus: 200,
    );
  }

  /// Admin đánh dấu đã xử lý ngoài app (hoàn tiền tay / bỏ qua) kèm ghi chú.
  static Future<void> dismissPayment(String txId, String note) async {
    await _post(
      '/admin/payments/$txId/resolve',
      {'action': 'dismiss', 'note': note.trim()},
      okStatus: 200,
    );
  }
}
