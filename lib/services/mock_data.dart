// lib/services/mock_data.dart

import '../models/product.dart';

/// Sample data so the app is fully browsable with zero setup — no backend,
/// no Supabase, nothing to configure. Used automatically by ProductService
/// whenever API_BASE_URL isn't set (see ApiConfig.isConfigured). Swap this
/// out once you're ready to point at the real backend.
class MockData {
  static final List<Product> products = [
    Product(
      id: 'demo-1',
      slug: 'iphone-15-pro',
      name: 'iPhone 15 Pro',
      brand: 'Apple',
      category: 'Phones',
      shortDescription: 'Titanium design, A17 Pro chip, pro camera system.',
      description:
          'The iPhone 15 Pro comes with everything you need for a shoot-ready '
          'kit: three rear cameras, a bright 6.1" display, and all-day battery.',
      dailyRate: 450,
      refundableDeposit: 5000,
      status: ProductStatus.active,
      isFeatured: true,
      specifications: const {
        'Storage': '256GB',
        'Color': 'Natural Titanium',
        'included': 'Charger, Cable, Case',
      },
      images: [
        const ProductImage(
          id: 'img-1',
          storagePath: '',
          url: 'https://picsum.photos/seed/iphone15pro/600/600',
          sortOrder: 0,
          isPrimary: true,
        ),
      ],
      totalUnits: 4,
      availableUnits: 3,
      rating: 4.9,
      reviewCount: 27,
      reviews: const [],
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    ),
    Product(
      id: 'demo-2',
      slug: 'sony-a7-iv',
      name: 'Sony A7 IV',
      brand: 'Sony',
      category: 'Cameras',
      shortDescription: 'Full-frame mirrorless, 33MP, 4K60 video.',
      description:
          'A hybrid full-frame mirrorless camera built for both photo and '
          'video work, with fast autofocus and excellent low-light performance.',
      dailyRate: 1200,
      refundableDeposit: 15000,
      status: ProductStatus.active,
      isFeatured: true,
      specifications: const {
        'Sensor': '33MP Full-Frame',
        'Video': '4K60',
        'included': 'Battery, Charger, 32GB SD Card, Strap',
      },
      images: [
        const ProductImage(
          id: 'img-2',
          storagePath: '',
          url: 'https://picsum.photos/seed/sonya7iv/600/600',
          sortOrder: 0,
          isPrimary: true,
        ),
      ],
      totalUnits: 2,
      availableUnits: 1,
      rating: 4.8,
      reviewCount: 19,
      reviews: const [],
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    ),
    Product(
      id: 'demo-3',
      slug: 'iphone-14',
      name: 'iPhone 14',
      brand: 'Apple',
      category: 'Phones',
      shortDescription: 'Great everyday shooter, dual camera system.',
      description: 'A dependable, budget-friendly rental with a great camera and long battery life.',
      dailyRate: 300,
      refundableDeposit: 3500,
      status: ProductStatus.active,
      isFeatured: false,
      specifications: const {'Storage': '128GB', 'Color': 'Midnight'},
      images: [
        const ProductImage(
          id: 'img-3',
          storagePath: '',
          url: 'https://picsum.photos/seed/iphone14/600/600',
          sortOrder: 0,
          isPrimary: true,
        ),
      ],
      totalUnits: 5,
      availableUnits: 0,
      rating: 4.6,
      reviewCount: 41,
      reviews: const [],
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    ),
    Product(
      id: 'demo-4',
      slug: 'canon-eos-r6',
      name: 'Canon EOS R6 Mark II',
      brand: 'Canon',
      category: 'Cameras',
      shortDescription: 'Fast, versatile full-frame mirrorless.',
      description:
          'A well-rounded full-frame body with excellent autofocus and burst '
          'shooting, popular for events and portrait work.',
      dailyRate: 1100,
      refundableDeposit: 14000,
      status: ProductStatus.active,
      isFeatured: false,
      specifications: const {'Sensor': '24MP Full-Frame', 'included': 'Battery, Charger, 64GB SD Card'},
      images: [
        const ProductImage(
          id: 'img-4',
          storagePath: '',
          url: 'https://picsum.photos/seed/canonr6/600/600',
          sortOrder: 0,
          isPrimary: true,
        ),
      ],
      totalUnits: 3,
      availableUnits: 2,
      rating: 4.7,
      reviewCount: 15,
      reviews: const [],
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    ),
  ];

  static Future<List<Product>> getActiveProducts() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return products;
  }

  static Future<Product?> getProductById(String idOrSlug) async {
    await Future.delayed(const Duration(milliseconds: 300));
    for (final p in products) {
      if (p.id == idOrSlug || p.slug == idOrSlug) return p;
    }
    return null;
  }
}
