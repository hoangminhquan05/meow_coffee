import 'enums.dart';

/// Phân quyền màn hình theo vai trò. Mỗi vai trò có trang chủ riêng; mở một
/// màn không thuộc vai trò mình (kể cả do nút bấm gắn sai route) sẽ bị đưa về
/// trang chủ của vai trò đó.

/// Trang chủ theo vai trò.
String homeRouteFor(UserRole? role) => switch (role) {
      UserRole.customer => '/customer',
      UserRole.shipper => '/shipper',
      _ => '/home',
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
const _shipperRoutes = {'/shipper'};

/// Trả về route thay thế nếu `role` không được mở `name`; null nếu được mở.
/// Chưa đăng nhập (role null) thì không chặn – các màn đều cần đăng nhập
/// mới đọc được dữ liệu (Firestore Rules).
String? guardRoute(String? name, UserRole? role) {
  if (role == null || name == null) return null;
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
