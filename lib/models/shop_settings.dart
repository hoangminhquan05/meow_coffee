import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// Phí giao hàng: `base_km` km đầu giá `base_fee`, mỗi km tiếp theo `per_km`.
/// Giai đoạn 1 tắt (`enabled = false`) → phí = 0 (O9).
class ShippingFeeConfig {
  final bool enabled;
  final double baseKm;
  final int baseFee;
  final int perKm;

  const ShippingFeeConfig({
    this.enabled = false,
    this.baseKm = 3,
    this.baseFee = 15000,
    this.perKm = 5000,
  });

  /// Phí cho quãng đường `km` (làm tròn lên từng km sau phần mở đầu).
  int feeFor(double km) {
    if (!enabled) return 0;
    if (km <= baseKm) return baseFee;
    return baseFee + (km - baseKm).ceil() * perKm;
  }

  factory ShippingFeeConfig.fromMap(Map<String, dynamic>? m) {
    const d = ShippingFeeConfig();
    if (m == null) return d;
    return ShippingFeeConfig(
      enabled: m['enabled'] as bool? ?? d.enabled,
      baseKm: (m['base_km'] as num?)?.toDouble() ?? d.baseKm,
      baseFee: (m['base_fee'] as num?)?.round() ?? d.baseFee,
      perKm: (m['per_km'] as num?)?.round() ?? d.perKm,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'base_km': baseKm,
        'base_fee': baseFee,
        'per_km': perKm,
      };
}

/// Trọng số chấm điểm gán shipper (mục 6 kế hoạch online).
class DispatchWeights {
  final double load;
  final double pickupKm;
  final double detourKm;
  final double today;

  const DispatchWeights({
    this.load = 3,
    this.pickupKm = 1,
    this.detourKm = 2,
    this.today = 0.2,
  });

  factory DispatchWeights.fromMap(Map<String, dynamic>? m) {
    const d = DispatchWeights();
    if (m == null) return d;
    double v(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    return DispatchWeights(
      load: v('load', d.load),
      pickupKm: v('pickup_km', d.pickupKm),
      detourKm: v('detour_km', d.detourKm),
      today: v('today', d.today),
    );
  }

  Map<String, dynamic> toMap() => {
        'load': load,
        'pickup_km': pickupKm,
        'detour_km': detourKm,
        'today': today,
      };
}

class DispatchConfig {
  final int offerSeconds;
  final int maxOrdersPerShipper;
  final double batchRadiusKm;
  final int staleLocationMin;
  final DispatchWeights weights;

  const DispatchConfig({
    this.offerSeconds = 60,
    this.maxOrdersPerShipper = 3,
    this.batchRadiusKm = 1.5,
    this.staleLocationMin = 10,
    this.weights = const DispatchWeights(),
  });

  factory DispatchConfig.fromMap(Map<String, dynamic>? m) {
    const d = DispatchConfig();
    if (m == null) return d;
    return DispatchConfig(
      offerSeconds: (m['offer_seconds'] as num?)?.round() ?? d.offerSeconds,
      maxOrdersPerShipper:
          (m['max_orders_per_shipper'] as num?)?.round() ?? d.maxOrdersPerShipper,
      batchRadiusKm:
          (m['batch_radius_km'] as num?)?.toDouble() ?? d.batchRadiusKm,
      staleLocationMin:
          (m['stale_location_min'] as num?)?.round() ?? d.staleLocationMin,
      weights: DispatchWeights.fromMap(
        (m['weights'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'offer_seconds': offerSeconds,
        'max_orders_per_shipper': maxOrdersPerShipper,
        'batch_radius_km': batchRadiusKm,
        'stale_location_min': staleLocationMin,
        'weights': weights.toMap(),
      };
}

/// Điều kiện báo "Giao không thành công" (O29).
class DeliveryFailureConfig {
  final int waitMinutes;
  final int minCallAttempts;

  const DeliveryFailureConfig({this.waitMinutes = 10, this.minCallAttempts = 2});

  factory DeliveryFailureConfig.fromMap(Map<String, dynamic>? m) {
    const d = DeliveryFailureConfig();
    if (m == null) return d;
    return DeliveryFailureConfig(
      waitMinutes: (m['wait_minutes'] as num?)?.round() ?? d.waitMinutes,
      minCallAttempts:
          (m['min_call_attempts'] as num?)?.round() ?? d.minCallAttempts,
    );
  }

  Map<String, dynamic> toMap() => {
        'wait_minutes': waitMinutes,
        'min_call_attempts': minCallAttempts,
      };
}

/// Cài đặt quán trong `settings/shop`.
class ShopSettings {
  /// Giá trị dùng khi chưa có doc (giữ thông tin cũ đang in trên hóa đơn).
  static const defaults = ShopSettings();

  final String name;
  final String address;
  final String phone;
  final LatLng? location;
  final String openTime; // "HH:mm"
  final String closeTime; // "HH:mm", có thể nhỏ hơn openTime (qua nửa đêm)
  final bool onlinePaused;
  final double maxDeliveryKm;
  final int minOrderValue; // 0 = tắt
  final ShippingFeeConfig shippingFee;
  final int paymentTimeoutMin;

  /// Chặn đặt đơn khi không có shipper trong ca (O30). Admin bật khi quán đủ người.
  final bool requireShipperOnShift;
  final DispatchConfig dispatch;
  final DeliveryFailureConfig deliveryFailure;
  final DateTime? updatedAt;
  final String? updatedByName;

  const ShopSettings({
    this.name = 'Meow Coffee',
    this.address = '83 Hai Bà Trưng, Hoàn Kiếm, TP. Hà Nội',
    this.phone = '032 8386 66',
    this.location,
    this.openTime = '07:00',
    this.closeTime = '22:00',
    this.onlinePaused = false,
    this.maxDeliveryKm = 7,
    this.minOrderValue = 50000,
    this.shippingFee = const ShippingFeeConfig(),
    this.paymentTimeoutMin = 2,
    this.requireShipperOnShift = false,
    this.dispatch = const DispatchConfig(),
    this.deliveryFailure = const DeliveryFailureConfig(),
    this.updatedAt,
    this.updatedByName,
  });

  bool get hasLocation => location != null;

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  /// Đang trong giờ nhận đơn online không (hỗ trợ khung qua nửa đêm).
  bool isWithinHours(DateTime now) {
    final open = _minutes(openTime);
    final close = _minutes(closeTime);
    final t = now.hour * 60 + now.minute;
    if (open == close) return true; // mở cả ngày
    if (open < close) return t >= open && t < close;
    return t >= open || t < close;
  }

  /// Lý do không nhận đơn online lúc này (null = đang nhận).
  /// Các điều kiện theo từng đơn (đơn tối thiểu, bán kính, shipper) kiểm ở bước sau.
  String? closedReason(DateTime now) {
    if (!hasLocation) return 'Quán chưa thiết lập vị trí, tạm chưa nhận đơn online';
    if (onlinePaused) return 'Quán đang tạm ngưng nhận đơn online';
    if (!isWithinHours(now)) {
      return 'Quán nhận đơn online từ $openTime đến $closeTime';
    }
    return null;
  }

  factory ShopSettings.fromMap(Map<String, dynamic> m) {
    const d = defaults;
    final loc = m['location'];
    LatLng? location;
    if (loc is Map && loc['lat'] is num && loc['lng'] is num) {
      location = LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );
    } else if (loc is GeoPoint) {
      location = LatLng(loc.latitude, loc.longitude);
    }
    final updatedAt = m['updated_at'];
    final updatedBy = m['updated_by'];
    return ShopSettings(
      name: m['name'] as String? ?? d.name,
      address: m['address'] as String? ?? d.address,
      phone: m['phone'] as String? ?? d.phone,
      location: location,
      openTime: m['open_time'] as String? ?? d.openTime,
      closeTime: m['close_time'] as String? ?? d.closeTime,
      onlinePaused: m['online_paused'] as bool? ?? d.onlinePaused,
      maxDeliveryKm:
          (m['max_delivery_km'] as num?)?.toDouble() ?? d.maxDeliveryKm,
      minOrderValue: (m['min_order_value'] as num?)?.round() ?? d.minOrderValue,
      shippingFee: ShippingFeeConfig.fromMap(
        (m['shipping_fee'] as Map?)?.cast<String, dynamic>(),
      ),
      paymentTimeoutMin:
          (m['payment_timeout_min'] as num?)?.round() ?? d.paymentTimeoutMin,
      requireShipperOnShift:
          m['require_shipper_on_shift'] as bool? ?? d.requireShipperOnShift,
      dispatch: DispatchConfig.fromMap(
        (m['dispatch'] as Map?)?.cast<String, dynamic>(),
      ),
      deliveryFailure: DeliveryFailureConfig.fromMap(
        (m['delivery_failure'] as Map?)?.cast<String, dynamic>(),
      ),
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
      updatedByName: updatedBy is Map ? updatedBy['name'] as String? : null,
    );
  }

  /// Dữ liệu ghi Firestore (không gồm updated_at/updated_by).
  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        'phone': phone,
        'location': location == null
            ? null
            : {'lat': location!.latitude, 'lng': location!.longitude},
        'open_time': openTime,
        'close_time': closeTime,
        'online_paused': onlinePaused,
        'max_delivery_km': maxDeliveryKm,
        'min_order_value': minOrderValue,
        'shipping_fee': shippingFee.toMap(),
        'payment_timeout_min': paymentTimeoutMin,
        'require_shipper_on_shift': requireShipperOnShift,
        'dispatch': dispatch.toMap(),
        'delivery_failure': deliveryFailure.toMap(),
      };
}
