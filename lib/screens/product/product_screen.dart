import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/bottom_nav_bar.dart';

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  String _query = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('sanPham').get();
      if (!mounted) return;
      setState(() {
        _products = snapshot.docs
            .map((doc) => Product.fromMap(doc.data(), docId: doc.id))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('ProductScreen._loadProducts error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Product> get _filteredProducts {
    if (_query.isEmpty) return _products;
    final normalizedQuery = normalizeVietnamese(_query);
    return _products
        .where(
          (product) =>
              normalizeVietnamese(product.name).contains(normalizedQuery),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filtered = _filteredProducts;

    return Scaffold(
      bottomNavigationBar: const BottomNavBar(currentIndex: 1),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  elevation: 6,
                  shadowColor: colorScheme.primary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  color: colorScheme.surface,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm sản phẩm...',
                      prefixIcon:
                          Icon(Icons.search, color: colorScheme.primary),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon:
                                  Icon(Icons.close, color: colorScheme.primary),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Khám Phá Sản Phẩm',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Danh mục sản phẩm chất lượng',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            const Text('Đang tải sản phẩm...'),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? _EmptyProductState(hasQuery: _query.isNotEmpty)
                        : RefreshIndicator(
                            onRefresh: _loadProducts,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, index) {
                                final product = filtered[index];
                                return _ProductCard(
                                  product: product,
                                  onTap: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/product_detail',
                                      arguments: product.id,
                                    );
                                  },
                                  onAddToCart: () {
                                    context
                                        .read<CartProvider>()
                                        .addToCart(product);
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Đã thêm ${product.name} vào giỏ hàng',
                                          ),
                                          duration: const Duration(seconds: 2),
                                          action: SnackBarAction(
                                            label: 'Đóng',
                                            onPressed: () {},
                                          ),
                                        ),
                                      );
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shortDescription = product.description.length > 60
        ? '${product.description.substring(0, 60)}...'
        : product.description;

    return Card(
      elevation: 2,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const Icon(Icons.coffee, color: Colors.brown),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.formattedPrice,
                      style: TextStyle(
                        fontSize: 15,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (shortDescription.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        shortDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: colorScheme.primary,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: onAddToCart,
                  icon: Icon(Icons.add, color: colorScheme.onPrimary),
                  tooltip: 'Thêm vào giỏ hàng',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyProductState extends StatelessWidget {
  final bool hasQuery;

  const _EmptyProductState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              hasQuery
                  ? 'Không tìm thấy sản phẩm phù hợp'
                  : 'Hiện chưa có sản phẩm nào',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'Hãy thử từ khóa khác hoặc kiểm tra chính tả'
                  : 'Sản phẩm mới sẽ sớm được cập nhật',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
