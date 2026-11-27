import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/order.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Mở các loại chat từ nhiều màn (chi tiết đơn, hoàn tiền, bong bóng…).
class ChatNav {
  ChatNav._();

  static Future<void> open(BuildContext context, ChatArgs args) =>
      Navigator.pushNamed(context, '/chat', arguments: args);

  /// Khách mở chat Meow Shop của mình.
  static Future<void> shopAsCustomer(BuildContext context, {OrderCard? attach, String draft = ''}) {
    final uid = context.read<SessionProvider>().uid;
    return open(
      context,
      ChatArgs(ref: ChatRef.shop(uid), title: 'Meow Shop', attach: attach, draft: draft),
    );
  }

  /// NV/admin nhắn khách của một đơn (kèm sẵn thẻ đơn).
  static Future<void> shopWithCustomer(BuildContext context, Order o, {String draft = ''}) {
    final c = o.customer;
    if (c == null || c.id.isEmpty) return Future.value();
    return open(
      context,
      ChatArgs(
        ref: ChatRef.shop(c.id),
        title: c.name.isEmpty ? 'Khách hàng' : c.name,
        subtitle: c.phone,
        customer: c,
        attach: OrderCard.of(o),
        draft: draft,
      ),
    );
  }

  /// Chat shipper–khách của đơn (khách hoặc shipper mở).
  static Future<void> orderChat(BuildContext context, Order o) {
    final isShipper = context.read<SessionProvider>().isShipper;
    final shipper = o.delivery?.shipper?.name ?? '';
    return open(
      context,
      ChatArgs(
        ref: ChatRef.order(o.id),
        title: isShipper ? 'Khách hàng' : (shipper.isEmpty ? 'Shipper' : 'Shipper $shipper'),
        subtitle: o.orderCode,
      ),
    );
  }
}

/// Số đỏ nhỏ (tin chưa đọc).
class CountBadge extends StatelessWidget {
  final int count;
  final Widget child;

  const CountBadge({super.key, required this.count, required this.child});

  @override
  Widget build(BuildContext context) => Badge(
        isLabelVisible: count > 0,
        backgroundColor: AppColors.danger,
        label: Text(count > 99 ? '99+' : '$count'),
        child: child,
      );
}

/// Icon chat ở góc trên màn NV/admin: số cuộc chat khách đang chờ trả lời.
class ChatInboxButton extends StatelessWidget {
  const ChatInboxButton({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.select<ChatProvider, int>((c) => c.totalUnread);
    return IconButton(
      tooltip: 'Hộp thư Meow Shop',
      onPressed: () => Navigator.pushNamed(context, '/shop_inbox'),
      icon: CountBadge(
        count: count,
        child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.ink),
      ),
    );
  }
}

/// Nút "Nhắn …" có số tin chưa đọc của cuộc chat đó.
class ChatActionButton extends StatelessWidget {
  final String label;
  final ChatRef chat;
  final VoidCallback? onPressed;

  const ChatActionButton({super.key, required this.label, required this.chat, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<ChatProvider, int>((c) => c.unreadOf(chat));
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brand,
        side: const BorderSide(color: AppColors.softBorder),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: CountBadge(count: unread, child: const Icon(Icons.chat_bubble_outline_rounded, size: 20)),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// Bong bóng chat nổi của khách (trên mọi tab của app khách). Kéo được,
/// thả ra tự dính vào mép trái/phải. Có đơn đang giao → cho chọn nhắn
/// Meow Shop hay shipper.
class CustomerChatBubble extends StatefulWidget {
  final Widget child;

  const CustomerChatBubble({super.key, required this.child});

  @override
  State<CustomerChatBubble> createState() => _CustomerChatBubbleState();
}

class _CustomerChatBubbleState extends State<CustomerChatBubble> {
  static const _size = 56.0;
  static const _margin = 12.0;

  /// Vị trí góc trên-trái của bong bóng; null = mặc định góc phải dưới.
  Offset? _pos;
  bool _dragging = false;

  Offset _clamp(Offset p, Size area, EdgeInsets pad) => Offset(
        p.dx.clamp(_margin, area.width - _size - _margin),
        p.dy.clamp(pad.top + _margin, area.height - _size - _margin),
      );

  Future<void> _onTap() async {
    final chats = context.read<ChatProvider>();
    final orders = chats.activeShipperOrders;
    if (orders.isEmpty) {
      await ChatNav.shopAsCustomer(context);
      return;
    }
    final uid = context.read<SessionProvider>().uid;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Nhắn tin với', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: CountBadge(
                count: chats.unreadOf(ChatRef.shop(uid)),
                child: const CircleAvatar(
                  backgroundColor: AppColors.soft,
                  child: Icon(Icons.storefront_rounded, color: AppColors.brand),
                ),
              ),
              title: const Text('Meow Shop', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Đổi món, hủy đơn, hoàn tiền, góp ý…'),
              onTap: () => Navigator.pop(ctx, 'shop'),
            ),
            for (final o in orders)
              ListTile(
                leading: CountBadge(
                  count: chats.unreadOf(ChatRef.order(o.id)),
                  child: const CircleAvatar(
                    backgroundColor: AppColors.soft,
                    child: Icon(Icons.delivery_dining_rounded, color: AppColors.brand),
                  ),
                ),
                title: Text('Shipper ${o.delivery?.shipper?.name ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Đơn ${o.orderCode} · ${o.status.label} · ${formatMoney(o.total)}'),
                onTap: () => Navigator.pop(ctx, o),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is Order) {
      await ChatNav.orderChat(context, choice);
    } else {
      await ChatNav.shopAsCustomer(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = context.select<ChatProvider, int>((c) => c.totalUnread);
    final pad = MediaQuery.of(context).padding;
    return LayoutBuilder(
      builder: (context, box) {
        final area = Size(box.maxWidth, box.maxHeight);
        final pos = _clamp(
          _pos ?? Offset(area.width - _size - _margin, area.height - _size - 20),
          area,
          pad,
        );
        return Stack(
          children: [
            Positioned.fill(child: widget.child),
            AnimatedPositioned(
              duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                onPanStart: (_) => setState(() {
                  _dragging = true;
                  _pos = pos;
                }),
                onPanUpdate: (d) => setState(() => _pos = _clamp((_pos ?? pos) + d.delta, area, pad)),
                onPanEnd: (_) => setState(() {
                  _dragging = false;
                  final p = _pos ?? pos;
                  // Dính vào mép gần hơn cho khỏi che nội dung.
                  final left = p.dx + _size / 2 < area.width / 2;
                  _pos = Offset(left ? _margin : area.width - _size - _margin, p.dy);
                }),
                onTap: _onTap,
                child: Semantics(
                  button: true,
                  label: 'Nhắn tin',
                  child: CountBadge(
                    count: count,
                    child: Container(
                      width: _size,
                      height: _size,
                      decoration: const BoxDecoration(
                        gradient: AppColors.brandGradient,
                        shape: BoxShape.circle,
                        boxShadow: AppColors.buttonShadow,
                      ),
                      child: const Icon(Icons.chat_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
