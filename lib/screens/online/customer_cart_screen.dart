import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/customer_cart_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/add_to_cart_sheet.dart';
import '../../widgets/meow_ui.dart';

/// Tab Giỏ của khách (bước 5). Giá luôn theo thực đơn hiện tại; món hết hàng /
/// ngừng bán được đánh dấu đỏ và chặn thanh toán đến khi bỏ khỏi giỏ.
class CustomerCartScreen extends StatelessWidget {
  final VoidCallback? onBrowseMenu;

  /// Mở như trang riêng (từ "Đặt lại") thì có nút quay lại.
  final bool standalone;

  const CustomerCartScreen({super.key, this.onBrowseMenu, this.standalone = false});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CustomerCartProvider>();
    final hasProblem = cart.lines.any((l) => !l.isOrderable);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Giỏ Hàng'),
        automaticallyImplyLeading: standalone,
        backgroundColor: AppColors.bg,
        actions: [
          if (!cart.isEmpty)
            IconButton(
              tooltip: 'Xóa hết',
              icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
              onPressed: () async {
                final ok = await showMeowConfirmDialog(
                  context,
                  title: 'Xóa hết giỏ hàng?',
                  message: 'Tất cả món trong giỏ sẽ bị xóa.',
                  confirmLabel: 'Xóa hết',
                );
                if (ok) cart.clear();
              },
            ),
        ],
      ),
      body: !cart.isLoaded
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : cart.isEmpty
              ? _Empty(onBrowseMenu: onBrowseMenu)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    if (cart.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('Lỗi đồng bộ giỏ hàng: ${cart.error}',
                            style: const TextStyle(color: AppColors.danger)),
                      ),
                    if (hasProblem)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Có món không còn bán, bỏ khỏi giỏ để đặt hàng.',
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ),
                            TextButton(
                              onPressed: cart.removeUnorderable,
                              child: const Text('Bỏ các món đó'),
                            ),
                          ],
                        ),
                      ),
                    for (final line in cart.lines) ...[
                      _LineCard(line: line),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${cart.totalItems} món · tạm tính',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      Text(
                        formatMoney(cart.subtotal),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brand,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MeowPrimaryButton(
                      label: 'Thanh toán',
                      icon: Icons.arrow_forward_rounded,
                      height: 48,
                      onPressed: cart.allOrderable
                          ? () => Navigator.pushNamed(context, '/checkout')
                          : null,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback? onBrowseMenu;

  const _Empty({this.onBrowseMenu});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 56, color: AppColors.brand),
            const SizedBox(height: 14),
            const Text('Giỏ hàng đang trống',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Chọn món yêu thích, Meow giao tận nơi.',
                style: TextStyle(color: AppColors.muted)),
            if (onBrowseMenu != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: 200,
                child: MeowSecondaryButton(label: 'Xem thực đơn', onPressed: onBrowseMenu),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final CustomerCartLine line;

  const _LineCard({required this.line});

  Future<void> _edit(BuildContext context) async {
    final product = line.product;
    if (product == null) return;
    final cart = context.read<CustomerCartProvider>();
    final result = await showModalBottomSheet<({String size, int quantity, String note})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditSheet(line: line),
    );
    if (result != null) {
      cart.update(line.key, size: result.size, note: result.note, quantity: result.quantity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CustomerCartProvider>();
    final problem = line.problem;
    return MeowCard(
      padding: const EdgeInsets.all(12),
      borderColor: problem != null ? AppColors.danger : AppColors.border,
      onTap: problem == null ? () => _edit(context) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 64,
              child: CachedNetworkImage(
                imageUrl: line.product?.imageUrl ?? '',
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  color: AppColors.soft,
                  child: const Icon(Icons.coffee, color: AppColors.brand),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                if (line.note.isNotEmpty)
                  Text('Ghi chú: ${line.note}',
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.muted)),
                if (problem != null)
                  Text(problem,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.danger))
                else
                  Text('${formatMoney(line.unitPrice)} / món',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      problem == null ? formatMoney(line.lineTotal) : '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: AppColors.brand),
                    ),
                    const Spacer(),
                    _Qty(
                      icon: Icons.remove_rounded,
                      onTap: () => cart.setQuantity(line.key, line.quantity - 1),
                    ),
                    SizedBox(
                      width: 30,
                      child: Text('${line.quantity}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    _Qty(
                      icon: Icons.add_rounded,
                      onTap: problem == null
                          ? () => cart.setQuantity(line.key, line.quantity + 1)
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Bỏ khỏi giỏ',
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                      onPressed: () => cart.remove(line.key),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Qty extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _Qty({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onTap == null ? AppColors.bg : AppColors.soft,
          ),
          child: Icon(icon,
              size: 16, color: onTap == null ? AppColors.mutedLight : AppColors.brand),
        ),
      );
}

class _EditSheet extends StatefulWidget {
  final CustomerCartLine line;

  const _EditSheet({required this.line});

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _note = TextEditingController(text: widget.line.note);
  late String _size = widget.line.size;
  late int _qty = widget.line.quantity;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.line.product!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(product.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              SizeQuantityNoteForm(
                product: product,
                size: _size,
                quantity: _qty,
                noteController: _note,
                onSizeChanged: (s) => setState(() => _size = s),
                onQuantityChanged: (q) => setState(() => _qty = q),
              ),
              const SizedBox(height: 20),
              MeowPrimaryButton(
                label: 'CẬP NHẬT • ${formatMoney(product.priceOf(_size) * _qty)}',
                onPressed: () =>
                    Navigator.pop(context, (size: _size, quantity: _qty, note: _note.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
