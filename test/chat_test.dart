import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_coffee/core/enums.dart';
import 'package:meow_coffee/core/route_guard.dart';
import 'package:meow_coffee/models/chat.dart';
import 'package:meow_coffee/models/order.dart';
import 'package:meow_coffee/providers/chat_provider.dart';

Order _order(String status, {bool shipper = true}) => Order.fromMap({
      'channel': 'online',
      'status': status,
      'total': 50000,
      'delivery': {
        if (shipper) 'shipper': {'id': 's1', 'name': 'An'},
      },
    }, id: 'o1');

ChatThread _thread({
  ChatRole? last,
  DateTime? at,
  int unreadShop = 0,
  int unreadCustomer = 0,
}) =>
    ChatThread.fromMap(const ChatRef.shop('c1'), {
      'customer': {'id': 'c1', 'name': 'Lan', 'phone': '0901'},
      if (last != null) 'last_message': {'text': 'Xin chào', 'sender_role': last.value},
      if (at != null) 'last_message_at': Timestamp.fromDate(at),
      'unread_shop': unreadShop,
      'unread_customer': unreadCustomer,
    });

void main() {
  test('chat refs: collection, key, who gets the unread count', () {
    const shop = ChatRef.shop('c1');
    const order = ChatRef.order('o1');
    expect(shop.collection, 'shop_chats');
    expect(order.collection, 'order_chats');
    expect(shop.key, isNot(order.key));
    expect(shop.otherSide(ChatRole.customer), ChatRole.shop);
    expect(shop.otherSide(ChatRole.shop), ChatRole.customer);
    expect(order.otherSide(ChatRole.customer), ChatRole.shipper);
    expect(order.otherSide(ChatRole.shipper), ChatRole.customer);
    expect(order.unreadField(ChatRole.shipper), 'unread_shipper');
  });

  test('staff and admin both chat as Meow Shop', () {
    expect(ChatRole.forUser(UserRole.staff), ChatRole.shop);
    expect(ChatRole.forUser(UserRole.admin), ChatRole.shop);
    expect(ChatRole.forUser(UserRole.customer), ChatRole.customer);
    expect(ChatRole.forUser(UserRole.shipper), ChatRole.shipper);
  });

  test('thread parses customer, last message and unread counters', () {
    final t = _thread(last: ChatRole.customer, at: DateTime(2026, 11, 27, 9), unreadShop: 2);
    expect(t.customerName, 'Lan');
    expect(t.customerPhone, '0901');
    expect(t.lastSender, ChatRole.customer);
    expect(t.unreadFor(ChatRole.shop), 2);
    expect(t.unreadFor(ChatRole.customer), 0);
  });

  test('message previews', () {
    final img = ChatMessage.fromMap('m1', {'sender_role': 'shop', 'type': 'image', 'image_url': 'x'});
    expect(img.senderRole, ChatRole.shop);
    expect(img.preview, contains('Hình ảnh'));
    final card = ChatMessage.fromMap('m2', {
      'sender_role': 'customer',
      'type': 'order',
      'order_ref': {'id': 'o1', 'code': 'ON-271126-001', 'status': 'pending', 'total': 45000},
    });
    expect(card.order?.code, 'ON-271126-001');
    expect(card.order?.total, 45000);
    expect(card.preview, contains('ON-271126-001'));
    final long = ChatMessage.fromMap('m3', {'type': 'text', 'text': 'a' * 120});
    expect(long.preview.length, 81); // 80 ký tự + "…"
    expect(long.createdAt, isNull); // chưa có giờ server
  });

  test('shipper chat is open only while the order is with a shipper', () {
    expect(orderChatOpen(_order('ready')), isTrue);
    expect(orderChatOpen(_order('delivering')), isTrue);
    expect(orderChatOpen(_order('delivery_failed')), isTrue);
    expect(orderChatOpen(_order('completed')), isFalse);
    expect(orderChatOpen(_order('cancelled')), isFalse);
    // Giao lại: đơn về Sẵn sàng, chưa có shipper mới.
    expect(orderChatOpen(_order('ready', shipper: false)), isFalse);
  });

  test('new incoming message detection', () {
    final t0 = DateTime(2026, 11, 27, 9);
    final t1 = t0.add(const Duration(minutes: 1));
    final fromCustomer = _thread(last: ChatRole.customer, at: t1, unreadShop: 1);
    expect(ChatProvider.isNewIncoming(fromCustomer, t0, ChatRole.shop), isTrue);
    expect(ChatProvider.isNewIncoming(fromCustomer, null, ChatRole.shop), isTrue);
    // Đã biết tin này rồi.
    expect(ChatProvider.isNewIncoming(fromCustomer, t1, ChatRole.shop), isFalse);
    // Tin của chính mình.
    expect(ChatProvider.isNewIncoming(fromCustomer, t0, ChatRole.customer), isFalse);
    // Đã đọc ở máy khác.
    final read = _thread(last: ChatRole.customer, at: t1);
    expect(ChatProvider.isNewIncoming(read, t0, ChatRole.shop), isFalse);
  });

  test('chat date labels', () {
    final now = DateTime(2026, 11, 27, 15);
    expect(chatDayLabel(DateTime(2026, 11, 27, 8), now), 'Hôm nay');
    expect(chatDayLabel(DateTime(2026, 11, 26, 23), now), 'Hôm qua');
    expect(chatDayLabel(DateTime(2026, 11, 20), now), '20/11/2026');
    expect(chatListTime(DateTime(2026, 11, 27, 8, 5), now), '08:05');
    expect(chatListTime(DateTime(2026, 11, 26, 8), now), 'Hôm qua');
    expect(chatListTime(DateTime(2026, 11, 1), now), '01/11');
  });

  test('inbox is staff/admin only, chat screen is shared', () {
    expect(guardRoute('/shop_inbox', UserRole.staff), isNull);
    expect(guardRoute('/shop_inbox', UserRole.admin), isNull);
    expect(guardRoute('/shop_inbox', UserRole.customer), '/customer');
    expect(guardRoute('/shop_inbox', UserRole.shipper), '/shipper');
    for (final r in UserRole.values) {
      expect(guardRoute('/chat', r), isNull);
    }
  });

  test('chat bubble shows a small Cloudinary thumbnail', () {
    const original = 'https://res.cloudinary.com/demo/image/upload/v1/meow_coffee/chats/a.png';
    expect(chatThumbUrl(original),
        'https://res.cloudinary.com/demo/image/upload/w_600,c_limit,q_auto/v1/meow_coffee/chats/a.png');
    expect(chatThumbUrl('https://example.com/image/upload/a.png'),
        'https://example.com/image/upload/a.png');
    expect(chatThumbUrl(''), '');
  });
}
