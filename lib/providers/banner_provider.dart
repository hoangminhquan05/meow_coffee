import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../config/env_config.dart';
import '../core/firestore_paths.dart';
import '../models/banner_model.dart';
import '../services/cloudinary_service.dart';

class BannerProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _bannersCollection =>
      _db.collection(FsCollections.banners);

  List<BannerModel> _banners = [];
  List<BannerModel> get banners => List.unmodifiable(_banners);

  BannerModel? _selectedBanner;
  BannerModel? get selectedBanner => _selectedBanner;

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  BannerProvider() {
    loadBanners();
  }

  Future<void> loadBanners() async {
    _isLoading = true;
    notifyListeners();
    try {
      final snapshot = await _bannersCollection.get();
      _banners = snapshot.docs
          .map((doc) => BannerModel.fromMap(doc.data(), id: doc.id))
          .toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    } catch (e) {
      debugPrint('BannerProvider.loadBanners error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectBanner(BannerModel banner) {
    _selectedBanner = banner;
    notifyListeners();
  }

  void clearSelection() {
    _selectedBanner = null;
    notifyListeners();
  }

  Future<String> uploadBannerImage(XFile file) async {
    _isUploading = true;
    notifyListeners();
    try {
      final publicId = 'banner_${DateTime.now().millisecondsSinceEpoch}';
      return await CloudinaryService.instance.uploadImage(
        file,
        folder: EnvConfig.cloudinaryFolderBanners,
        publicId: publicId,
      );
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  Future<void> addBanner(BannerModel banner) async {
    // Banner mới xếp cuối danh sách.
    final nextOrder = _banners.isEmpty
        ? 1
        : _banners.map((b) => b.displayOrder).reduce((a, b) => a > b ? a : b) +
            1;
    await _bannersCollection.add({
      ...banner.copyWith(displayOrder: nextOrder).toMap(),
      'created_at': FieldValue.serverTimestamp(),
    });
    await loadBanners();
  }

  Future<void> updateBanner(BannerModel banner) async {
    if (banner.id.isEmpty) return;

    final oldDoc = await _bannersCollection.doc(banner.id).get();
    final oldBanner = oldDoc.exists && oldDoc.data() != null
        ? BannerModel.fromMap(oldDoc.data()!, id: oldDoc.id)
        : null;

    await _bannersCollection.doc(banner.id).update(banner.toMap());

    if (oldBanner != null &&
        oldBanner.bannerUrl.isNotEmpty &&
        oldBanner.bannerUrl != banner.bannerUrl) {
      await CloudinaryService.instance.deleteImageByUrl(oldBanner.bannerUrl);
    }

    await loadBanners();
  }

  /// Bật/tắt hiển thị banner ở Trang chủ. Cập nhật giao diện trước, lỗi thì hoàn lại.
  Future<void> setActive(String bannerId, bool isActive) async {
    final index = _banners.indexWhere((b) => b.id == bannerId);
    if (index < 0) return;
    final previous = _banners[index];
    _banners[index] = previous.copyWith(isActive: isActive);
    notifyListeners();
    try {
      await _bannersCollection.doc(bannerId).update({'is_active': isActive});
    } catch (e) {
      _banners[index] = previous;
      notifyListeners();
      rethrow;
    }
  }

  /// Kéo thả đổi thứ tự: ghi lại `display_order` = vị trí (1, 2, 3…) cho mọi banner
  /// trong một batch. Cập nhật giao diện trước, lỗi thì hoàn lại.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final previous = List<BannerModel>.of(_banners);
    final moved = _banners.removeAt(oldIndex);
    _banners.insert(newIndex, moved);
    _banners = [
      for (var i = 0; i < _banners.length; i++)
        _banners[i].copyWith(displayOrder: i + 1),
    ];
    notifyListeners();
    try {
      final batch = _db.batch();
      for (final b in _banners) {
        batch.update(_bannersCollection.doc(b.id), {'display_order': b.displayOrder});
      }
      await batch.commit();
    } catch (e) {
      _banners = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteBanner(String bannerId) async {
    final docSnapshot = await _bannersCollection.doc(bannerId).get();
    if (!docSnapshot.exists || docSnapshot.data() == null) return;

    final banner = BannerModel.fromMap(docSnapshot.data()!, id: docSnapshot.id);
    await _bannersCollection.doc(bannerId).delete();

    if (banner.bannerUrl.isNotEmpty) {
      await CloudinaryService.instance.deleteImageByUrl(banner.bannerUrl);
    }

    clearSelection();
    await loadBanners();
  }
}
