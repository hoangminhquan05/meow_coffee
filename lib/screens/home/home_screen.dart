import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/banner_model.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bottom_nav_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _products = [];
  bool _isLoadingProducts = true;

  static const List<String> _categories = [
    'Trà Hoa Quả',
    'Trà Sữa',
    'Sữa',
    'Sữa Chua',
  ];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('sanPham').get();
      if (!mounted) return;
      setState(() {
        _products = snapshot.docs
            .map((doc) => Product.fromMap(doc.data(), docId: doc.id))
            .toList();
        _isLoadingProducts = false;
      });
    } catch (e) {
      debugPrint('HomeScreen._loadProducts error: $e');
      if (mounted) {
        setState(() => _isLoadingProducts = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BottomNavBar(currentIndex: 0),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProducts,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _MeowCoffeeTitle(),
                const _BannerSection(),
                if (_isLoadingProducts)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No products available',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                else ...[
                  _CategorySection(
                    categoryName: 'Sản phẩm bán chạy',
                    products: _products,
                  ),
                  for (final category in _categories)
                    _CategorySection(
                      categoryName: category,
                      products: _products
                          .where((p) => p.category == category)
                          .toList(),
                    ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MeowCoffeeTitle extends StatefulWidget {
  const _MeowCoffeeTitle();

  @override
  State<_MeowCoffeeTitle> createState() => _MeowCoffeeTitleState();
}

class _MeowCoffeeTitleState extends State<_MeowCoffeeTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Meow Coffee ☕',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.coffeeBrown,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerSection extends StatefulWidget {
  const _BannerSection();

  @override
  State<_BannerSection> createState() => _BannerSectionState();
}

class _BannerSectionState extends State<_BannerSection> {
  final PageController _pageController = PageController(viewportFraction: 0.92);
  List<BannerModel> _banners = [];
  Timer? _autoScrollTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadBanners();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadBanners() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('banner').get();
      if (!mounted) return;
      final loaded = snapshot.docs
          .map((doc) => BannerModel.fromMap(doc.data(), docId: doc.id))
          .toList();
      setState(() => _banners = loaded);

      if (loaded.length > 1) {
        _autoScrollTimer?.cancel();
        _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          if (!mounted || !_pageController.hasClients) return;
          _currentPage = (_currentPage + 1) % _banners.length;
          _pageController.animateToPage(
            _currentPage,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        });
      }
    } catch (e) {
      debugPrint('_BannerSection._loadBanners error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _banners.isEmpty
            ? Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Đang tải banner...',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : PageView.builder(
                controller: _pageController,
                itemCount: _banners.length,
                onPageChanged: (index) => _currentPage = index,
                itemBuilder: (context, index) {
                  final banner = _banners[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: banner.bannerUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(),
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
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String categoryName;
  final List<Product> products;

  const _CategorySection({
    required this.categoryName,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            categoryName,
            style: const TextStyle(
              fontSize: 20,
              color: AppColors.deepPurple,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 175,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return _ProductItemCard(product: products[index]);
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
    return SizedBox(
      width: 140,
      height: 170,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pushNamed(
              context,
              '/product_detail',
              arguments: product.id,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 100,
                    child: CachedNetworkImage(
                      imageUrl: product.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.coffee, color: Colors.brown),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  product.formattedPrice,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
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
