import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/shipper_status.dart';
import '../../providers/customer_cart_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/shipper_service.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import '../online/customer_cart_screen.dart';
import '../online/my_orders_screen.dart';
import '../product/product_screen.dart';
import '../shipper/offer_dialog.dart';
import '../shipper/shipper_home_screen.dart';
import '../shipper/shipper_today_screen.dart';
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

/// Khung app shipper: Giao hàng (ca, GPS, đơn đang giữ) · Hôm nay · Tài khoản.
/// Lời mời giao đơn (bước 9) bật lên toàn màn hình ở mọi tab.
class ShipperShell extends StatefulWidget {
  const ShipperShell({super.key});

  @override
  State<ShipperShell> createState() => _ShipperShellState();
}

class _ShipperShellState extends State<ShipperShell> {
  int _index = 0;
  StreamSubscription<ShipperStatus>? _sub;
  String? _shownOfferId;

  static const _pages = <Widget>[
    ShipperHomeScreen(),
    ShipperTodayScreen(),
    AccountScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Lời mời giao đơn hiện toàn màn hình dù đang ở tab nào (bước 9).
    final uid = context.read<SessionProvider>().uid;
    _sub = ShipperService.watchMine(uid).listen(_onStatus, onError: (Object e) {
      debugPrint('ShipperShell status error: $e');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onStatus(ShipperStatus s) async {
    final offer = s.liveOffer(DateTime.now());
    if (offer == null || offer.offerId == _shownOfferId || !mounted) return;
    _shownOfferId = offer.offerId;
    final accepted = await showOfferDialog(context, offer);
    if (accepted && mounted) {
      setState(() => _index = 0);
      Navigator.of(context).pushNamed('/shipper_order', arguments: offer.orderId);
    }
  }

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
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today_rounded),
              label: 'Hôm nay'),
          NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Tài khoản'),
        ],
      ),
    );
  }
}
