import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import '../models/order.dart';
import '../models/shipper_status.dart';
import '../services/chat_service.dart';
import '../services/order_service.dart';
import '../services/shipper_service.dart';

/// Thông tin để mở một cuộc chat (màn `/chat`).
class ChatArgs {
  final ChatRef ref;
  final String title;
  final String subtitle;

  /// Chat Meow Shop: khách là ai (NV cần để tạo cuộc chat lần đầu).
  final OrderCustomer? customer;

  /// Thẻ đơn đính kèm sẵn (mở chat từ chi tiết đơn) – gửi cùng tin đầu tiên.
  final OrderCard? attach;

  /// Nội dung soạn sẵn trong ô nhập.
  final String draft;

  const ChatArgs({
    required this.ref,
    required this.title,
    this.subtitle = '',
    this.customer,
    this.attach,
    this.draft = '',
  });
}

/// Tin mới đến khi app đang mở (main.dart hiện thanh báo).
class ChatAlert {
  final ChatArgs args;
  final String preview;

  /// NV và shipper: kèm tiếng báo + rung.
  final bool sound;

  const ChatAlert({required this.args, required this.preview, required this.sound});
}

/// Theo dõi tin chưa đọc của người đang đăng nhập (chạy suốt phiên):
/// - NV/admin: các cuộc chat Meow Shop khách đang chờ trả lời.
/// - Khách: chat Meow Shop của mình + chat shipper của đơn đang giao.
/// - Shipper: chat khách của các đơn đang giữ.
class ChatProvider extends ChangeNotifier {
  void Function(ChatAlert alert)? onIncoming;

  String? _uid;
  ChatRole? _role;
  String? _openKey;

  final List<StreamSubscription<dynamic>> _subs = [];
  final Map<String, StreamSubscription<ChatThread?>> _orderSubs = {};

  List<ChatThread> _shopUnread = const [];
  ChatThread? _myShop;
  final Map<String, ChatThread> _orderThreads = {};
  List<Order> _activeShipperOrders = const [];

  /// Giờ tin cuối đã biết của từng cuộc chat – để nhận ra tin mới.
  final Map<String, DateTime?> _seen = {};
  bool _shopPrimed = false;

  ChatRole? get role => _role;

  /// Số trên icon chat / bong bóng. NV: số cuộc chat chờ trả lời;
  /// khách, shipper: tổng số tin chưa đọc.
  int get totalUnread => switch (_role) {
        ChatRole.shop => _shopUnread.length,
        ChatRole.customer => (_myShop?.unreadFor(ChatRole.customer) ?? 0) +
            _orderThreads.values.fold(0, (s, t) => s + t.unreadFor(ChatRole.customer)),
        ChatRole.shipper =>
          _orderThreads.values.fold(0, (s, t) => s + t.unreadFor(ChatRole.shipper)),
        null => 0,
      };

  int unreadOf(ChatRef ref) {
    final me = _role;
    if (me == null) return 0;
    if (ref.kind == ChatKind.shop) {
      if (me == ChatRole.customer) return _myShop?.unreadFor(me) ?? 0;
      return _shopUnread.where((t) => t.ref == ref).fold(0, (s, t) => s + t.unreadFor(me));
    }
    return _orderThreads[ref.id]?.unreadFor(me) ?? 0;
  }

  /// Khách: đơn đang có shipper (Sẵn sàng / Đang giao / Giao thất bại) – để
  /// bong bóng chat cho chọn nhắn Meow Shop hay shipper.
  List<Order> get activeShipperOrders => _activeShipperOrders;

  /// Màn chat đang mở thì không báo tin mới của chính cuộc đó.
  void setOpen(ChatRef ref) => _openKey = ref.key;

  void clearOpen(ChatRef ref) {
    if (_openKey == ref.key) _openKey = null;
  }

  /// Gắn với phiên đăng nhập (đổi tài khoản / đăng xuất → nghe lại từ đầu).
  void bind(String? uid, ChatRole? role) {
    final id = (uid == null || uid.isEmpty) ? null : uid;
    if (id == _uid && role == _role) return;
    _reset();
    _uid = id;
    _role = id == null ? null : role;
    switch (_role) {
      case ChatRole.shop:
        _subs.add(ChatService.watchShopUnread().listen(_onShopUnread, onError: _log));
      case ChatRole.customer:
        _subs.add(ChatService.watchThread(ChatRef.shop(id!)).listen(_onMyShop, onError: _log));
        _subs.add(OrderService.watchCustomerOrders(id, limit: 10).listen(_onCustomerOrders, onError: _log));
      case ChatRole.shipper:
        _subs.add(ShipperService.watchMine(id!).listen(_onShipperStatus, onError: _log));
      case null:
        break;
    }
    notifyListeners();
  }

  void _log(Object e) => debugPrint('ChatProvider: $e');

  void _onShopUnread(List<ChatThread> threads) {
    for (final t in threads) {
      final key = t.ref.key;
      final prev = _seen[key];
      _seen[key] = t.lastMessageAt;
      // Lần nạp đầu: không báo các tin đã có sẵn.
      if (!_shopPrimed) continue;
      if (_isNew(t, prev, ChatRole.shop)) {
        _alert(
          ChatArgs(
            ref: t.ref,
            title: t.customerName.isEmpty ? 'Khách hàng' : t.customerName,
            subtitle: t.customerPhone,
            customer: OrderCustomer(id: t.ref.id, name: t.customerName, phone: t.customerPhone),
          ),
          t,
          sound: true,
        );
      }
    }
    _shopPrimed = true;
    _shopUnread = threads;
    notifyListeners();
  }

  void _onMyShop(ChatThread? t) {
    final key = ChatRef.shop(_uid ?? '').key;
    final primed = _seen.containsKey(key);
    final prev = _seen[key];
    _seen[key] = t?.lastMessageAt;
    if (t != null && primed && _isNew(t, prev, ChatRole.customer)) {
      _alert(ChatArgs(ref: t.ref, title: 'Meow Shop'), t, sound: false);
    }
    _myShop = t;
    notifyListeners();
  }

  void _onCustomerOrders(List<Order> orders) {
    _activeShipperOrders = orders.where(orderChatOpen).toList();
    _syncOrderSubs({for (final o in _activeShipperOrders) o.id});
    notifyListeners();
  }

  void _onShipperStatus(ShipperStatus s) => _syncOrderSubs(s.activeOrderIds.toSet());

  /// Nghe đúng các cuộc chat đơn đang cần (đơn mới thêm, đơn xong bỏ).
  void _syncOrderSubs(Set<String> ids) {
    for (final id in _orderSubs.keys.toList()) {
      if (!ids.contains(id)) {
        _orderSubs.remove(id)?.cancel();
        _orderThreads.remove(id);
      }
    }
    for (final id in ids) {
      if (_orderSubs.containsKey(id)) continue;
      final ref = ChatRef.order(id);
      _orderSubs[id] = ChatService.watchThread(ref).listen(
        (t) => _onOrderThread(ref, t),
        onError: _log,
      );
    }
  }

  void _onOrderThread(ChatRef ref, ChatThread? t) {
    final me = _role;
    if (me == null) return;
    final primed = _seen.containsKey(ref.key);
    final prev = _seen[ref.key];
    _seen[ref.key] = t?.lastMessageAt;
    if (t == null) {
      _orderThreads.remove(ref.id);
    } else {
      _orderThreads[ref.id] = t;
      if (primed && _isNew(t, prev, me)) {
        _alert(_orderChatArgs(ref, t), t, sound: me == ChatRole.shipper);
      }
    }
    notifyListeners();
  }

  ChatArgs _orderChatArgs(ChatRef ref, ChatThread t) {
    if (_role == ChatRole.shipper) {
      return ChatArgs(ref: ref, title: 'Khách hàng', subtitle: t.orderCode);
    }
    final order = _activeShipperOrders.where((o) => o.id == ref.id).firstOrNull;
    final shipper = order?.delivery?.shipper?.name ?? '';
    return ChatArgs(
      ref: ref,
      title: shipper.isEmpty ? 'Shipper' : 'Shipper $shipper',
      subtitle: order?.orderCode ?? t.orderCode,
    );
  }

  /// Tin cuối mới hơn lần trước, do bên kia gửi, mình chưa đọc.
  static bool isNewIncoming(ChatThread t, DateTime? prev, ChatRole me) {
    final at = t.lastMessageAt;
    if (at == null || t.lastSender == null || t.lastSender == me) return false;
    if (t.unreadFor(me) == 0) return false;
    return prev == null || at.isAfter(prev);
  }

  bool _isNew(ChatThread t, DateTime? prev, ChatRole me) =>
      t.ref.key != _openKey && isNewIncoming(t, prev, me);

  void _alert(ChatArgs args, ChatThread t, {required bool sound}) =>
      onIncoming?.call(ChatAlert(args: args, preview: t.lastText, sound: sound));

  void _reset() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    for (final s in _orderSubs.values) {
      s.cancel();
    }
    _orderSubs.clear();
    _orderThreads.clear();
    _seen.clear();
    _shopUnread = const [];
    _myShop = null;
    _activeShipperOrders = const [];
    _shopPrimed = false;
    _openKey = null;
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }
}
