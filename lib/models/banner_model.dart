class BannerModel {
  final String id;
  final String bannerUrl;
  final String name;

  const BannerModel({
    this.id = '',
    this.bannerUrl = '',
    this.name = '',
  });

  factory BannerModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    return BannerModel(
      id: (docId != null && docId.isNotEmpty)
          ? docId
          : (map['id'] as String? ?? ''),
      bannerUrl: map['banner_url'] as String? ?? '',
      name: map['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'banner_url': bannerUrl,
      'name': name,
    };
  }

  BannerModel copyWith({
    String? id,
    String? bannerUrl,
    String? name,
  }) {
    return BannerModel(
      id: id ?? this.id,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      name: name ?? this.name,
    );
  }
}
