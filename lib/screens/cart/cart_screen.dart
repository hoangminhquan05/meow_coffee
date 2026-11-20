import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/cart_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/bottom_nav_bar.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final cart = context.watch<CartProvider>();

    return Scaffold(
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cart.cartItems.isNotEmpty) _CheckoutBar(cart: cart),
          const BottomNavBar(currentIndex: 2),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Giỏ Hàng',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ),
                      Text(
                        'ID: ${userId ?? "Khách"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: cart.cartItems.isEmpty
                      ? const _EmptyCartPlaceholder()
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: cart.cartItems.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            return _CartItemCard(item: cart.cartItems[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCartPlaceholder extends StatelessWidget {
  const _EmptyCartPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart,
              size: 80,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Giỏ hàng của bạn đang trống',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hãy thêm sản phẩm bạn yêu thích vào giỏ hàng',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  final CartProvider cart;

  const _CheckoutBar({required this.cart});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: colorScheme.surfaceContainerHighest,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tổng cộng:',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  formatVnd(cart.totalPrice, suffix: 'đ'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/payment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.payment, size: 20),
                label: const Text('Thanh Toán'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final CartItem item;

  const _CartItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cart = context.read<CartProvider>();

    return Card(
      elevation: 2,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: CachedNetworkImage(
                  imageUrl: item.product.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Colors.grey.shade200),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.coffee, color: Colors.brown),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.product.formattedPrice,
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SmallIconButton(
                    icon: Icons.remove,
                    color: colorScheme.error,
                    bgColor: colorScheme.error.withValues(alpha: 0.1),
                    onPressed: () => cart.decreaseQuantity(item.product),
                  ),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${item.quantity}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  _SmallIconButton(
                    icon: Icons.add,
                    color: colorScheme.primary,
                    bgColor: colorScheme.primary.withValues(alpha: 0.1),
                    onPressed: () => cart.increaseQuantity(item.product),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _SmallIconButton(
              icon: Icons.delete,
              color: colorScheme.error,
              bgColor: colorScheme.errorContainer.withValues(alpha: 0.3),
              onPressed: () => cart.removeFromCart(item.product),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onPressed;

  const _SmallIconButton({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
