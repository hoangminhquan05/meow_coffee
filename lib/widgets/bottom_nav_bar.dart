import 'package:flutter/material.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
  });

  static const List<String> _routes = [
    '/home',
    '/product',
    '/cart',
    '/profile',
  ];

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    Navigator.pushReplacementNamed(context, _routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      backgroundColor: Colors.white,
      selectedIndex: currentIndex,
      onDestinationSelected: (index) => _onTap(context, index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home),
          label: 'Trang Chủ',
        ),
        NavigationDestination(
          icon: Icon(Icons.production_quantity_limits),
          label: 'Sản Phẩm',
        ),
        NavigationDestination(
          icon: Icon(Icons.shopping_cart),
          label: 'Giỏ Hàng',
        ),
        NavigationDestination(
          icon: Icon(Icons.person),
          label: 'Tài Khoản',
        ),
      ],
    );
  }
}
