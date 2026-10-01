// Domain Models for Seller Hub / Store Management Modules.

/// DRF serialises decimals as strings; accept either form.
double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class SellerStoreProfile {
  const SellerStoreProfile({
    required this.id,
    required this.storeName,
    this.slug,
    this.tagline = '',
    this.description = '',
    this.logoUrl = '',
    this.bannerUrl = '',
    this.fssaiLicenseNumber = '',
    this.storeAddress = '',
    this.deliveryRadiusKm = 5.0,
    this.minimumOrderAmount = '0.00',
    this.estimatedDeliveryMins = 30,
    this.isAcceptingOrders = true,
    this.latitude,
    this.longitude,
    this.ratingAvg = 5.0,
    this.ratingCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String storeName;
  final String? slug;
  final String tagline;
  final String description;
  final String logoUrl;
  final String bannerUrl;
  final String fssaiLicenseNumber;
  final String storeAddress;
  final double deliveryRadiusKm;
  final String minimumOrderAmount;
  final int estimatedDeliveryMins;
  final bool isAcceptingOrders;

  /// Store pickup pin used for rider dispatch (null until configured).
  final double? latitude;
  final double? longitude;
  final double ratingAvg;
  final int ratingCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SellerStoreProfile.fromJson(Map<String, dynamic> json) {
    return SellerStoreProfile(
      id: json['id'] as int? ?? 0,
      storeName: json['store_name'] as String? ?? 'Seller Store',
      slug: json['slug'] as String?,
      tagline: json['tagline'] as String? ?? '',
      description: json['description'] as String? ?? '',
      logoUrl: json['logo_url'] as String? ?? '',
      bannerUrl: json['banner_url'] as String? ?? '',
      fssaiLicenseNumber: json['fssai_license_number'] as String? ?? '',
      storeAddress: json['store_address'] as String? ?? '',
      deliveryRadiusKm: _num(json['delivery_radius_km']) ?? 5.0,
      minimumOrderAmount: json['minimum_order_amount']?.toString() ?? '0.00',
      estimatedDeliveryMins:
          _num(json['estimated_delivery_mins'])?.toInt() ?? 30,
      isAcceptingOrders: json['is_accepting_orders'] as bool? ?? true,
      latitude: _num(json['latitude']),
      longitude: _num(json['longitude']),
      ratingAvg: _num(json['rating_avg']) ?? 5.0,
      ratingCount: _num(json['rating_count'])?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'store_name': storeName,
    'tagline': tagline,
    'description': description,
    'logo_url': logoUrl,
    'banner_url': bannerUrl,
    'fssai_license_number': fssaiLicenseNumber,
    'store_address': storeAddress,
    'delivery_radius_km': deliveryRadiusKm,
    'minimum_order_amount': minimumOrderAmount,
    'estimated_delivery_mins': estimatedDeliveryMins,
    'is_accepting_orders': isAcceptingOrders,
    'latitude': latitude,
    'longitude': longitude,
  };

  SellerStoreProfile copyWith({
    int? id,
    String? storeName,
    String? slug,
    String? tagline,
    String? description,
    String? logoUrl,
    String? bannerUrl,
    String? fssaiLicenseNumber,
    String? storeAddress,
    double? deliveryRadiusKm,
    String? minimumOrderAmount,
    int? estimatedDeliveryMins,
    bool? isAcceptingOrders,
    double? ratingAvg,
    int? ratingCount,
  }) {
    return SellerStoreProfile(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
      slug: slug ?? this.slug,
      tagline: tagline ?? this.tagline,
      description: description ?? this.description,
      logoUrl: logoUrl ?? this.logoUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      fssaiLicenseNumber: fssaiLicenseNumber ?? this.fssaiLicenseNumber,
      storeAddress: storeAddress ?? this.storeAddress,
      deliveryRadiusKm: deliveryRadiusKm ?? this.deliveryRadiusKm,
      minimumOrderAmount: minimumOrderAmount ?? this.minimumOrderAmount,
      estimatedDeliveryMins:
          estimatedDeliveryMins ?? this.estimatedDeliveryMins,
      isAcceptingOrders: isAcceptingOrders ?? this.isAcceptingOrders,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
