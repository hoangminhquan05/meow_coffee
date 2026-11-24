import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/env_config.dart';
import '../core/enums.dart';
import '../providers/cart_provider.dart';

/// Lỗi tạo đơn online (thông báo tiếng Việt từ Worker).
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

/// Gọi Cloudflare Worker `POST /orders` (O28). App chỉ gửi mã món, size,
/// số lượng, ghi chú, mã địa chỉ – giá và tổng tiền do Worker tính.
class OnlineOrderService {
  OnlineOrderService._();

  static Future<OnlineOrderResult> create({
    required List<CartItem> items,
    required String addressId,
    required PaymentMethod method,
    String note = '',
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
            Uri.parse('$base/orders'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'items': [
                for (final i in items)
                  {
                    'product_id': i.product.id,
                    'size': i.size,
                    'quantity': i.quantity,
                    'note': i.note,
                  },
              ],
              'address_id': addressId,
              'payment_method': method.value,
              'note': note.trim(),
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const OnlineOrderError('network', 'Không kết nối được máy chủ, vui lòng thử lại');
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 201) {
      final err = body['error'] as Map<String, dynamic>? ?? const {};
      throw OnlineOrderError(
        err['code'] as String? ?? 'error',
        err['message'] as String? ?? 'Đặt đơn thất bại (${res.statusCode})',
      );
    }
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
}
