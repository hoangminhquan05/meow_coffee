import 'enums.dart';

/// Phân quyền màn hình theo vai trò. Mỗi vai trò có trang chủ riêng; mở một
/// màn không thuộc vai trò mình (kể cả do nút bấm gắn sai route) sẽ bị đưa về
/// trang chủ của vai trò đó.

/// Trang chủ theo vai trò. Chưa biết vai trò (chưa đăng nhập / chưa nạp
/// xong hồ sơ) → màn đăng nhập, không bao giờ rơi vào trang chủ nhân viên.
String homeRouteFor(UserRole? role) => switch (role) {
      UserRole.customer => '/customer',
      UserRole.shipper => '/shipper',
      UserRole.staff || UserRole.admin => '/home',
      null => '/login',
    };

/// Màn bán tại quầy + xử lý đơn online: nhân viên và admin.
const _sellerRoutes = {
  '/home',
  '/product',
  '/cart',
  '/payment',
  '/order_history',
  '/order_detail',
  '/profile',
  '/statistics',
  '/table_management',
  '/online_orders',
  '/online_order',
  '/shippers_live',
  '/shop_inbox',
};

/// Màn quản trị: chỉ admin.
const _adminRoutes = {
  '/adminproduct',
  '/add_product',
  '/edit_product',
  '/staff_management',
  '/add_staff',
  '/bannerManagement',
  '/shop_settings',
  '/payment_reviews',
  '/refunds',
};

/// Màn đặt hàng online: chỉ khách.
const _customerRoutes = {
  '/customer',
  '/checkout',
  '/online_cart',
  '/my_order',
  '/addresses',
};

/// Màn giao hàng: chỉ shipper.
const _shipperRoutes = {'/shipper', '/shipper_order'};

/// Trả về route thay thế nếu `role` không được mở `name`; null nếu được mở.
/// Chưa đăng nhập (role null): màn theo vai trò → về màn đăng nhập; màn dùng
/// chung (đăng nhập, đăng ký, quên mật khẩu…) mở bình thường.
String? guardRoute(String? name, UserRole? role) {
  if (name == null) return null;
  if (role == null) {
    final roleOnly = _adminRoutes.contains(name) ||
        _sellerRoutes.contains(name) ||
        _customerRoutes.contains(name) ||
        _shipperRoutes.contains(name);
    return roleOnly ? '/login' : null;
  }
  final allowed = switch (name) {
    _ when _adminRoutes.contains(name) => role == UserRole.admin,
    _ when _sellerRoutes.contains(name) =>
      role == UserRole.admin || role == UserRole.staff,
    _ when _customerRoutes.contains(name) => role == UserRole.customer,
    _ when _shipperRoutes.contains(name) => role == UserRole.shipper,
    _ => true, // màn dùng chung: đăng nhập, thông tin cá nhân, đổi mật khẩu, chi tiết món…
  };
  return allowed ? null : homeRouteFor(role);
}
