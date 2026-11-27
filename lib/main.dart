import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'config/env_config.dart';
import 'core/enums.dart';
import 'core/route_guard.dart';
import 'models/chat.dart';
import 'models/order.dart';
import 'providers/banner_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/customer_cart_provider.dart';
import 'providers/online_orders_provider.dart';
import 'providers/session_provider.dart';
import 'providers/shop_settings_provider.dart';
import 'screens/address/address_book_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/chat/shop_inbox_screen.dart';
import 'screens/admin/payment_reviews_screen.dart';
import 'screens/admin/refunds_screen.dart';
import 'screens/staff/online_order_detail_screen.dart';
import 'screens/staff/online_orders_screen.dart';
import 'screens/staff/shippers_live_screen.dart';
import 'utils/alert_sound.dart';
import 'utils/formatters.dart';
import 'screens/admin/shop_settings_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/startup_screen.dart';
import 'screens/auth/verify_account_screen.dart';
import 'screens/online/checkout_screen.dart';
import 'screens/online/customer_cart_screen.dart';
import 'screens/online/customer_order_detail_screen.dart';
import 'screens/shell/role_shells.dart';
import 'screens/shipper/shipper_order_screen.dart';
import 'screens/admin/add_product_screen.dart';
import 'screens/admin/add_staff_screen.dart';
import 'screens/admin/admin_product_screen.dart';
import 'screens/admin/banner_management_screen.dart';
import 'screens/admin/edit_product_screen.dart';
import 'screens/admin/staff_management_screen.dart';
import 'screens/admin/statistics_screen.dart';
import 'screens/admin/table_management_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/cart/cart_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/orders/order_history_screen.dart';
import 'screens/payment/payment_screen.dart';
import 'screens/product/product_detail_screen.dart';
import 'screens/product/product_screen.dart';
import 'screens/profile/change_password_screen.dart';
import 'screens/profile/edit_user_info_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/user_info_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp(options: EnvConfig.firebaseOptions);
  // Chế độ thử OTP: chỉ dùng số test khai báo trong Firebase Console, bỏ bước
  // reCAPTCHA. Chỉ bật trong bản debug và khi .env có AUTH_PHONE_TEST_MODE=true
  // (project chưa bật Blaze nên không gửi được SMS thật).
  if (kDebugMode && EnvConfig.authPhoneTestMode) {
    await FirebaseAuth.instance
        .setSettings(appVerificationDisabledForTesting: true);
  }
  runApp(const MeowCoffeeApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Đơn mới vào "Chờ xác nhận" khi app đang mở (chưa có push – bước 11).
void _alertNewOrder(Order order) {
  AlertSound.notify();
  _messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      content: Text('Đơn mới ${order.orderCode} · ${formatMoney(order.total)}'),
      action: SnackBarAction(
        label: 'Xem',
        onPressed: () => _navigatorKey.currentState
            ?.pushNamed('/online_order', arguments: order.id),
      ),
    ));
}

/// Tin nhắn mới khi app đang mở (chưa có push – bước 11). NV và shipper
/// kèm tiếng báo + rung; khách chỉ hiện thanh báo.
void _alertChat(ChatAlert alert) {
  if (alert.sound) AlertSound.notify();
  _messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      content: Text(
        '${alert.args.title}: ${alert.preview}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      action: SnackBarAction(
        label: 'Mở',
        onPressed: () =>
            _navigatorKey.currentState?.pushNamed('/chat', arguments: alert.args),
      ),
    ));
}

class MeowCoffeeApp extends StatelessWidget {
  const MeowCoffeeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => BannerProvider()),
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) {
            final session = SessionProvider();
            // Bị khóa / mất quyền khi đang dùng → xóa giỏ, về đăng nhập (Q14).
            session.onForcedSignOut = () {
              ctx.read<CartProvider>().clear();
              _navigatorKey.currentState
                  ?.pushNamedAndRemoveUntil('/login', (route) => false);
            };
            return session;
          },
        ),
        // Giỏ hàng khách (Firestore carts/{uid}): chỉ chạy với tài khoản khách.
        ChangeNotifierProxyProvider<SessionProvider, CustomerCartProvider>(
          lazy: false,
          create: (_) => CustomerCartProvider(),
          update: (_, session, cart) =>
              cart!..bindTo(session.isCustomer ? session.uid : null),
        ),
        // Đơn online đang xử lý: chỉ NV/admin; báo đơn mới (âm thanh + rung).
        ChangeNotifierProxyProvider<SessionProvider, OnlineOrdersProvider>(
          lazy: false,
          create: (_) => OnlineOrdersProvider()..onNewOrder = _alertNewOrder,
          update: (_, session, orders) =>
              orders!..setEnabled(session.isSeller),
        ),
        // Chat (bước 10): tin chưa đọc + báo tin mới theo vai trò.
        ChangeNotifierProxyProvider<SessionProvider, ChatProvider>(
          lazy: false,
          create: (_) => ChatProvider()..onIncoming = _alertChat,
          update: (_, session, chats) =>
              chats!..bind(session.uid, ChatRole.forUser(session.user?.role)),
        ),
        // Cài đặt quán: chỉ lắng nghe khi đã đăng nhập.
        ChangeNotifierProxyProvider<SessionProvider, ShopSettingsProvider>(
          lazy: false,
          create: (_) => ShopSettingsProvider(),
          update: (_, session, shop) =>
              shop!..setActive(session.isSignedIn),
        ),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        title: 'Meow Coffee',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        initialRoute: '/',
        // Mở app / F5 trên web (dù URL đang ở /#/home hay /#/shipper) luôn đi
        // qua màn khởi động: chờ biết ai đang đăng nhập rồi mới chọn trang chủ.
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute(
            settings: const RouteSettings(name: '/'),
            builder: (_) => const StartupScreen(),
          ),
        ],
        onGenerateRoute: (settings) {
          // Mở màn không thuộc vai trò mình → về trang chủ của vai trò đó.
          final navContext = _navigatorKey.currentContext;
          final role = navContext == null
              ? null
              : Provider.of<SessionProvider>(navContext, listen: false).user?.role;
          final redirect = guardRoute(settings.name, role);
          if (redirect != null) {
            debugPrint('Route ${settings.name} không dành cho $role → $redirect');
            settings = RouteSettings(name: redirect);
          }
          switch (settings.name) {
            case '/login':
              return MaterialPageRoute(builder: (_) => const LoginScreen());
            case '/forgot_pass':
              return MaterialPageRoute(
                builder: (_) => const ForgotPasswordScreen(),
              );
            case '/reset_pass':
              final phone = settings.arguments as String? ?? '';
              return MaterialPageRoute(
                builder: (_) => ResetPasswordScreen(phone: phone),
              );
            case '/home':
              return MaterialPageRoute(builder: (_) => const HomeScreen());
            case '/product':
              return MaterialPageRoute(builder: (_) => const ProductScreen());
            case '/product_detail':
              final productId = settings.arguments as String? ?? '';
              return MaterialPageRoute(
                builder: (_) => ProductDetailScreen(productId: productId),
              );
            case '/cart':
              return MaterialPageRoute(builder: (_) => const CartScreen());
            case '/payment':
              return MaterialPageRoute(builder: (_) => const PaymentScreen());
            case '/order_history':
              return MaterialPageRoute(
                builder: (_) => const OrderHistoryScreen(),
              );
            case '/order_detail':
              final orderId = settings.arguments as String? ?? '';
              return MaterialPageRoute(
                builder: (_) => OrderDetailScreen(orderId: orderId),
              );
            case '/profile':
              return MaterialPageRoute(builder: (_) => const ProfileScreen());
            case '/thongtincanhan':
              final userId = settings.arguments as String?;
              return MaterialPageRoute(
                builder: (_) => UserInfoScreen(userId: userId),
              );
            case '/editUserInfo':
              final userId = settings.arguments as String?;
              return MaterialPageRoute(
                builder: (_) => EditUserInfoScreen(userId: userId),
              );
            case '/change_password':
              return MaterialPageRoute(
                builder: (_) => const ChangePasswordScreen(),
              );
            case '/adminproduct':
              return MaterialPageRoute(
                builder: (_) => const AdminProductScreen(),
              );
            case '/add_product':
              return MaterialPageRoute(
                builder: (_) => const AddProductScreen(),
              );
            case '/edit_product':
              final productId = settings.arguments as String?;
              return MaterialPageRoute(
                builder: (_) => EditProductScreen(productId: productId),
              );
            case '/staff_management':
              return MaterialPageRoute(
                builder: (_) => const StaffManagementScreen(),
              );
            case '/add_staff':
              final role = settings.arguments as UserRole? ?? UserRole.staff;
              return MaterialPageRoute(
                builder: (_) => AddStaffScreen(initialRole: role),
              );
            case '/bannerManagement':
              return MaterialPageRoute(
                builder: (_) => const BannerManagementScreen(),
              );
            case '/table_management':
              return MaterialPageRoute(
                builder: (_) => const TableManagementScreen(),
              );
            case '/register':
              return MaterialPageRoute(builder: (_) => const RegisterScreen());
            case '/verify_account':
              final args = settings.arguments as VerifyAccountArgs? ??
                  const VerifyAccountArgs();
              return MaterialPageRoute(
                builder: (_) => VerifyAccountScreen(args: args),
              );
            case '/checkout':
              return MaterialPageRoute(builder: (_) => const CheckoutScreen());
            case '/online_cart':
              return MaterialPageRoute(
                builder: (_) => const CustomerCartScreen(standalone: true),
              );
            case '/my_order':
              final orderId = settings.arguments as String? ?? '';
              return MaterialPageRoute(
                builder: (_) => CustomerOrderDetailScreen(orderId: orderId),
              );
            case '/addresses':
              return MaterialPageRoute(
                builder: (_) => const AddressBookScreen(),
              );
            case '/customer':
              return MaterialPageRoute(builder: (_) => const CustomerShell());
            case '/shipper':
              return MaterialPageRoute(builder: (_) => const ShipperShell());
            case '/shipper_order':
              final orderId = settings.arguments as String? ?? '';
              return MaterialPageRoute(
                builder: (_) => ShipperOrderScreen(orderId: orderId),
              );
            case '/online_orders':
              return MaterialPageRoute(
                builder: (_) => const OnlineOrdersScreen(),
              );
            case '/online_order':
              final orderId = settings.arguments as String? ?? '';
              return MaterialPageRoute(
                builder: (_) => OnlineOrderDetailScreen(orderId: orderId),
              );
            case '/chat':
              final args = settings.arguments;
              if (args is! ChatArgs) {
                return MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(),
                    body: const Center(child: Text('Không mở được cuộc trò chuyện')),
                  ),
                );
              }
              return MaterialPageRoute(builder: (_) => ChatScreen(args: args));
            case '/shop_inbox':
              return MaterialPageRoute(builder: (_) => const ShopInboxScreen());
            case '/shippers_live':
              return MaterialPageRoute(
                builder: (_) => const ShippersLiveScreen(),
              );
            case '/refunds':
              return MaterialPageRoute(builder: (_) => const RefundsScreen());
            case '/payment_reviews':
              return MaterialPageRoute(
                builder: (_) => const PaymentReviewsScreen(),
              );
            case '/shop_settings':
              return MaterialPageRoute(
                builder: (_) => const ShopSettingsScreen(),
              );
            case '/statistics':
              return MaterialPageRoute(
                builder: (_) => const StatisticsScreen(),
              );
            default:
              return MaterialPageRoute(builder: (_) => const LoginScreen());
          }
        },
      ),
    );
  }
}
