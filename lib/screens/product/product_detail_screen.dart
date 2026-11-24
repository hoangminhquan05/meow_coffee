import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/add_to_cart_sheet.dart';
import '../../widgets/meow_ui.dart';

/// Chi tiết món (L1): chọn size (bắt buộc, không chọn sẵn), số lượng, ghi chú.
class ProductDetailScreen extends StatefulWidget {
  final String productId;

  const ProductDetailScreen({
    super.key,
    required this.productId,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late final Stream<Product?> _productStream =
      ProductService.watchOne(widget.productId);
  final _noteController = TextEditingController();
  String? _size;
  int _quantity = 1;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _addToCart(Product product, String size) {
    context.read<CartProvider>().addItem(
          product,
          size: size,
          quantity: _quantity,
          note: _noteController.text,
        );
    final label = size == Product.defaultSize
        ? '$_quantity × ${product.name}'
        : '$_quantity × ${product.name} ($size)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã thêm $label vào giỏ hàng'),
        duration: const Duration(seconds: 2),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Chi Tiết Sản Phẩm'),
      body: StreamBuilder<Product?>(
        stream: _productStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorView(message: 'Không thể tải sản phẩm: ${snapshot.error}');
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            );
          }
          final product = snapshot.data;
          if (product == null) {
            return const _ErrorView(message: 'Không tìm thấy sản phẩm');
          }
          return _buildDetailContent(product);
        },
      ),
    );
  }

  Widget _buildDetailContent(Product product) {
    // Món không chia size → size cố định 'default'.
    final size = product.hasSizes
        ? (product.sizes.contains(_size) ? _size : null)
        : Product.defaultSize;
    final soldOut = !product.isAvailable;
    final unit = size == null ? 0 : product.priceOf(size);
    // Khách chưa đặt online được (bước 5) → chỉ xem món.
    final session = context.watch<SessionProvider>();
    final canSell = !session.isCustomer && !session.isShipper;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MeowCard(
                  padding: const EdgeInsets.all(11),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 252,
                      width: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Image.asset(
                          'assets/images/banner.jpg',
                          fit: BoxFit.cover,
                        ),
                        errorWidget: (_, _, _) => Image.asset(
                          'assets/images/banner.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                MeowCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.inkSlate,
                                letterSpacing: -0.5,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            product.priceLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brand,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: soldOut ? AppColors.dangerSoft : AppColors.bg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          soldOut ? '● Hết hàng' : '● Đang phục vụ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                soldOut ? AppColors.danger : AppColors.success,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        product.description.isNotEmpty
                            ? product.description
                            : 'Đồ uống pha chế từ nguyên liệu tươi ngon chọn lọc tại Meow Coffee.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF475569),
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!soldOut && canSell) ...[
                  const SizedBox(height: 16),
                  MeowCard(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: SizeQuantityNoteForm(
                      product: product,
                      size: size,
                      quantity: _quantity,
                      noteController: _noteController,
                      onSizeChanged: (s) => setState(() => _size = s),
                      onQuantityChanged: (q) => setState(() => _quantity = q),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: MeowPrimaryButton(
                label: !canSell
                    ? 'ĐẶT MÓN ONLINE SẮP RA MẮT'
                    : soldOut
                        ? 'MÓN ĐANG HẾT HÀNG'
                        : size == null
                            ? 'CHỌN SIZE ĐỂ THÊM'
                            : 'THÊM VÀO GIỎ • ${formatMoney(unit * _quantity)}',
                icon: Icons.shopping_bag_outlined,
                onPressed: (!canSell || soldOut || size == null)
                    ? null
                    : () => _addToCart(product, size),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              child: MeowSecondaryButton(
                label: 'Quay lại',
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
