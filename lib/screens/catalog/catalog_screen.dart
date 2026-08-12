// lib/screens/catalog/catalog_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import '../../services/favorites_service.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/catalog_product_card.dart';

enum _SortOption { featured, priceAsc, priceDesc, nameAsc }

/// Port of `app/catalog/page.tsx` + `app/catalog/CatalogView.tsx`.
/// Live inventory subscriptions (useInventory.ts) are a good phase-2 add —
/// for now this loads the same availability snapshot productService uses.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late Future<List<Product>> _productsFuture;
  String _search = '';
  String _category = 'All';
  _SortOption _sort = _SortOption.featured;
  bool _availableOnly = false;

  static const _categories = ['All', 'Phones', 'Cameras'];

  @override
  void initState() {
    super.initState();
    _productsFuture = ProductService.getActiveProducts();
  }

  List<Product> _applyFilters(List<Product> products) {
    final query = _search.trim().toLowerCase();
    var filtered = products.where((p) {
      final matchesCategory = _category == 'All' || p.category == _category;
      final matchesSearch = query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          (p.brand ?? '').toLowerCase().contains(query);
      final matchesAvailability = !_availableOnly || p.availableUnits > 0;
      return matchesCategory && matchesSearch && matchesAvailability;
    }).toList();

    switch (_sort) {
      case _SortOption.priceAsc:
        filtered.sort((a, b) => a.pricePerDay.compareTo(b.pricePerDay));
        break;
      case _SortOption.priceDesc:
        filtered.sort((a, b) => b.pricePerDay.compareTo(a.pricePerDay));
        break;
      case _SortOption.nameAsc:
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case _SortOption.featured:
        break;
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browse Our Gear')),
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load products: ${snapshot.error}'));
          }

          final filtered = _applyFilters(snapshot.data ?? []);

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _productsFuture = ProductService.getActiveProducts());
              await _productsFuture;
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildFilters(filtered.length)),
                if (filtered.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('No products match your filters.')),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent: 400,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = filtered[index];
                          return StreamBuilder<List<String>>(
                            stream: FavoritesService.favoritesStream,
                            initialData: FavoritesService.current,
                            builder: (context, favSnapshot) {
                              final isFav = (favSnapshot.data ?? []).contains(product.id);
                              return CatalogProductCard(
                                product: product,
                                isFavorite: isFav,
                                onToggleFavorite: () =>
                                    FavoritesService.toggleFavorite(product.id),
                                onViewDetails: () => context.push('/catalog/${product.id}'),
                                onReserve: () =>
                                    context.push('/catalog/${product.id}/reserve'),
                              );
                            },
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilters(int resultCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by name or brand',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _categories[index];
                final active = _category == item;
                return ChoiceChip(
                  label: Text(item == 'All' ? 'All Products' : item),
                  selected: active,
                  onSelected: (_) => setState(() => _category = item),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: active ? AppColors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.border),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<_SortOption>(
                  initialValue: _sort,
                  decoration: const InputDecoration(isDense: true),
                  items: const [
                    DropdownMenuItem(value: _SortOption.featured, child: Text('Featured')),
                    DropdownMenuItem(value: _SortOption.priceAsc, child: Text('Price: Low to High')),
                    DropdownMenuItem(value: _SortOption.priceDesc, child: Text('Price: High to Low')),
                    DropdownMenuItem(value: _SortOption.nameAsc, child: Text('Name: A to Z')),
                  ],
                  onChanged: (value) => setState(() => _sort = value ?? _SortOption.featured),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Available only'),
                selected: _availableOnly,
                onSelected: (value) => setState(() => _availableOnly = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('$resultCount result${resultCount == 1 ? '' : 's'}',
              style: const TextStyle(color: AppColors.charcoal, fontSize: 12)),
        ],
      ),
    );
  }
}