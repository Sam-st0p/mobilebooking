// lib/services/producr_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'supabase_client.dart';

/// Port of `src/services/productService.ts`. Same table joins, same RPCs
/// (`get_product_availability`, `get_product_reviews`), same public
/// storage bucket ("product-images") — only the language changed.
class ProductService {
  static const _productSelect = '''
    *,
    product_images(*),
    categories(name),
    brands(name)
  ''';

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// Customers can't SELECT inventory_units/unit_reservations directly
  /// (admin-only RLS), so live unit counts come from the
  /// get_product_availability() RPC, scoped to "today" as a point-in-time
  /// snapshot for catalog display — same as the web app.
  static Future<({int totalUnits, int availableUnits})> _fetchAvailabilitySnapshot(
    String productId,
  ) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final data = await supabase.rpc('get_product_availability', params: {
      'p_product_id': productId,
      'p_start_date': today,
      'p_end_date': today,
    });
    final rows = (data as List?) ?? [];
    if (rows.isEmpty) return (totalUnits: 0, availableUnits: 0);
    final row = rows.first as Map<String, dynamic>;
    return (
      totalUnits: (row['total_units'] as num?)?.toInt() ?? 0,
      availableUnits: (row['available_units'] as num?)?.toInt() ?? 0,
    );
  }

  /// Reviews are keyed off booking_items, fetched via get_product_reviews()
  /// (already filtered to approved), same as the web app.
  static Future<List<ProductReview>> _fetchApprovedReviews(String productId) async {
    final data = await supabase.rpc('get_product_reviews', params: {
      'p_product_id': productId,
      'p_limit': 100,
      'p_offset': 0,
    });
    final rows = (data as List?) ?? [];
    return rows.map((r) {
      final row = r as Map<String, dynamic>;
      return ProductReview(
        id: row['review_id'] as String,
        author: 'Verified renter',
        rating: (row['rating'] as num).toDouble(),
        comment: (row['comment'] as String?) ?? '',
        date: row['created_at'] as String,
      );
    }).toList();
  }

  static Future<Product> _mapProduct(Map<String, dynamic> row) async {
    final productId = row['id'] as String;
    final results = await Future.wait([
      _fetchAvailabilitySnapshot(productId),
      _fetchApprovedReviews(productId),
    ]);
    final availability = results[0] as ({int totalUnits, int availableUnits});
    final reviews = results[1] as List<ProductReview>;

    final rawImages = (row['product_images'] as List?) ?? [];
    final images = rawImages.map((img) {
      final m = img as Map<String, dynamic>;
      final storagePath = m['storage_path'] as String;
      final publicUrl =
          supabase.storage.from('product-images').getPublicUrl(storagePath);
      return ProductImage(
        id: m['id'] as String,
        storagePath: storagePath,
        url: publicUrl,
        altText: m['alt_text'] as String?,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        isPrimary: m['is_primary'] as bool? ?? false,
      );
    }).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final rating = reviews.isEmpty
        ? 0.0
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;

    final specifications = Map<String, String>.from(
      (row['specifications'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
    );

    final categories = row['categories'] as Map<String, dynamic>?;
    final brands = row['brands'] as Map<String, dynamic>?;
    final status = productStatusFromString(row['status'] as String? ?? 'draft');
    final availableUnits = availability.availableUnits;
    final totalUnits = availability.totalUnits;

    return Product(
      id: productId,
      slug: row['slug'] as String,
      name: row['name'] as String,
      brand: brands?['name'] as String?,
      category: categories?['name'] as String? ?? '',
      shortDescription: row['short_description'] as String?,
      description: row['description'] as String?,
      dailyRate: (row['daily_rate'] as num).toDouble(),
      refundableDeposit: (row['refundable_deposit'] as num?)?.toDouble() ?? 0,
      status: status,
      isFeatured: row['is_featured'] as bool? ?? false,
      specifications: specifications,
      images: images,
      totalUnits: totalUnits,
      availableUnits: availableUnits,
      reservedUnits: (totalUnits - availableUnits).clamp(0, totalUnits),
      rentedUnits: 0,
      maintenanceUnits: 0,
      rating: rating,
      reviewCount: reviews.length,
      reviews: reviews,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
    );
  }

  static Future<List<Product>> getActiveProducts() async {
    final data = await supabase
        .from('products')
        .select(_productSelect)
        .eq('status', 'active')
        .order('created_at', ascending: false);

    final rows = (data as List).cast<Map<String, dynamic>>();
    return Future.wait(rows.map(_mapProduct));
  }

  /// Accepts either the product UUID or its slug (catalog links use slugs).
  static Future<Product?> getProductById(String idOrSlug) async {
    final isUuid = _uuidPattern.hasMatch(idOrSlug);
    try {
      final data = await supabase
          .from('products')
          .select(_productSelect)
          .eq(isUuid ? 'id' : 'slug', idOrSlug)
          .maybeSingle();
      if (data == null) return null;
      return await _mapProduct(data);
    } on PostgrestException {
      return null;
    }
  }
}
