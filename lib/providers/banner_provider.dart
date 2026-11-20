import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/env_config.dart';
import '../models/banner_model.dart';
import '../services/cloudinary_service.dart';

class BannerProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _bannersCollection =>
      _db.collection('banner');

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
          .map((doc) => BannerModel.fromMap(doc.data(), docId: doc.id))
          .toList();
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

  Future<String> uploadBannerImage(File file) async {
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
    final docRef = await _bannersCollection.add(banner.toMap());
    final bannerWithId = banner.copyWith(id: docRef.id);
    await docRef.set(bannerWithId.toMap());
    await loadBanners();
  }

  Future<void> updateBanner(BannerModel banner) async {
    if (banner.id.isEmpty) return;

    final oldDoc = await _bannersCollection.doc(banner.id).get();
    final oldBanner = oldDoc.exists && oldDoc.data() != null
        ? BannerModel.fromMap(oldDoc.data()!, docId: oldDoc.id)
        : null;

    await _bannersCollection.doc(banner.id).set(banner.toMap());

    if (oldBanner != null &&
        oldBanner.bannerUrl.isNotEmpty &&
        oldBanner.bannerUrl != banner.bannerUrl) {
      await CloudinaryService.instance.deleteImageByUrl(oldBanner.bannerUrl);
    }

    await loadBanners();
  }

  Future<void> deleteBanner(String bannerId) async {
    final docSnapshot = await _bannersCollection.doc(bannerId).get();
    if (!docSnapshot.exists || docSnapshot.data() == null) return;

    final banner = BannerModel.fromMap(docSnapshot.data()!, docId: docSnapshot.id);
    await _bannersCollection.doc(bannerId).delete();

    if (banner.bannerUrl.isNotEmpty) {
      await CloudinaryService.instance.deleteImageByUrl(banner.bannerUrl);
    }

    clearSelection();
    await loadBanners();
  }
}
