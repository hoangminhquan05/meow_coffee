import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/firestore_paths.dart';
import '../../models/banner_model.dart';
import '../../models/product.dart';
import '../../providers/session_provider.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_to_cart_sheet.dart';
import '../../widgets/bottom_nav_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Realtime: món bị đánh dấu hết hàng ở máy khác hiện ngay (L10).
  late final Stream<List<Product>> _productsStream = ProductService.watchAll();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // Khách dùng thanh điều hướng của CustomerShell.
      bottomNavigationBar: context.select<SessionProvider, bool>(
        (s) => s.isCustomer,
      )
          ? null
          : const BottomNavBar(currentIndex: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HomeTopBar(),
              const SizedBox(height: 12),
              const _BannerSection(),
              const SizedBox(height: 24),
              StreamBuilder<List<Product>>(
                stream: _productsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Lỗi tải sản phẩm: ${snapshot.error}',
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child:
                            CircularProgressIndicator(color: AppColors.brand),
                      ),
                    );
                  }
                  final products = snapshot.data!;
                  if (products.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Hiện chưa có sản phẩm nào',
                        style: TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    );
                  }
                  // Mỗi danh mục một hàng, theo dữ liệu thực tế.
                  final categories = <String>[];
                  for (final p in products) {
                    final c = p.category.isEmpty ? 'Khác' : p.category;
                    if (!categories.contains(c)) categories.add(c);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in categories)
                        _CategorySection(
                          eyebrow: 'DANH MỤC',
                          title: c,
                          products: products
                              .where((p) =>
                                  (p.category.isEmpty ? 'Khác' : p.category) ==
                                  c)
                              .toList(),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Text(
                'Meow Coffee',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkSlate,
                  letterSpacing: -0.6,
                ),
              ),
              SizedBox(width: 6),
              Text('☕', style: TextStyle(fontSize: 20)),
            ],
          ),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 12,
                      color: AppColors.brand,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'AI Gợi ý',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BannerSection extends StatefulWidget {
  const _BannerSection();

  @override
  State<_BannerSection> createState() => _BannerSectionState();
}

/// Banner Trang chủ: đọc realtime `banners` (đang hiện, có ảnh, theo display_order).
/// Đang tải → khung xám loading; không có banner hoặc lỗi → ảnh tĩnh banner.jpg.
class _BannerSectionState extends State<_BannerSection> {
  static const _height = 184.0;

  final PageController _pageController = PageController(viewportFraction: 0.90);
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<BannerModel> _banners = [];
  bool _isLoading = true;
  Timer? _autoScrollTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection(FsCollections.banners)
        .snapshots()
        .listen(_onSnapshot, onError: (Object e) {
      debugPrint('_BannerSection banners stream error: $e');
      if (!mounted) return;
      setState(() {
        _banners = [];
        _isLoading = false;
      });
      _restartAutoScroll();
    });
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!mounted) return;
    final loaded = snapshot.docs
        .map((doc) => BannerModel.fromMap(doc.data(), id: doc.id))
        .where((b) => b.isActive && b.bannerUrl.isNotEmpty)
        .toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    setState(() {
      _banners = loaded;
      _isLoading = false;
      // Danh sách ngắn lại (admin ẩn banner) → về trang đầu.
      if (_currentPage >= loaded.length) {
        _currentPage = 0;
        if (_pageController.hasClients) _pageController.jumpToPage(0);
      }
    });
    _restartAutoScroll();
  }

  void _restartAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_banners.length <= 1) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_pageController.hasClients || _banners.isEmpty) return;
      _currentPage = (_currentPage + 1) % _banners.length;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Widget _frame({required Widget child, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: _height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _frame(
        color: AppColors.soft,
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.brand,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_banners.isEmpty) {
      // Không có banner đang hiện (hoặc lỗi tải): ảnh tĩnh dự phòng.
      return _frame(
        child: Image.asset('assets/images/banner.jpg', fit: BoxFit.cover),
      );
    }

    return SizedBox(
      height: 184,
      width: double.infinity,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _banners.length,
        onPageChanged: (index) => _currentPage = index,
        itemBuilder: (context, index) {
          final banner = _banners[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppColors.cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: CachedNetworkImage(
                imageUrl: banner.bannerUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: AppColors.soft,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                    color: AppColors.brand,
                    strokeWidth: 2,
                  ),
                ),
                errorWidget: (_, _, _) => Image.asset(
                  'assets/images/banner.jpg',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String eyebrow;
  final String title;
  final List<Product> products;

  const _CategorySection({
    required this.eyebrow,
    required this.title,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warmLabel,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    // Khách chuyển tab Thực đơn bằng thanh dưới của CustomerShell.
                    if (!context.select<SessionProvider, bool>(
                        (s) => s.isCustomer))
                      GestureDetector(
                        onTap: () =>
                            Navigator.pushReplacementNamed(context, '/product'),
                        child: const Text(
                          'Xem tất cả',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final product = products[index];
                return _ProductItemCard(product: product);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductItemCard extends StatelessWidget {
  final Product product;

  const _ProductItemCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final soldOut = !product.isAvailable;
    // Chỉ NV/admin đánh dấu hết hàng; khách và NV/admin đều thêm vào giỏ
    // (giỏ online / giỏ tại quầy); shipper chỉ xem.
    final canSell =
        context.select<SessionProvider, bool>((s) => !s.isCustomer && !s.isShipper);
    final canAdd = context.select<SessionProvider, bool>((s) => !s.isShipper);
    void openDetail() =>
        Navigator.pushNamed(context, '/product_detail', arguments: product.id);
    return Opacity(
      opacity: soldOut ? 0.55 : 1,
      child: Container(
      width: 158,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: openDetail,
          // Nhấn giữ → đánh dấu hết hàng / bán lại (L10).
          onLongPress:
              canSell ? () => showAvailabilitySheet(context, product) : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 110,
                    child: CachedNetworkImage(
                      imageUrl: product.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: AppColors.soft,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.brand,
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: AppColors.soft,
                        alignment: Alignment.center,
                        child: const Icon(Icons.coffee, color: AppColors.brand),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  product.priceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: Material(
                    color: soldOut ? AppColors.dangerSoft : AppColors.soft,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      // "+" mở bảng chọn size (Q11), không thêm thẳng.
                      // Khách: tạm chỉ xem chi tiết (đặt online ở bước 5).
                      onTap: soldOut
                          ? null
                          : canAdd
                              ? () => showAddToCartSheet(context, product)
                              : openDetail,
                      child: Center(
                        child: Text(
                          soldOut ? 'Hết hàng' : (canAdd ? '+ Thêm' : 'Xem món'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                soldOut ? AppColors.danger : AppColors.brand,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
