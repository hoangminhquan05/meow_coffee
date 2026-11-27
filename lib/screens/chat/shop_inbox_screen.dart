import 'package:flutter/material.dart';

import '../../models/chat.dart';
import '../../models/order.dart';
import '../../providers/chat_provider.dart';
import '../../services/chat_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// Hộp thư Meow Shop (NV/admin): mọi cuộc chat của khách, tin mới nhất trước.
/// Ai trong quán cũng trả lời được; khách chỉ thấy tên "Meow Shop" (O31).
class ShopInboxScreen extends StatefulWidget {
  const ShopInboxScreen({super.key});

  @override
  State<ShopInboxScreen> createState() => _ShopInboxScreenState();
}

class _ShopInboxScreenState extends State<ShopInboxScreen> {
  final Stream<List<ChatThread>> _stream = ChatService.watchShopInbox();
  final _search = TextEditingController();
  bool _unreadOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ChatThread t, String q) {
    if (q.isEmpty) return true;
    final name = normalizeVietnamese(t.customerName).toLowerCase();
    return name.contains(q) || t.customerPhone.replaceAll(' ', '').contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Hộp thư Meow Shop'),
        backgroundColor: AppColors.bg,
      ),
      body: StreamBuilder<List<ChatThread>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Không tải được hộp thư: ${snap.error}',
                    style: const TextStyle(color: AppColors.danger)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brand));
          }
          final all = snap.data!;
          final unreadCount = all.where((t) => t.unreadFor(ChatRole.shop) > 0).length;
          final q = normalizeVietnamese(_search.text.trim()).toLowerCase();
          final list = all
              .where((t) => !_unreadOnly || t.unreadFor(ChatRole.shop) > 0)
              .where((t) => _matches(t, q))
              .toList();
          final now = DateTime.now();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tên hoặc SĐT khách',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Tất cả',
                      selected: !_unreadOnly,
                      onTap: () => setState(() => _unreadOnly = false),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Chưa đọc ($unreadCount)',
                      selected: _unreadOnly,
                      onTap: () => setState(() => _unreadOnly = true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                          all.isEmpty ? 'Chưa có khách nào nhắn tin.' : 'Không có cuộc chat phù hợp.',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                        itemBuilder: (context, i) => _InboxTile(thread: list[i], now: now),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Chip lọc Tất cả / Chưa đọc. Tự đặt màu viền và nền: theme chưa có
/// `outlineVariant` nên ChoiceChip mặc định vẽ viền đậm ở chip *chưa* chọn,
/// còn chip đang chọn lại mất viền, nền trùng nền trang → trông như chọn nhầm.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.soft,
        side: BorderSide(color: selected ? AppColors.brand : AppColors.border),
        labelStyle: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.brand : AppColors.ink,
        ),
      );
}

class _InboxTile extends StatelessWidget {
  final ChatThread thread;
  final DateTime now;

  const _InboxTile({required this.thread, required this.now});

  @override
  Widget build(BuildContext context) {
    final t = thread;
    final unread = t.unreadFor(ChatRole.shop);
    final name = t.customerName.isEmpty ? 'Khách hàng' : t.customerName;
    final preview = t.lastSender == ChatRole.shop ? 'Meow Shop: ${t.lastText}' : t.lastText;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.soft,
        child: Text(
          name.characters.first.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
          if (t.lastMessageAt != null)
            Text(chatListTime(t.lastMessageAt!, now),
                style: TextStyle(
                    fontSize: 12,
                    color: unread > 0 ? AppColors.brand : AppColors.muted,
                    fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400)),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              t.customerPhone.isEmpty ? preview : '${t.customerPhone} · $preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: unread > 0 ? AppColors.ink : AppColors.muted),
            ),
          ),
          if (unread > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      onTap: () => Navigator.pushNamed(
        context,
        '/chat',
        arguments: ChatArgs(
          ref: t.ref,
          title: name,
          subtitle: t.customerPhone,
          customer: OrderCustomer(id: t.ref.id, name: t.customerName, phone: t.customerPhone),
        ),
      ),
    );
  }
}
