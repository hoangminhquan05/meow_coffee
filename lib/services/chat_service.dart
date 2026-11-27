import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:image_picker/image_picker.dart';

import '../config/env_config.dart';
import '../core/enums.dart';
import '../core/firestore_paths.dart';
import '../models/chat.dart';
import '../models/order.dart';
import 'cloudinary_service.dart';
import 'order_service.dart';

/// Chat Meow Shop + chat shipper (bước 10). App ghi thẳng Firestore:
/// mỗi lần gửi là 1 batch (tin nhắn + cập nhật đầu cuộc chat [+ tên NV thật]),
/// Rules kiểm người gửi, nội dung, bộ đếm chưa đọc.
class ChatService {
  ChatService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> threadDoc(ChatRef ref) =>
      _db.collection(ref.collection).doc(ref.id);

  static CollectionReference<Map<String, dynamic>> _messages(ChatRef ref) =>
      threadDoc(ref).collection(FsCollections.messages);

  /// Mẫu câu nhanh cho NV (bấm là điền vào ô nhập, sửa được trước khi gửi).
  static const quickReplies = [
    'Chào bạn, Meow Shop có thể giúp gì cho bạn ạ?',
    'Món … hiện đã hết, bạn muốn đổi sang món khác không ạ?',
    'Quán đã nhận đơn và đang pha chế, bạn chờ chút nhé!',
    'Đơn của bạn đã giao cho shipper, bạn để ý điện thoại giúp quán nhé.',
    'Bạn gửi giúp quán thông tin nhận hoàn tiền: Ngân hàng – Số tài khoản – Tên chủ tài khoản nhé.',
    'Quán đã chuyển khoản hoàn tiền, bạn kiểm tra giúp quán nhé. Cảm ơn bạn!',
    'Cảm ơn bạn đã ủng hộ Meow Coffee! 🐱',
  ];

  /// Tin nhắn soạn sẵn khi khách gửi thông tin nhận hoàn tiền (O32).
  static String refundDraft(Order o) =>
      'Thông tin nhận hoàn tiền đơn ${o.orderCode}:\nNgân hàng: \nSố tài khoản: \nTên chủ tài khoản: ';

  /// Tin nhắn soạn sẵn khi admin xin số tài khoản để hoàn tiền.
  static String askRefundDraft(Order o, String amount) =>
      'Chào bạn, quán cần hoàn $amount cho đơn ${o.orderCode}. '
      'Bạn gửi giúp quán: Ngân hàng – Số tài khoản – Tên chủ tài khoản nhé.';

  static Stream<ChatThread?> watchThread(ChatRef ref) => threadDoc(ref)
      .snapshots()
      .map((d) => d.exists ? ChatThread.fromDoc(ref, d) : null);

  /// Tin nhắn mới nhất trước (màn chat dùng ListView đảo ngược).
  static Stream<List<ChatMessage>> watchMessages(ChatRef ref, {int limit = 200}) =>
      _messages(ref)
          .orderBy('created_at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  /// Hộp thư Meow Shop: cuộc chat có tin mới nhất trước.
  static Stream<List<ChatThread>> watchShopInbox({int limit = 100}) => _db
      .collection(FsCollections.shopChats)
      .orderBy('last_message_at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => ChatThread.fromDoc(ChatRef.shop(d.id), d)).toList());

  /// Cuộc chat Meow Shop khách đang chờ trả lời (số trên icon chat của NV).
  static Stream<List<ChatThread>> watchShopUnread() => _db
      .collection(FsCollections.shopChats)
      .where('unread_shop', isGreaterThan: 0)
      .snapshots()
      .map((s) => s.docs.map((d) => ChatThread.fromDoc(ChatRef.shop(d.id), d)).toList());

  /// NV nào đã trả lời từng tin "Meow Shop" (chỉ NV/admin đọc được – O31).
  static Stream<Map<String, String>> watchAuthors(String customerUid) => _db
      .collection(FsCollections.shopMessageAuthors)
      .where('chat_id', isEqualTo: customerUid)
      .snapshots()
      .map((s) => {
            for (final d in s.docs)
              d.id: (d.data()['staff'] as Map?)?['name']?.toString() ?? '',
          });

  /// Gửi 1 tin. `customer` bắt buộc với chat shop (để NV thấy tên/SĐT khách);
  /// `orderCode` bắt buộc với chat đơn. NV gửi thì ghi kèm tên thật vào
  /// `shop_message_authors` – khách chỉ thấy "Meow Shop".
  static Future<void> send({
    required ChatRef ref,
    required ChatRole as,
    required PersonRef sender,
    String text = '',
    String imageUrl = '',
    OrderCard? order,
    OrderCustomer? customer,
    String orderCode = '',
  }) async {
    final body = text.trim();
    final type = order != null
        ? MessageType.order
        : imageUrl.isNotEmpty
            ? MessageType.image
            : MessageType.text;
    if (type == MessageType.text && body.isEmpty) return;
    if (body.length > chatMaxTextLength) {
      throw StateError('Tin nhắn tối đa $chatMaxTextLength ký tự');
    }
    if (type == MessageType.order && ref.kind != ChatKind.shop) {
      throw StateError('Chỉ gửi thẻ đơn trong chat Meow Shop');
    }

    final msgRef = _messages(ref).doc();
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.set(msgRef, {
      'sender_role': as.value,
      'sender_id': as == ChatRole.shop ? 'meowshop' : sender.id,
      'type': type.value,
      if (type == MessageType.text) 'text': body,
      if (type == MessageType.image) 'image_url': imageUrl,
      if (type == MessageType.order) 'order_ref': order!.toMap(),
      'created_at': now,
    });
    batch.set(
      threadDoc(ref),
      {
        if (ref.kind == ChatKind.shop && customer != null)
          'customer': {'id': ref.id, 'name': customer.name, 'phone': customer.phone},
        if (ref.kind == ChatKind.order) ...{
          'order_id': ref.id,
          if (orderCode.isNotEmpty) 'order_code': orderCode,
        },
        'last_message': {
          'text': ChatMessage.previewOf(type, text: body, orderCode: order?.code ?? ''),
          'sender_role': as.value,
        },
        'last_message_at': now,
        // Gửi tin = đã đọc hết; bên kia thêm 1 tin chưa đọc.
        ref.unreadField(as): 0,
        ref.unreadField(ref.otherSide(as)): FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );
    if (as == ChatRole.shop) {
      batch.set(_db.collection(FsCollections.shopMessageAuthors).doc(msgRef.id), {
        'chat_id': ref.id,
        'staff': sender.toMap(),
        'created_at': now,
      });
    }
    await batch.commit();
  }

  /// Tải ảnh lên Cloudinary (thư mục chat) rồi gửi.
  static Future<void> sendImage({
    required ChatRef ref,
    required ChatRole as,
    required PersonRef sender,
    required XFile file,
    OrderCustomer? customer,
    String orderCode = '',
  }) async {
    final url = await CloudinaryService.instance
        .uploadImage(file, folder: EnvConfig.cloudinaryFolderChat);
    await send(
      ref: ref,
      as: as,
      sender: sender,
      imageUrl: url,
      customer: customer,
      orderCode: orderCode,
    );
  }

  /// Mở cuộc chat → về 0 tin chưa đọc của mình (chỉ ghi khi đang > 0).
  static Future<void> markRead(ChatRef ref, ChatRole role) =>
      threadDoc(ref).update({ref.unreadField(role): 0});

  /// Đơn online của khách – để chọn gửi thẻ đơn (khách: đơn của mình;
  /// NV: đơn của khách đang chat). Bỏ đơn còn chờ chuyển khoản.
  static Stream<List<Order>> watchCustomerOrders(String customerUid) =>
      OrderService.watchCustomerOrders(customerUid, limit: 20).map(
          (list) => list.where((o) => o.status != OrderStatus.awaitingPayment).toList());
}
