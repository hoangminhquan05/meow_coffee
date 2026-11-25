import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/customer_cart_provider.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import '../online/customer_cart_screen.dart';
import '../online/my_orders_screen.dart';
import '../product/product_screen.dart';
import '../shipper/shipper_home_screen.dart';
import 'account_screen.dart';

/// Khung app khách: Trang chủ · Thực đơn · Giỏ · Đơn của tôi · Tài khoản.
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final cartCount = context.select<CustomerCartProvider, int>((c) => c.totalItems);
    final pages = <Widget>[
      const HomeScreen(),
      const ProductScreen(),
      CustomerCartScreen(onBrowseMenu: () => setState(() => _index = 1)),
      const MyOrdersScreen(),
      const AccountScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.soft,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Trang chủ'),
          const NavigationDestination(
              icon: Icon(Icons.local_cafe_outlined),
              selectedIcon: Icon(Icons.local_cafe_rounded),
              label: 'Thực đơn'),
          NavigationDestination(
              icon: Badge(
                isLabelVisible: cartCount > 0,
                label: Text('$cartCount'),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: cartCount > 0,
                label: Text('$cartCount'),
                child: const Icon(Icons.shopping_bag_rounded),
              ),
              label: 'Giỏ'),
          const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Đơn'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Tài khoản'),
        ],
      ),
    );
  }
}

/// Khung app shipper: Giao hàng (ca + GPS, bước 8) · Tài khoản.
class ShipperShell extends StatefulWidget {
  const ShipperShell({super.key});

  @override
  State<ShipperShell> createState() => _ShipperShellState();
}

class _ShipperShellState extends State<ShipperShell> {
  int _index = 0;

  static const _pages = <Widget>[
    ShipperHomeScreen(),
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
