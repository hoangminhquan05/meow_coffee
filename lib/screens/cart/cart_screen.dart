import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/cart_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/add_to_cart_sheet.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/meow_ui.dart';

/// Giỏ hàng (L2): sửa số lượng, size, ghi chú; xóa dòng / xóa hết.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  Future<void> _confirmClear(BuildContext context) async {
    final cart = context.read<CartProvider>();
    final ok = await showMeowConfirmDialog(
      context,
      title: 'Xóa hết giỏ hàng?',
      message: 'Tất cả món đã chọn sẽ bị xóa khỏi giỏ.',
      confirmLabel: 'Xóa hết',
    );
    if (ok) cart.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(
        title: 'Giỏ Hàng',
        showBack: false,
        trailing: cart.isEmpty
            ? null
            : MeowCircleIconButton(
                icon: Icons.delete_sweep_outlined,
                iconColor: AppColors.danger,
                onTap: () => _confirmClear(context),
              ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!cart.isEmpty) _CheckoutBar(cart: cart),
          const BottomNavBar(currentIndex: 2),
        ],
      ),
      body: cart.isEmpty
          ? const _EmptyCartPlaceholder()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${cart.totalItems} món · chạm vào món để sửa size / ghi chú',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                for (final item in cart.items) ...[
                  _CartItemCard(item: item),
                  const SizedBox(height: 14),
                ],
              ],
            ),
    );
  }
}

class _EmptyCartPlaceholder extends StatelessWidget {
  const _EmptyCartPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: AppColors.soft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                size: 40,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Giỏ hàng đang trống',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Chọn món cho khách để bắt đầu đơn mới',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 200,
              child: MeowSecondaryButton(
                label: 'Chọn món',
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/product'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  final CartProvider cart;

  const _CheckoutBar({required this.cart});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tạm tính',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
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
              label: 'Tiếp tục',
              icon: Icons.arrow_forward_rounded,
              height: 48,
              onPressed: () => Navigator.pushNamed(context, '/payment'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final CartItem item;

  const _CartItemCard({required this.item});

  Future<void> _decrease(BuildContext context) async {
    final cart = context.read<CartProvider>();
    if (item.quantity > 1) {
      cart.decrease(item.key);
      return;
    }
    final ok = await showMeowConfirmDialog(
      context,
      title: 'Xóa món?',
      message: 'Xóa ${item.displayName} khỏi giỏ hàng?',
      confirmLabel: 'Xóa',
    );
    if (ok) cart.remove(item.key);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartProvider>();

    return MeowCard(
      padding: const EdgeInsets.all(14),
      onTap: () => showEditCartItemSheet(context, item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(
              imageUrl: item.product.imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: AppColors.soft),
              errorWidget: (_, _, _) => Container(
                color: AppColors.soft,
                child: const Icon(Icons.coffee, color: AppColors.brand),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSlate,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => cart.remove(item.key),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Ghi chú: ${item.note}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${formatMoney(item.unitPrice)} / món',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatMoney(item.lineTotal),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.borderSubtle.withValues(alpha: 0.8),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _QtyPillButton(
                            icon: Icons.remove_rounded,
                            filled: false,
                            onTap: () => _decrease(context),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${item.quantity}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkSlate,
                              ),
                            ),
                          ),
                          _QtyPillButton(
                            icon: Icons.add_rounded,
                            filled: true,
                            onTap: () => cart.increase(item.key),
                          ),
                        ],
                      ),
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

/// Sửa size / ghi chú / số lượng của một dòng trong giỏ.
Future<void> showEditCartItemSheet(BuildContext context, CartItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _EditCartItemSheet(item: item),
  );
}

class _EditCartItemSheet extends StatefulWidget {
  final CartItem item;

  const _EditCartItemSheet({required this.item});

  @override
  State<_EditCartItemSheet> createState() => _EditCartItemSheetState();
}

class _EditCartItemSheetState extends State<_EditCartItemSheet> {
  late final _noteController = TextEditingController(text: widget.item.note);
  late String _size = widget.item.size;
  late int _quantity = widget.item.quantity;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.item.product;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              SizeQuantityNoteForm(
                product: product,
                size: _size,
                quantity: _quantity,
                noteController: _noteController,
                onSizeChanged: (s) => setState(() => _size = s),
                onQuantityChanged: (q) => setState(() => _quantity = q),
              ),
              const SizedBox(height: 20),
              MeowPrimaryButton(
                label:
                    'CẬP NHẬT • ${formatMoney(product.priceOf(_size) * _quantity)}',
                height: 50,
                onPressed: () {
                  context.read<CartProvider>().updateItem(
                        widget.item.key,
                        size: _size,
                        note: _noteController.text,
                        quantity: _quantity,
                      );
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QtyPillButton extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _QtyPillButton({
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.brand : AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: 15,
            color: filled ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
