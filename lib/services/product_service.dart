import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/firestore_paths.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';

class ProductService {
  ProductService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(FsCollections.products);

  /// Danh sách món realtime, sắp theo danh mục rồi tên.
  static Stream<List<Product>> watchAll() => _col.snapshots().map((s) {
        final list = s.docs.map(Product.fromDoc).toList()
          ..sort((a, b) {
            final c = a.category.compareTo(b.category);
            return c != 0 ? c : a.name.compareTo(b.name);
          });
        return list;
      });

  static Stream<Product?> watchOne(String id) => _col
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Product.fromDoc(d) : null);

  /// Chỉ cập nhật `is_available` (nhân viên được phép – Q9).
  static Future<void> setAvailable(String id, bool value) =>
      _col.doc(id).update({'is_available': value});
}

/// Nhấn giữ thẻ món → "Đánh dấu hết hàng" / "Bán lại" (L10, Q9).
Future<void> showAvailabilitySheet(BuildContext context, Product product) async {
  final markSoldOut = product.isAvailable;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              product.name,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              markSoldOut ? 'Đang bán' : 'Đang hết hàng',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                markSoldOut
                    ? Icons.remove_shopping_cart_outlined
                    : Icons.check_circle_outline_rounded,
                color: markSoldOut ? AppColors.danger : AppColors.success,
              ),
              title: Text(
                markSoldOut ? 'Đánh dấu hết hàng' : 'Bán lại',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: markSoldOut ? AppColors.danger : AppColors.success,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ProductService.setAvailable(product.id, !markSoldOut);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(markSoldOut
            ? 'Đã đánh dấu ${product.name} hết hàng'
            : 'Đã mở bán lại ${product.name}'),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Không cập nhật được trạng thái món: $e')),
    );
  }
}
