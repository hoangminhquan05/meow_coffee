import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/chat.dart';
import '../../models/order.dart';
import '../../providers/chat_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/chat_service.dart';
import '../../services/order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// Màn chat dùng chung (bước 10):
/// - Chat Meow Shop: khách ↔ mọi NV/admin (khách chỉ thấy "Meow Shop").
/// - Chat đơn: khách ↔ shipper đang giữ đơn; đơn kết thúc thì chỉ xem lại.
class ChatScreen extends StatefulWidget {
  final ChatArgs args;

  const ChatScreen({super.key, required this.args});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatRef _ref = widget.args.ref;
  late final SessionProvider _session = context.read<SessionProvider>();
  late final ChatProvider _chats = context.read<ChatProvider>();
  late final ChatRole? _role = ChatRole.forUser(_session.user?.role);
  late final Stream<List<ChatMessage>> _messages = ChatService.watchMessages(_ref);

  /// NV xem chat Meow Shop: tin nào do NV nào trả lời (O31).
  late final Stream<Map<String, String>>? _authors =
      _role == ChatRole.shop && _ref.kind == ChatKind.shop
          ? ChatService.watchAuthors(_ref.id)
          : null;

  late final TextEditingController _text = TextEditingController(text: widget.args.draft);
  final _focus = FocusNode();

  StreamSubscription<ChatThread?>? _threadSub;
  StreamSubscription<Order?>? _orderSub;
  ChatThread? _thread;
  Order? _order;
  Object? _orderError;
  bool _orderLoaded = false;
  OrderCard? _attach;
  bool _sending = false;
  bool _uploading = false;

  bool get _isOrderChat => _ref.kind == ChatKind.order;

  /// Chat đơn chỉ gửi được khi đơn còn đang giao; chat shop luôn mở.
  bool get _canSend =>
      _role != null && (!_isOrderChat || (_order != null && orderChatOpen(_order!)));

  @override
  void initState() {
    super.initState();
    _attach = widget.args.attach;
    _chats.setOpen(_ref);
    _threadSub = ChatService.watchThread(_ref).listen(_onThread, onError: (Object e) {
      debugPrint('ChatScreen thread error: $e');
    });
    if (_isOrderChat) {
      _orderSub = OrderService.watchOrder(_ref.id).listen(
        (o) => setState(() {
          _order = o;
          _orderLoaded = true;
          _orderError = null;
        }),
        onError: (Object e) => setState(() {
          _orderError = e;
          _orderLoaded = true;
        }),
      );
    }
  }

  void _onThread(ChatThread? t) {
    if (!mounted) return;
    setState(() => _thread = t);
    final role = _role;
    // Đang mở chat → tin mới coi như đã đọc.
    if (role != null && t != null && t.unreadFor(role) > 0) {
      ChatService.markRead(_ref, role).catchError((Object e) {
        debugPrint('ChatScreen markRead error: $e');
      });
    }
  }

  @override
  void dispose() {
    _chats.clearOpen(_ref);
    _threadSub?.cancel();
    _orderSub?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Chat Meow Shop: thông tin khách để ghi vào đầu cuộc chat.
  OrderCustomer? get _customer {
    if (_ref.kind != ChatKind.shop) return null;
    if (_role == ChatRole.customer) {
      final u = _session.user;
      return OrderCustomer(id: _session.uid, name: u?.name ?? '', phone: u?.phone ?? '');
    }
    final t = _thread;
    return widget.args.customer ??
        (t == null ? null : OrderCustomer(id: _ref.id, name: t.customerName, phone: t.customerPhone));
  }

  String get _customerUid => _ref.kind == ChatKind.shop ? _ref.id : (_order?.customer?.id ?? '');

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _errorText(Object e) => e is StateError
      ? e.message
      : 'Không gửi được tin nhắn. Kiểm tra kết nối rồi thử lại.';

  Future<void> _sendRaw({String text = '', OrderCard? order}) => ChatService.send(
        ref: _ref,
        as: _role!,
        sender: _session.personRef,
        text: text,
        order: order,
        customer: _customer,
        orderCode: _order?.orderCode ?? _thread?.orderCode ?? '',
      );

  Future<void> _send() async {
    if (!_canSend || _sending) return;
    final text = _text.text.trim();
    final attach = _attach;
    if (text.isEmpty && attach == null) return;
    setState(() {
      _sending = true;
      _attach = null;
    });
    _text.clear();
    try {
      if (attach != null) await _sendRaw(order: attach);
      if (text.isNotEmpty) await _sendRaw(text: text);
    } catch (e) {
      debugPrint('ChatScreen send error: $e');
      if (!mounted) return;
      // Trả lại nội dung để gửi lại.
      if (_text.text.isEmpty) _text.text = text;
      _toast(_errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendOrderCard(Order o) async {
    try {
      await _sendRaw(order: OrderCard.of(o));
    } catch (e) {
      debugPrint('ChatScreen send order error: $e');
      if (mounted) _toast(_errorText(e));
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final role = _role;
    if (role == null || !_canSend) return;
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
    } catch (e) {
      if (mounted) _toast('Không mở được ${source == ImageSource.camera ? 'máy ảnh' : 'thư viện ảnh'}');
      return;
    }
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      await ChatService.sendImage(
        ref: _ref,
        as: role,
        sender: _session.personRef,
        file: file,
        customer: _customer,
        orderCode: _order?.orderCode ?? _thread?.orderCode ?? '',
      );
    } catch (e) {
      debugPrint('ChatScreen image error: $e');
      if (mounted) _toast(e is StateError ? e.message : 'Không gửi được ảnh. Thử lại sau.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _showAttachMenu() async {
    final canOrder = _ref.kind == ChatKind.shop && _customerUid.isNotEmpty;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.brand),
              title: const Text('Ảnh từ thư viện'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: AppColors.brand),
                title: const Text('Chụp ảnh'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            if (canOrder)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brand),
                title: const Text('Gửi đơn hàng'),
                onTap: () => Navigator.pop(ctx, 'order'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'gallery':
        await _pickImage(ImageSource.gallery);
      case 'camera':
        await _pickImage(ImageSource.camera);
      case 'order':
        final o = await showModalBottomSheet<Order>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => _OrderPickerSheet(customerUid: _customerUid),
        );
        if (o != null && mounted) await _sendOrderCard(o);
    }
  }

  Future<void> _showQuickReplies() async {
    final reply = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Mẫu câu nhanh',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              for (final r in ChatService.quickReplies)
                ListTile(
                  leading: const Icon(Icons.bolt_rounded, color: AppColors.brand),
                  title: Text(r),
                  onTap: () => Navigator.pop(ctx, r),
                ),
            ],
          ),
        ),
      ),
    );
    if (reply == null || !mounted) return;
    final current = _text.text.trimRight();
    _text.text = current.isEmpty ? reply : '$current $reply';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.soft,
              child: Icon(
                _ref.kind == ChatKind.shop
                    ? (_role == ChatRole.customer ? Icons.storefront_rounded : Icons.person_rounded)
                    : (_role == ChatRole.shipper ? Icons.person_rounded : Icons.delivery_dining_rounded),
                color: AppColors.brand,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(args.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  if (_subtitle.isNotEmpty)
                    Text(_subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            ?_banner,
            Expanded(child: _messageList()),
            if (_uploading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand)),
                    SizedBox(width: 10),
                    Text('Đang gửi ảnh…', style: TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
            if (_canSend) _composer(),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    if (widget.args.subtitle.isNotEmpty) return widget.args.subtitle;
    if (_isOrderChat) return _order?.orderCode ?? _thread?.orderCode ?? '';
    if (_role == ChatRole.shop) return _thread?.customerPhone ?? '';
    return '';
  }

  /// Dòng thông báo trên đầu chat đơn: đã khóa / chờ shipper / mất quyền.
  Widget? get _banner {
    if (!_isOrderChat || !_orderLoaded) return null;
    String? text;
    if (_orderError != null || _order == null) {
      text = _role == ChatRole.shipper
          ? 'Bạn không còn giữ đơn này nên không xem được cuộc trò chuyện.'
          : 'Không tải được đơn hàng.';
    } else if (!orderChatOpen(_order!)) {
      final o = _order!;
      text = o.status.isActive
          ? 'Đơn đang chờ shipper mới – nhắn được khi có shipper nhận đơn.'
          : 'Đơn đã ${o.status == OrderStatus.completed ? 'hoàn tất' : 'hủy'} – chỉ xem lại tin nhắn.';
    }
    if (text == null) return null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.warningSoft,
      child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.inkSlate)),
    );
  }

  Widget _messageList() {
    return StreamBuilder<Map<String, String>>(
      stream: _authors,
      builder: (context, authorSnap) {
        final authors = authorSnap.data ?? const <String, String>{};
        return StreamBuilder<List<ChatMessage>>(
          stream: _messages,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _isOrderChat && _role == ChatRole.shipper
                        ? 'Bạn không còn giữ đơn này.'
                        : 'Không tải được tin nhắn: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: AppColors.brand));
            }
            final list = snap.data!;
            if (list.isEmpty) return _empty();
            final now = DateTime.now();
            return ListView.builder(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final m = list[i];
                final older = i + 1 < list.length ? list[i + 1] : null;
                final at = m.createdAt ?? now;
                final showDay = older == null || !_sameDay(older.createdAt ?? now, at);
                final mine = m.senderRole == _role;
                final author = authors[m.id] ?? '';
                final groupStart = showDay ||
                    older.senderRole != m.senderRole ||
                    (mine && _role == ChatRole.shop && (authors[older.id] ?? '') != author);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDay) _DayChip(label: chatDayLabel(at, now)),
                    if (groupStart) _senderLabel(m, mine, author),
                    _Bubble(
                      message: m,
                      mine: mine,
                      role: _role,
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _senderLabel(ChatMessage m, bool mine, String author) {
    String label;
    if (mine) {
      // NV thấy ai trong quán đã trả lời; người khác không cần nhãn cho tin của mình.
      if (_role != ChatRole.shop) return const SizedBox(height: 6);
      label = author.isEmpty ? 'Meow Shop' : 'Meow Shop · $author';
    } else {
      label = switch (m.senderRole) {
        ChatRole.shop => 'Meow Shop',
        ChatRole.shipper => 'Shipper',
        ChatRole.customer => _role == ChatRole.shop
            ? (_thread?.customerName.isNotEmpty == true ? _thread!.customerName : widget.args.title)
            : 'Khách hàng',
      };
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 2),
      child: Text(
        label,
        textAlign: mine ? TextAlign.right : TextAlign.left,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.muted),
      ),
    );
  }

  Widget _empty() {
    final text = switch ((_ref.kind, _role)) {
      (ChatKind.shop, ChatRole.customer) =>
        'Cần đổi món, hủy đơn hay hỏi gì? Nhắn cho Meow Shop nhé – quán trả lời trong giờ mở cửa.',
      (ChatKind.shop, _) => 'Chưa có tin nhắn. Gửi tin đầu tiên cho khách.',
      (ChatKind.order, ChatRole.customer) =>
        'Nhắn shipper nếu cần dặn thêm (ví dụ: gọi trước khi tới, để hàng ở bảo vệ…).',
      (ChatKind.order, _) => 'Nhắn khách nếu cần hỏi đường hoặc báo sắp tới.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 48, color: AppColors.mutedLight),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    final attach = _attach;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attach != null)
            Container(
              margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: AppColors.soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Đính kèm đơn ${attach.code} · ${formatMoney(attach.total)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: 'Bỏ đính kèm',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _attach = null),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Gửi ảnh / đơn hàng',
                icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.brand),
                onPressed: _uploading ? null : _showAttachMenu,
              ),
              if (_role == ChatRole.shop)
                IconButton(
                  tooltip: 'Mẫu câu nhanh',
                  icon: const Icon(Icons.bolt_rounded, color: AppColors.brand),
                  onPressed: _showQuickReplies,
                ),
              Expanded(
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: chatMaxTextLength,
                  textCapitalization: TextCapitalization.sentences,
                  // Chỉ hiện bộ đếm khi gần chạm giới hạn.
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      currentLength > chatMaxTextLength - 100
                          ? Text('$currentLength/$maxLength',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted))
                          : null,
                  decoration: InputDecoration(
                    hintText: 'Nhập tin nhắn…',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.bg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                tooltip: 'Gửi',
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                    : const Icon(Icons.send_rounded, color: AppColors.brand),
                onPressed: _sending ? null : _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;

  const _DayChip({required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ),
      );
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final ChatRole? role;

  const _Bubble({required this.message, required this.mine, required this.role});

  @override
  Widget build(BuildContext context) {
    final m = message;
    final time = m.createdAt == null ? 'Đang gửi…' : DateFormat('HH:mm').format(m.createdAt!);
    final maxWidth = MediaQuery.of(context).size.width * 0.75;
    final Widget content = switch (m.type) {
      MessageType.image => _ImageContent(url: m.imageUrl),
      MessageType.order => _OrderCardContent(card: m.order, mine: mine, role: role),
      MessageType.text => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: mine ? AppColors.brand : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: mine ? null : Border.all(color: AppColors.border),
          ),
          child: SelectableText(
            m.text,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.35,
              color: mine ? Colors.white : AppColors.ink,
            ),
          ),
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: content),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(time, style: const TextStyle(fontSize: 10.5, color: AppColors.mutedLight)),
          ),
        ],
      ),
    );
  }
}

/// Ảnh trong bong bóng: hiện bản thu nhỏ của Cloudinary; tải lỗi (mạng chập
/// chờn, ảnh vừa gửi xong…) thì tự thử lại 2 lần, sau đó cho chạm để thử lại
/// thay vì đứng yên ở "Không tải được ảnh".
class _ImageContent extends StatefulWidget {
  final String url;

  const _ImageContent({required this.url});

  @override
  State<_ImageContent> createState() => _ImageContentState();
}

class _ImageContentState extends State<_ImageContent> {
  static const _autoRetries = 2;

  /// Lần tải thứ mấy. Mỗi lần đổi cacheKey để thư viện tải lại từ đầu.
  int _attempt = 0;
  int _retryScheduledFor = -1;
  Timer? _retryTimer;

  @override
  void didUpdateWidget(covariant _ImageContent old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _retryTimer?.cancel();
      _attempt = 0;
      _retryScheduledFor = -1;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  /// Gọi trong lúc dựng errorWidget nên chỉ hẹn giờ, không setState ngay.
  bool _scheduleAutoRetry(Object error) {
    if (_attempt >= _autoRetries) return false;
    if (_retryScheduledFor != _attempt) {
      _retryScheduledFor = _attempt;
      debugPrint('Ảnh chat lỗi (lần ${_attempt + 1}), thử lại: ${widget.url} → $error');
      _retryTimer = Timer(Duration(seconds: 2 * (_attempt + 1)), () {
        if (mounted) setState(() => _attempt++);
      });
    }
    return true;
  }

  Widget _box({required double height, required Widget child}) => Container(
        width: 220,
        height: height,
        color: AppColors.soft,
        alignment: Alignment.center,
        child: child,
      );

  Widget get _loading => _box(
        height: 160,
        child: const CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand),
      );

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _ImageViewer(url: url),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          key: ValueKey(_attempt),
          imageUrl: chatThumbUrl(url),
          cacheKey: _attempt == 0 ? null : '${chatThumbUrl(url)}#$_attempt',
          width: 220,
          fit: BoxFit.cover,
          placeholder: (_, _) => _loading,
          errorWidget: (_, _, error) {
            if (_scheduleAutoRetry(error)) return _loading;
            debugPrint('Ảnh chat lỗi: ${widget.url} → $error');
            return GestureDetector(
              onTap: () => setState(() => _attempt++),
              child: _box(
                height: 120,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, color: AppColors.muted),
                    SizedBox(height: 4),
                    Text('Không tải được ảnh', style: TextStyle(color: AppColors.muted)),
                    Text('Chạm để thử lại',
                        style: TextStyle(fontSize: 12, color: AppColors.brand)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String url;

  const _ImageViewer({required this.url});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, _) => const CircularProgressIndicator(color: Colors.white),
              errorWidget: (_, _, _) => const Text(
                'Không tải được ảnh',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      );
}

/// Thẻ đơn hàng: mã, tổng tiền, trạng thái hiện tại; bấm mở chi tiết đơn.
class _OrderCardContent extends StatelessWidget {
  final OrderCard? card;
  final bool mine;
  final ChatRole? role;

  const _OrderCardContent({required this.card, required this.mine, required this.role});

  @override
  Widget build(BuildContext context) {
    final c = card;
    if (c == null) return const SizedBox.shrink();
    final route = switch (role) {
      ChatRole.customer => '/my_order',
      ChatRole.shop => '/online_order',
      _ => null,
    };
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: route == null ? null : () => Navigator.pushNamed(context, route, arguments: c.id),
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: mine ? AppColors.brand : AppColors.border, width: 1.2),
          ),
          child: StreamBuilder<Order?>(
            stream: OrderService.watchOrder(c.id),
            builder: (context, snap) {
              final o = snap.data;
              final status = o?.status.label ??
                  OrderStatus.values
                      .where((s) => s.value == c.status)
                      .map((s) => s.label)
                      .firstOrNull ??
                  '';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.brand),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(c.code,
                            style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.brand)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Tổng: ${formatMoney(o?.total ?? c.total)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (status.isNotEmpty)
                    Text('Trạng thái: $status',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  if (route != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Xem chi tiết đơn ›',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brand)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Chọn 1 đơn online của khách để gửi thẻ đơn.
class _OrderPickerSheet extends StatelessWidget {
  final String customerUid;

  const _OrderPickerSheet({required this.customerUid});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Chọn đơn hàng',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: StreamBuilder<List<Order>>(
                stream: ChatService.watchCustomerOrders(customerUid),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Không tải được đơn: ${snap.error}',
                          style: const TextStyle(color: AppColors.danger)),
                    );
                  }
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
                    );
                  }
                  final orders = snap.data!;
                  if (orders.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Chưa có đơn online nào.', style: TextStyle(color: AppColors.muted)),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final o in orders)
                        ListTile(
                          leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brand),
                          title: Text(o.orderCode, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text('${o.status.label} · ${formatDateTime(o.createdAt)}'),
                          trailing: Text(formatMoney(o.total),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          onTap: () => Navigator.pop(context, o),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
