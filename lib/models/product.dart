// lib/models/product.dart

/// Port of `types/product.ts`. Field names match 1:1 so the mapping logic
/// ported from `src/services/productService.ts` (see ProductService) reads
/// the same way as the TypeScript original.
enum ProductStatus { draft, active, inactive, archived }

ProductStatus productStatusFromString(String value) {
  return ProductStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => ProductStatus.draft,
  );
}

class ProductReview {
  final String id;
  final String author;
  final double rating;
  final String comment;
  final String date;

  const ProductReview({
    required this.id,
    required this.author,
    required this.rating,
    required this.comment,
    required this.date,
  });
}

class ProductImage {
  final String id;
  final String storagePath;
  final String url;
  final String? altText;
  final int sortOrder;
  final bool isPrimary;

  const ProductImage({
    required this.id,
    required this.storagePath,
    required this.url,
    this.altText,
    required this.sortOrder,
    required this.isPrimary,
  });
}

class Product {
  final String id;
  final String slug;
  final String name;
  final String? brand;
  final String category;
  final String? shortDescription;
  final String? description;
  final double dailyRate;
  final double refundableDeposit;
  final String currency; // always "PHP"
  final ProductStatus status;
  final bool isFeatured;
  final Map<String, String> specifications;
  final List<ProductImage> images;
  final int totalUnits;
  final int availableUnits;
  final int reservedUnits;
  final int rentedUnits;
  final int maintenanceUnits;
  final double rating;
  final int reviewCount;
  final List<ProductReview> reviews;
  final String createdAt;
  final String updatedAt;

  const Product({
    required this.id,
    required this.slug,
    required this.name,
    this.brand,
    required this.category,
    this.shortDescription,
    this.description,
    required this.dailyRate,
    required this.refundableDeposit,
    this.currency = 'PHP',
    required this.status,
    required this.isFeatured,
    required this.specifications,
    required this.images,
    required this.totalUnits,
    required this.availableUnits,
    required this.reservedUnits,
    required this.rentedUnits,
    required this.maintenanceUnits,
    required this.rating,
    required this.reviewCount,
    required this.reviews,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Alias for dailyRate — kept for parity with the TS `pricePerDay` alias.
  double get pricePerDay => dailyRate;

  /// Alias for images[0]?.url.
  String get image => images.isNotEmpty ? images.first.url : '';

  /// Parsed from specifications['included'] (comma-separated), if present.
  List<String> get included {
    final raw = specifications['included'];
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  String? get badge => isFeatured ? 'Featured' : null;

  bool get isActive => status == ProductStatus.active;
}
