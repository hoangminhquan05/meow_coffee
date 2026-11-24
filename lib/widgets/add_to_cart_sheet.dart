import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../providers/customer_cart_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'meow_ui.dart';

/// Thêm vào đúng giỏ: khách → giỏ online (Firestore), NV/admin → giỏ bán tại quầy.
void addToRightCart(
  BuildContext context,
  Product product, {
  required String size,
  required int quantity,
  required String note,
}) {
  if (context.read<SessionProvider>().isCustomer) {
    context
        .read<CustomerCartProvider>()
        .add(product, size: size, quantity: quantity, note: note);
  } else {
    context
        .read<CartProvider>()
        .addItem(product, size: size, quantity: quantity, note: note);
  }
}

/// Bảng chọn món (L1, Q11): size bắt buộc chọn (không chọn sẵn),
/// số lượng, ghi chú tự do. Dùng cho nút "+" trên thẻ món.
Future<void> showAddToCartSheet(BuildContext context, Product product) async {
  if (!product.isAvailable) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.name} đang hết hàng')),
    );
    return;
  }
  final added = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddToCartSheet(product: product),
  );
  if (added != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã thêm $added vào giỏ hàng')),
    );
  }
}

class _AddToCartSheet extends StatefulWidget {
  final Product product;

  const _AddToCartSheet({required this.product});

  @override
  State<_AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends State<_AddToCartSheet> {
  final _noteController = TextEditingController();
  late String? _size =
      widget.product.hasSizes ? null : Product.defaultSize;
  int _quantity = 1;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _add() {
    final size = _size;
    if (size == null) return;
    try {
      addToRightCart(
        context,
        widget.product,
        size: size,
        quantity: _quantity,
        note: _noteController.text,
      );
    } on StateError catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    final label = size == Product.defaultSize
        ? '$_quantity × ${widget.product.name}'
        : '$_quantity × ${widget.product.name} ($size)';
    Navigator.pop(context, label);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final unit = _size == null ? 0 : product.priceOf(_size!);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                product.priceLabel,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
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
                label: _size == null
                    ? 'CHỌN SIZE ĐỂ THÊM'
                    : 'THÊM VÀO GIỎ • ${formatMoney(unit * _quantity)}',
                height: 50,
                onPressed: _size == null ? null : _add,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phần chọn size + số lượng + ghi chú, dùng chung cho bảng chọn món
/// và màn chi tiết món.
class SizeQuantityNoteForm extends StatelessWidget {
  final Product product;
  final String? size;
  final int quantity;
  final TextEditingController noteController;
  final ValueChanged<String> onSizeChanged;
  final ValueChanged<int> onQuantityChanged;

  const SizeQuantityNoteForm({
    super.key,
    required this.product,
    required this.size,
    required this.quantity,
    required this.noteController,
    required this.onSizeChanged,
    required this.onQuantityChanged,
  });

  static const _labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.muted,
    letterSpacing: 0.6,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (product.hasSizes) ...[
          const SizedBox(height: 18),
          const Text('CHỌN SIZE *', style: _labelStyle),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final s in product.sizes) ...[
                Expanded(
                  child: _SizeChip(
                    size: s,
                    price: product.priceOf(s),
                    selected: size == s,
                    onTap: () => onSizeChanged(s),
                  ),
                ),
                if (s != product.sizes.last) const SizedBox(width: 10),
              ],
            ],
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: Text('SỐ LƯỢNG', style: _labelStyle)),
            _QtyButton(
              icon: Icons.remove_rounded,
              onTap: quantity > 1 ? () => onQuantityChanged(quantity - 1) : null,
            ),
            SizedBox(
              width: 44,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            _QtyButton(
              icon: Icons.add_rounded,
              onTap: () => onQuantityChanged(quantity + 1),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('GHI CHÚ MÓN', style: _labelStyle),
        const SizedBox(height: 8),
        TextField(
          controller: noteController,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Ví dụ: ít đá, 50% đường',
            filled: true,
            fillColor: AppColors.bg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.brand),
            ),
          ),
        ),
      ],
    );
  }
}

class _SizeChip extends StatelessWidget {
  final String size;
  final int price;
  final bool selected;
  final VoidCallback onTap;

  const _SizeChip({
    required this.size,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.soft : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              size,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.brand : AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatMoney(price),
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? AppColors.soft : AppColors.bg,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.brand : AppColors.mutedLight,
        ),
      ),
    );
  }
}
