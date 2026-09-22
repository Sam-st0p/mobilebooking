// lib/screens/catalog/product_detail_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import '../../services/favorites_service.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/availability_badge.dart';

/// Port of `app/catalog/[id]/page.tsx` + `ProductDetailsClient.tsx`.
/// Similar-products, quick-estimate, and rental-duration-selector are
/// left as phase-2 additions — the core product view (gallery, specs,
/// price, reviews, reserve CTA) is fully wired here.
class ProductDetailScreen extends StatefulWidget {
  final String idOrSlug;
  const ProductDetailScreen({super.key, required this.idOrSlug});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<Product?> _productFuture;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _productFuture = ProductService.getProductById(widget.idOrSlug);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Product?>(
        future: _productFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final product = snapshot.data;
          if (product == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('This product could not be found.')),
            );
          }

          final images = product.images.isNotEmpty
              ? product.images.map((i) => i.url).toList()
              : [product.image];
          final fullyBooked = product.availableUnits <= 0;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 320,
                backgroundColor: AppColors.white,
                foregroundColor: AppColors.textPrimary,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => _imageIndex = i),
                        itemBuilder: (context, i) => CachedNetworkImage(
                          imageUrl: images[i],
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(color: AppColors.lightGray),
                        ),
                      ),
                      if (images.length > 1)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(images.length, (i) {
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == _imageIndex ? AppColors.white : AppColors.white.withValues(alpha: 0.5),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  StreamBuilder<List<String>>(
                    stream: FavoritesService.favoritesStream,
                    initialData: FavoritesService.current,
                    builder: (context, favSnapshot) {
                      final isFav = (favSnapshot.data ?? []).contains(product.id);
                      return IconButton(
                        icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                            color: AppColors.primary),
                        onPressed: () => FavoritesService.toggleFavorite(product.id),
                      );
                    },
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      [product.brand, product.effectiveCategory].where((s) => s != null && s.isNotEmpty).join(' · '),
                      style: const TextStyle(color: AppColors.charcoal, fontSize: 12, letterSpacing: 0.4),
                    ),
                    const SizedBox(height: 4),
                    Text(product.name,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('${product.rating.toStringAsFixed(1)} ★',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text('(${product.reviewCount} reviews)',
                            style: const TextStyle(color: AppColors.charcoal)),
                      ],
                    ),
                    if (product.description != null) ...[
                      const SizedBox(height: 16),
                      Text(product.description!,
                          style: const TextStyle(color: AppColors.charcoal, height: 1.5)),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _infoCard(
                            'Daily Rate',
                            '${product.currency}${product.pricePerDay.toStringAsFixed(0)}/day',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _infoCard(
                            'Refundable Deposit',
                            '${product.currency}${product.refundableDeposit.toStringAsFixed(0)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AvailabilityBadge(
                      totalUnits: product.totalUnits,
                      availableUnits: product.availableUnits,
                    ),
                    if (product.included.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text("What's Included",
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 8),
                      ...product.included.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.check, size: 16, color: AppColors.statusGreen),
                                const SizedBox(width: 8),
                                Expanded(child: Text(item)),
                              ],
                            ),
                          )),
                    ],
                    if (product.specifications.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text('Specifications',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 8),
                      ...product.specifications.entries
                          .where((e) => e.key != 'included')
                          .map((e) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(e.key, style: const TextStyle(color: AppColors.charcoal)),
                                    ),
                                    Expanded(
                                      child: Text(e.value,
                                          style: const TextStyle(fontWeight: FontWeight.w500)),
                                    ),
                                  ],
                                ),
                              )),
                    ],
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: FutureBuilder<Product?>(
        future: _productFuture,
        builder: (context, snapshot) {
          final product = snapshot.data;
          if (product == null) return const SizedBox.shrink();
          final fullyBooked = product.availableUnits <= 0;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: fullyBooked
                    ? null
                    : () => context.push('/catalog/${product.id}/reserve'),
                child: Text(fullyBooked ? 'Fully Booked' : 'Reserve Now'),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blush.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.charcoal)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ],
      ),
    );
  }
}