/// Giá trị enum lưu trên Firestore bằng tiếng Anh (`value`),
/// UI hiển thị tiếng Việt (`label`).
library;

T _fromValue<T extends Enum>(
  List<T> values,
  String? raw,
  T fallback,
  String Function(T) valueOf,
) {
  for (final v in values) {
    if (valueOf(v) == raw) return v;
  }
  return fallback;
}

enum UserRole {
  admin('admin', 'Quản lý'),
  staff('staff', 'Nhân viên'),
  customer('customer', 'Khách hàng'),
  shipper('shipper', 'Shipper');

  const UserRole(this.value, this.label);
  final String value;
  final String label;

  static UserRole fromValue(String? raw) =>
      _fromValue(values, raw, UserRole.staff, (e) => e.value);
}

enum OrderChannel {
  inStore('in_store', 'Tại quầy'),
  online('online', 'Online');

  const OrderChannel(this.value, this.label);
  final String value;
  final String label;

  static OrderChannel fromValue(String? raw) =>
      _fromValue(values, raw, OrderChannel.inStore, (e) => e.value);
}

enum Fulfillment {
  dineIn('dine_in', 'Tại quán'),
  takeaway('takeaway', 'Mang đi'),
  delivery('delivery', 'Giao hàng'),
  pickup('pickup', 'Tự đến lấy');

  const Fulfillment(this.value, this.label);
  final String value;
  final String label;

  static Fulfillment fromValue(String? raw) =>
      _fromValue(values, raw, Fulfillment.dineIn, (e) => e.value);
}

enum OrderStatus {
  pending('pending', 'Chờ xác nhận'),
  confirmed('confirmed', 'Đã xác nhận'),
  preparing('preparing', 'Đang pha chế'),
  delivering('delivering', 'Đang giao'),
  completed('completed', 'Hoàn tất'),
  cancelled('cancelled', 'Đã hủy');

  const OrderStatus(this.value, this.label);
  final String value;
  final String label;

  static OrderStatus fromValue(String? raw) =>
      _fromValue(values, raw, OrderStatus.completed, (e) => e.value);
}

enum PaymentStatus {
  unpaid('unpaid', 'Chưa thanh toán'),
  paid('paid', 'Đã thanh toán'),
  refunded('refunded', 'Đã hoàn tiền');

  const PaymentStatus(this.value, this.label);
  final String value;
  final String label;

  static PaymentStatus fromValue(String? raw) =>
      _fromValue(values, raw, PaymentStatus.paid, (e) => e.value);
}

enum PaymentMethod {
  cash('cash', 'Tiền mặt'),
  vietqr('vietqr', 'VietQR');

  const PaymentMethod(this.value, this.label);
  final String value;
  final String label;

  static PaymentMethod fromValue(String? raw) =>
      _fromValue(values, raw, PaymentMethod.cash, (e) => e.value);
}

enum TableStatus {
  available('available', 'Trống'),
  occupied('occupied', 'Bận');

  const TableStatus(this.value, this.label);
  final String value;
  final String label;

  static TableStatus fromValue(String? raw) =>
      _fromValue(values, raw, TableStatus.available, (e) => e.value);
}
