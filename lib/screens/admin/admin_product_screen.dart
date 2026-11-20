import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../utils/formatters.dart';

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
          .collection('sanPham')
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

  Future<void> _showProductOptions(Product product) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tùy chọn sản phẩm'),
        content: Text('Chọn thao tác cho ${product.name}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xóa'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'edit'),
            child: const Text('Chỉnh sửa'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'edit') {
      await Navigator.pushNamed(
        context,
        '/edit_product',
        arguments: product.id,
      );
      _loadProducts();
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: Text(
            'Bạn có chắc chắn muốn xóa sản phẩm "${product.name}" không?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Xóa'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await _deleteProduct(product);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý sản phẩm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Thêm sản phẩm',
            onPressed: () async {
              await Navigator.pushNamed(context, '/add_product');
              _loadProducts();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm sản phẩm...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'Không tìm thấy sản phẩm phù hợp'
                              : 'Hiện chưa có sản phẩm nào',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadProducts,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final product = filtered[index];
                            return Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showProductOptions(product),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 80,
                                          height: 80,
                                          child: CachedNetworkImage(
                                            imageUrl: product.imageUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (_, _) => Container(
                                              color: Colors.grey.shade200,
                                            ),
                                            errorWidget: (_, _, _) => Container(
                                              color: Colors.grey.shade200,
                                              child: const Icon(Icons.coffee),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              product.formattedPrice,
                                              style: const TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              product.category,
                                              style: const TextStyle(
                                                color: Colors.blue,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.edit,
                                          color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
