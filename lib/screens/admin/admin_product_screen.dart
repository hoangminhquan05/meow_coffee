import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/firestore_paths.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';

class AdminProductScreen extends StatefulWidget {
  const AdminProductScreen({super.key});

  @override
  State<AdminProductScreen> createState() => _AdminProductScreenState();
}

class _AdminProductScreenState extends State<AdminProductScreen> {
  final _searchController = TextEditingController();
  List<Product> _products = [];
  String _searchQuery = '';
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
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FsCollections.products)
          .get();
      if (!mounted) return;
      setState(() {
        _products = snapshot.docs.map(Product.fromDoc).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('AdminProductScreen._loadProducts error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Product> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;
    final query = normalizeVietnamese(_searchQuery);
    return _products
        .where((p) => normalizeVietnamese(p.name).contains(query))
        .toList();
  }

  Future<void> _deleteProduct(Product product) async {
    try {
      await FirebaseFirestore.instance
          .collection(FsCollections.products)
          .doc(product.id)
          .delete();
      if (!mounted) return;
      setState(() {
        _products.removeWhere((p) => p.id == product.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xóa "${product.name}"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi xóa sản phẩm: $e')),
      );
    }
  }

  Future<void> _toggleAvailable(Product product, bool value) async {
    try {
      await ProductService.setAvailable(product.id, value);
      if (!mounted) return;
      setState(() {
        final i = _products.indexWhere((p) => p.id == product.id);
        if (i >= 0) _products[i] = product.copyWith(isAvailable: value);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi cập nhật trạng thái: $e')),
      );
    }
  }

  Future<void> _editProduct(Product product) async {
    await Navigator.pushNamed(
      context,
      '/edit_product',
      arguments: product.id,
    );
    _loadProducts();
  }

  Future<void> _confirmDeleteProduct(Product product) async {
    final confirmed = await showMeowConfirmDialog(
      context,
      title: 'Xóa sản phẩm',
      message:
          'Xóa “${product.name}” khỏi thực đơn? Thao tác này không thể hoàn tác.',
      confirmLabel: 'Xóa sản phẩm',
      cancelLabel: 'Hủy',
      isDanger: true,
    );
    if (confirmed) {
      await _deleteProduct(product);
    }
  }

  Future<void> _showProductOptions(Product product) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tùy chọn sản phẩm',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              MeowPrimaryButton(
                label: 'Chỉnh sửa sản phẩm',
                icon: Icons.edit_outlined,
                height: 48,
                onPressed: () => Navigator.pop(dialogContext, 'edit'),
              ),
              const SizedBox(height: 10),
              MeowSecondaryButton(
                label: 'Xóa sản phẩm',
                icon: Icons.delete_outline_rounded,
                textColor: AppColors.danger,
                backgroundColor: AppColors.dangerSoft,
                borderColor: const Color(0xFFFECDD3),
                onPressed: () => Navigator.pop(dialogContext, 'delete'),
              ),
              const SizedBox(height: 10),
              MeowSecondaryButton(
                label: 'Hủy',
                onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'edit') {
      await _editProduct(product);
    } else if (action == 'delete') {
      await _confirmDeleteProduct(product);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(
        title: 'Quản Lý Sản Phẩm',
        trailing: MeowCircleIconButton(
          icon: Icons.add_rounded,
          onTap: () async {
            await Navigator.pushNamed(context, '/add_product');
            _loadProducts();
          },
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppColors.inputShadow,
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: const TextStyle(fontSize: 14, color: AppColors.ink),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm món, đồ uống theo tên...',
                      hintStyle: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.muted,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.muted,
                        size: 20,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.brand,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'TỔNG QUAN THỰC ĐƠN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.55,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.soft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${filtered.length} sản phẩm',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'Không tìm thấy sản phẩm phù hợp'
                              : 'Hiện chưa có sản phẩm nào',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.brand,
                        onRefresh: _loadProducts,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final product = filtered[index];
                            return MeowCard(
                              padding: const EdgeInsets.all(12),
                              onTap: () => _showProductOptions(product),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: SizedBox(
                                      width: 72,
                                      height: 78,
                                      child: CachedNetworkImage(
                                        imageUrl: product.imageUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (_, _) => Container(
                                          color: AppColors.soft,
                                        ),
                                        errorWidget: (_, _, _) => Container(
                                          color: AppColors.soft,
                                          child: const Icon(
                                            Icons.coffee,
                                            color: AppColors.brand,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                product.category.isNotEmpty
                                                    ? product.category
                                                    : 'Chưa phân loại',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              product.isAvailable
                                                  ? 'Đang bán'
                                                  : 'Hết hàng',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: product.isAvailable
                                                    ? AppColors.success
                                                    : AppColors.danger,
                                              ),
                                            ),
                                            SizedBox(
                                              height: 24,
                                              child: Switch(
                                                value: product.isAvailable,
                                                onChanged: (v) =>
                                                    _toggleAvailable(
                                                        product, v),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              product.priceLabel,
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.brand,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                _RowActionChip(
                                                  label: 'Sửa',
                                                  bg: AppColors.soft,
                                                  fg: AppColors.brand,
                                                  onTap: () =>
                                                      _editProduct(product),
                                                ),
                                                const SizedBox(width: 6),
                                                _RowActionChip(
                                                  label: 'Xóa',
                                                  bg: const Color(0xFFFFF0F3),
                                                  fg: const Color(0xFFD94A68),
                                                  onTap: () =>
                                                      _confirmDeleteProduct(
                                                    product,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: MeowPrimaryButton(
                  label: 'Thêm sản phẩm mới',
                  icon: Icons.add_rounded,
                  height: 48,
                  onPressed: () async {
                    await Navigator.pushNamed(context, '/add_product');
                    _loadProducts();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowActionChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _RowActionChip({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
