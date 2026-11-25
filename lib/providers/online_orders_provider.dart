import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/enums.dart';
import '../models/order.dart';
import '../services/staff_order_service.dart';

/// Đơn online đang xử lý cho NV/admin (realtime, chạy suốt phiên đăng nhập):
/// cấp số đếm cho thanh điều hướng và báo khi có đơn mới vào "Chờ xác nhận".
class OnlineOrdersProvider extends ChangeNotifier {
  StreamSubscription<List<Order>>? _sub;
  bool _enabled = false;
  bool _loaded = false;
  Object? _error;
  List<Order> _orders = const [];

  /// Đơn "Chờ xác nhận" đã biết – để phát hiện đơn mới.
  Set<String> _knownPending = {};

  /// Gọi khi có đơn mới vào "Chờ xác nhận" (main.dart phát âm thanh + thông báo).
  void Function(Order order)? onNewOrder;

  List<Order> get orders => _orders;
  bool get isLoaded => _loaded;
  Object? get error => _error;

  int get pendingCount =>
      _orders.where((o) => o.status == OrderStatus.pending).length;

  List<Order> byStatuses(Set<OrderStatus> statuses) =>
      _orders.where((o) => statuses.contains(o.status)).toList();

  /// Bật khi người dùng là NV/admin, tắt khi đăng xuất / đổi vai trò.
  void setEnabled(bool enabled) {
    if (enabled == _enabled) return;
    _enabled = enabled;
    _sub?.cancel();
    _sub = null;
    _orders = const [];
    _knownPending = {};
    _loaded = false;
    _error = null;
    if (enabled) _listen();
    notifyListeners();
  }

  void _listen() {
    _sub = StaffOrderService.watchActive().listen((orders) {
      final pending = {
        for (final o in orders)
          if (o.status == OrderStatus.pending) o.id,
      };
      // Lần đầu nạp: không báo các đơn đã có sẵn.
      if (_loaded) {
        for (final o in orders) {
          if (o.status == OrderStatus.pending && !_knownPending.contains(o.id)) {
            onNewOrder?.call(o);
          }
        }
      }
      _knownPending = pending;
      _orders = orders;
      _loaded = true;
      _error = null;
      notifyListeners();
    }, onError: (Object e) {
      debugPrint('OnlineOrdersProvider stream error: $e');
      _error = e;
      _loaded = true;
      notifyListeners();
    });
  }

  /// Thử nghe lại sau lỗi (ví dụ index đang tạo).
  void retry() {
    if (!_enabled) return;
    _sub?.cancel();
    _error = null;
    _loaded = false;
    _listen();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
