import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import '../product/product_screen.dart';
import 'account_screen.dart';

/// Khung app khách: Trang chủ · Thực đơn · Giỏ · Đơn của tôi · Tài khoản.
/// Giỏ và Đơn của tôi làm ở bước 5 kế hoạch online.
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;

  static const _pages = <Widget>[
    HomeScreen(),
    ProductScreen(),
    ComingSoonScreen(
      title: 'Giỏ Hàng',
      icon: Icons.shopping_bag_outlined,
      message: 'Đặt món online giao tận nơi sắp ra mắt.',
    ),
    ComingSoonScreen(
      title: 'Đơn Của Tôi',
      icon: Icons.receipt_long_outlined,
      message: 'Theo dõi đơn online sẽ có ở đây.',
    ),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.soft,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Trang chủ'),
          NavigationDestination(
              icon: Icon(Icons.local_cafe_outlined),
              selectedIcon: Icon(Icons.local_cafe_rounded),
              label: 'Thực đơn'),
          NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag_rounded),
              label: 'Giỏ'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Đơn'),
          NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Tài khoản'),
        ],
      ),
    );
  }
}

/// Khung app shipper: Giao hàng (bước 8–9) · Tài khoản.
class ShipperShell extends StatefulWidget {
  const ShipperShell({super.key});

  @override
  State<ShipperShell> createState() => _ShipperShellState();
}

class _ShipperShellState extends State<ShipperShell> {
  int _index = 0;

  static const _pages = <Widget>[
    ComingSoonScreen(
      title: 'Giao Hàng',
      icon: Icons.delivery_dining_outlined,
      message: 'Nhận và giao đơn online sẽ có ở đây.',
    ),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.soft,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.delivery_dining_outlined),
              selectedIcon: Icon(Icons.delivery_dining),
              label: 'Giao hàng'),
          NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Tài khoản'),
        ],
      ),
    );
  }
}

class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String message;

  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bg,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: AppColors.soft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: AppColors.brand),
              ),
              const SizedBox(height: 18),
              const Text(
                'Sắp ra mắt',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
