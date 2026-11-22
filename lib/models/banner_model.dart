/// Banner trong `banners/{id}`.
class BannerModel {
  final String id;
  final String name;
  final String bannerUrl;
  final int displayOrder;
  final bool isActive;

  const BannerModel({
    this.id = '',
    this.name = '',
    this.bannerUrl = '',
    this.displayOrder = 0,
    this.isActive = true,
  });

  factory BannerModel.fromMap(Map<String, dynamic> map, {required String id}) {
    final order = map['display_order'];
    return BannerModel(
      id: id,
      name: map['name'] as String? ?? '',
      bannerUrl: map['banner_url'] as String? ?? '',
      displayOrder: order is num ? order.toInt() : 0,
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  /// Dữ liệu ghi Firestore (không gồm `id`, `created_at`).
  Map<String, dynamic> toMap() => {
        'name': name,
        'banner_url': bannerUrl,
        'display_order': displayOrder,
        'is_active': isActive,
      };

  BannerModel copyWith({
    String? id,
    String? name,
    String? bannerUrl,
    int? displayOrder,
    bool? isActive,
  }) {
    return BannerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}
