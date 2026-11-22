import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'config/env_config.dart';
import 'providers/banner_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/session_provider.dart';
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
  runApp(const MeowCoffeeApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();

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
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Meow Coffee',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        initialRoute: '/login',
        onGenerateRoute: (settings) {
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
              return MaterialPageRoute(builder: (_) => const AddStaffScreen());
            case '/bannerManagement':
              return MaterialPageRoute(
                builder: (_) => const BannerManagementScreen(),
              );
            case '/table_management':
              return MaterialPageRoute(
                builder: (_) => const TableManagementScreen(),
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
