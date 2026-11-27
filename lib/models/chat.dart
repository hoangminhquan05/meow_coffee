import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:intl/intl.dart';

import '../core/enums.dart';
import '../core/firestore_paths.dart';
import 'order.dart';

/// Hai loại cuộc chat (bước 10, mục 7 kế hoạch online):
/// - `shop`: mỗi khách 1 cuộc cố định với "Meow Shop" – `shop_chats/{customerUid}`.
/// - `order`: shipper ↔ khách theo đơn – `order_chats/{orderId}`.
enum ChatKind { shop, order }

/// Ai gửi tin. NV/admin luôn gửi dưới tên "Meow Shop" (O31).
enum ChatRole {
  customer('customer'),
  shop('shop'),
  shipper('shipper');

  final String value;
  const ChatRole(this.value);

  static ChatRole fromValue(String? v) =>
      ChatRole.values.firstWhere((r) => r.value == v, orElse: () => ChatRole.customer);

  /// Vai trò chat của người đang đăng nhập.
  static ChatRole? forUser(UserRole? role) => switch (role) {
        UserRole.customer => ChatRole.customer,
        UserRole.shipper => ChatRole.shipper,
        UserRole.staff || UserRole.admin => ChatRole.shop,
        _ => null,
      };
}

/// Địa chỉ một cuộc chat.
class ChatRef {
  final ChatKind kind;

  /// `customerUid` (shop) hoặc `orderId` (order).
  final String id;

  const ChatRef.shop(String customerUid) : this._(ChatKind.shop, customerUid);
  const ChatRef.order(String orderId) : this._(ChatKind.order, orderId);
  const ChatRef._(this.kind, this.id);

  String get collection =>
      kind == ChatKind.shop ? FsCollections.shopChats : FsCollections.orderChats;

  /// Khóa duy nhất (để biết cuộc chat nào đang mở, tránh báo trùng).
  String get key => '${kind.name}:$id';

  /// Trường "chưa đọc" của một bên trong cuộc chat này.
  String unreadField(ChatRole role) => 'unread_${role.value}';

  /// Bên nhận tin khi `sender` gửi.
  ChatRole otherSide(ChatRole sender) => kind == ChatKind.shop
      ? (sender == ChatRole.customer ? ChatRole.shop : ChatRole.customer)
      : (sender == ChatRole.customer ? ChatRole.shipper : ChatRole.customer);

  @override
  bool operator ==(Object other) => other is ChatRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;
int _int(Object? v) => v is num ? v.toInt() : 0;

/// Thông tin đầu một cuộc chat (doc `shop_chats/*` hoặc `order_chats/*`).
class ChatThread {
  final ChatRef ref;

  /// Chỉ chat shop: khách là ai (NV không đọc được `users/*` nên lưu kèm).
  final String customerName;
  final String customerPhone;

  /// Chỉ chat đơn.
  final String orderCode;

  final String lastText;
  final ChatRole? lastSender;
  final DateTime? lastMessageAt;
  final Map<ChatRole, int> unread;

  const ChatThread({
    required this.ref,
    this.customerName = '',
    this.customerPhone = '',
    this.orderCode = '',
    this.lastText = '',
    this.lastSender,
    this.lastMessageAt,
    this.unread = const {},
  });

  int unreadFor(ChatRole role) => unread[role] ?? 0;

  factory ChatThread.fromMap(ChatRef ref, Map<String, dynamic> m) {
    final customer = m['customer'] is Map ? Map<String, dynamic>.from(m['customer']) : const {};
    final last = m['last_message'] is Map ? Map<String, dynamic>.from(m['last_message']) : const {};
    return ChatThread(
      ref: ref,
      customerName: customer['name']?.toString() ?? '',
      customerPhone: customer['phone']?.toString() ?? '',
      orderCode: m['order_code']?.toString() ?? '',
      lastText: last['text']?.toString() ?? '',
      lastSender: last['sender_role'] == null ? null : ChatRole.fromValue(last['sender_role']),
      lastMessageAt: _ts(m['last_message_at']),
      unread: {for (final r in ChatRole.values) r: _int(m['unread_${r.value}'])},
    );
  }

  factory ChatThread.fromDoc(ChatRef ref, DocumentSnapshot<Map<String, dynamic>> d) =>
      ChatThread.fromMap(ref, d.data() ?? const {});
}

enum MessageType {
  text('text'),
  image('image'),
  order('order');

  final String value;
  const MessageType(this.value);

  static MessageType fromValue(String? v) =>
      MessageType.values.firstWhere((t) => t.value == v, orElse: () => MessageType.text);
}

/// Thẻ đơn hàng gửi trong chat: chụp mã, trạng thái, tổng tiền lúc gửi.
class OrderCard {
  final String id;
  final String code;
  final String status;
  final int total;

  const OrderCard({required this.id, required this.code, this.status = '', this.total = 0});

  factory OrderCard.of(Order o) =>
      OrderCard(id: o.id, code: o.orderCode, status: o.status.value, total: o.total);

  factory OrderCard.fromMap(Map<String, dynamic> m) => OrderCard(
        id: m['id']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
        status: m['status']?.toString() ?? '',
        total: _int(m['total']),
      );

  Map<String, dynamic> toMap() => {'id': id, 'code': code, 'status': status, 'total': total};
}

class ChatMessage {
  final String id;
  final ChatRole senderRole;
  final String senderId;
  final MessageType type;
  final String text;
  final String imageUrl;
  final OrderCard? order;

  /// null khi tin vừa gửi chưa lên máy chủ (giờ server chưa có).
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.senderRole,
    this.senderId = '',
    this.type = MessageType.text,
    this.text = '',
    this.imageUrl = '',
    this.order,
    this.createdAt,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> m) => ChatMessage(
        id: id,
        senderRole: ChatRole.fromValue(m['sender_role']?.toString()),
        senderId: m['sender_id']?.toString() ?? '',
        type: MessageType.fromValue(m['type']?.toString()),
        text: m['text']?.toString() ?? '',
        imageUrl: m['image_url']?.toString() ?? '',
        order: m['order_ref'] is Map
            ? OrderCard.fromMap(Map<String, dynamic>.from(m['order_ref']))
            : null,
        createdAt: _ts(m['created_at']),
      );

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) =>
      ChatMessage.fromMap(d.id, d.data() ?? const {});

  /// Dòng tóm tắt cho danh sách chat / thông báo.
  String get preview => previewOf(type, text: text, orderCode: order?.code ?? '');

  static String previewOf(MessageType type, {String text = '', String orderCode = ''}) =>
      switch (type) {
        MessageType.image => '📷 Hình ảnh',
        MessageType.order => '🧾 Đơn $orderCode',
        MessageType.text => text.length > 80 ? '${text.substring(0, 80)}…' : text,
      };
}

/// Giới hạn độ dài tin văn bản (Rules kiểm cùng con số).
const chatMaxTextLength = 1000;

/// Ảnh nhỏ để hiện trong bong bóng chat: nhờ Cloudinary thu về rộng tối đa
/// [width]px (ảnh gốc ~750 KB → ~50 KB, tải nhanh hơn, ít lỗi hơn). Xem phóng
/// to vẫn dùng ảnh gốc. Link không phải ảnh Cloudinary thì giữ nguyên.
String chatThumbUrl(String url, {int width = 600}) {
  const marker = '/image/upload/';
  final i = url.indexOf(marker);
  if (!url.startsWith('https://res.cloudinary.com/') || i < 0) return url;
  final at = i + marker.length;
  return '${url.substring(0, at)}w_$width,c_limit,q_auto/${url.substring(at)}';
}

/// Chat shipper–khách gửi được khi đơn đã có shipper và chưa kết thúc:
/// Sẵn sàng (đã có người nhận) · Đang giao · Giao thất bại. Hoàn tất / Hủy → chỉ đọc.
bool orderChatOpen(Order o) =>
    o.delivery?.shipper != null &&
    const {OrderStatus.ready, OrderStatus.delivering, OrderStatus.deliveryFailed}
        .contains(o.status);

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Nhãn ngày chen giữa các tin: Hôm nay / Hôm qua / dd/MM/yyyy.
String chatDayLabel(DateTime day, DateTime now) {
  if (_sameDay(day, now)) return 'Hôm nay';
  if (_sameDay(day, now.subtract(const Duration(days: 1)))) return 'Hôm qua';
  return DateFormat('dd/MM/yyyy').format(day);
}

/// Giờ tin cuối trong danh sách chat: HH:mm (hôm nay) / Hôm qua / dd/MM.
String chatListTime(DateTime at, DateTime now) {
  if (_sameDay(at, now)) return DateFormat('HH:mm').format(at);
  if (_sameDay(at, now.subtract(const Duration(days: 1)))) return 'Hôm qua';
  return DateFormat('dd/MM').format(at);
}
