// lib/widgets/catalog_product_card.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/availability.dart';
import 'availability_badge.dart';

/// Port of `components/catalog-product-card/CatalogProductCard.tsx`.
class CatalogProductCard extends StatelessWidget {
  final Product product;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onViewDetails;
  final VoidCallback onReserve;
  final String ctaLabel;

  const CatalogProductCard({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onViewDetails,
    required this.onReserve,
    this.ctaLabel = 'Reserve Now',
  });

  @override
  Widget build(BuildContext context) {
    final fullyBooked = isFullyBooked(product.availableUnits);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: onViewDetails,
                child: AspectRatio(
                  aspectRatio: 1.1,
                  child: product.image.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: product.image,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(
                            color: AppColors.lightGray,
                            child: const Icon(Icons.camera_alt_outlined, color: AppColors.charcoal),
                          ),
                        )
                      : Container(
                          color: AppColors.lightGray,
                          child: const Icon(Icons.camera_alt_outlined, color: AppColors.charcoal),
                        ),
                ),
              ),
              if (product.badge != null)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      product.badge!,
                      style: const TextStyle(color: AppColors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: AppColors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onToggleFavorite,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                        color: isFavorite ? AppColors.primary : AppColors.charcoal,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.category,
                  style: const TextStyle(fontSize: 11, color: AppColors.charcoal, letterSpacing: 0.4),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: onViewDetails,
                  child: Text(
                    product.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (product.brand != null)
                  Text(product.brand!, style: const TextStyle(fontSize: 12, color: AppColors.charcoal)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '₱${product.pricePerDay.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                    const Text('/day', style: TextStyle(fontSize: 12, color: AppColors.charcoal)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('${product.rating.toStringAsFixed(1)} ★',
                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                    const SizedBox(width: 4),
                    Text('(${product.reviewCount})',
                        style: const TextStyle(fontSize: 12, color: AppColors.charcoal)),
                  ],
                ),
                const SizedBox(height: 8),
                AvailabilityBadge(
                  totalUnits: product.totalUnits,
                  availableUnits: product.availableUnits,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onViewDetails,
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                        child: const Text('View Details', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: fullyBooked ? null : onReserve,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                        child: Text(
                          fullyBooked ? 'Fully Booked' : ctaLabel,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
