// lib/models/product.dart
/// Product model. Shape matches the JSON returned by
/// GET /api/mobile/catalog and /api/mobile/catalog/:id — the backend does
/// all the Supabase joins/RPCs and hands this back ready to use.
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

  factory ProductReview.fromJson(Map<String, dynamic> json) => ProductReview(
        id: json['id'] as String,
        author: json['author'] as String? ?? 'Verified renter',
        rating: (json['rating'] as num).toDouble(),
        comment: json['comment'] as String? ?? '',
        date: json['date'] as String,
      );
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

  factory ProductImage.fromJson(Map<String, dynamic> json) => ProductImage(
        id: json['id'] as String,
        storagePath: json['storagePath'] as String? ?? '',
        url: json['url'] as String,
        altText: json['altText'] as String?,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        isPrimary: json['isPrimary'] as bool? ?? false,
      );
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
    required this.rating,
    required this.reviewCount,
    required this.reviews,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      category: json['category'] as String? ?? '',
      shortDescription: json['shortDescription'] as String?,
      description: json['description'] as String?,
      dailyRate: (json['dailyRate'] as num).toDouble(),
      refundableDeposit: (json['refundableDeposit'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'PHP',
      status: productStatusFromString(json['status'] as String? ?? 'draft'),
      isFeatured: json['isFeatured'] as bool? ?? false,
      specifications: Map<String, String>.from(
        (json['specifications'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
      ),
      images: ((json['images'] as List?) ?? [])
          .map((i) => ProductImage.fromJson(i as Map<String, dynamic>))
          .toList(),
      totalUnits: (json['totalUnits'] as num?)?.toInt() ?? 0,
      availableUnits: (json['availableUnits'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      reviews: ((json['reviews'] as List?) ?? [])
          .map((r) => ProductReview.fromJson(r as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  double get pricePerDay => dailyRate;

  String get image => images.isNotEmpty ? images.first.url : '';

  List<String> get included {
    final raw = specifications['included'];
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  String? get badge => isFeatured ? 'Featured' : null;

  bool get isActive => status == ProductStatus.active;
}
