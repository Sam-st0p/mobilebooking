// lib/widgets/catalog_product_card.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/availability.dart';

/// Card layout inspired by the reference UI kit: rounded image with a
/// floating rating pill, a location/category line, bold title, and a
/// price + single dark "Book Now" pill button — using our own blush/rose
/// palette instead of the reference's teal.
class CatalogProductCard extends StatelessWidget {
  final Product product;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onViewDetails;
  final VoidCallback onReserve;

  const CatalogProductCard({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onViewDetails,
    required this.onReserve,
  });

  @override
  Widget build(BuildContext context) {
    final fullyBooked = isFullyBooked(product.availableUnits);

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onViewDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Image with floating rating + favorite pills ----
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1,
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
                if (product.badge != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _pill(
                      color: AppColors.primary,
                      child: Text(
                        product.badge!,
                        style: const TextStyle(color: AppColors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Row(
                    children: [
                      _pill(
                        color: AppColors.textPrimary.withOpacity(0.82),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFC94D)),
                            const SizedBox(width: 3),
                            Text(
                              product.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: AppColors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // A real tap target (44x44, Android's/iOS's recommended minimum) —
                      // the old 27x27 pill sitting right next to the rating pill was easy
                      // to miss on a real phone, which is why favoriting felt "broken".
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggleFavorite,
                        child: Semantics(
                          button: true,
                          label: isFavorite ? 'Remove from favorites' : 'Add to favorites',
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: _pill(
                                color: AppColors.white,
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  size: 15,
                                  color: isFavorite ? AppColors.primary : AppColors.charcoal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // ---- Info ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 12, color: AppColors.dustyRose),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          product.effectiveCategory,
                          style: const TextStyle(fontSize: 11, color: AppColors.charcoal),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    product.name,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: RichText(
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '₱${product.pricePerDay.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const TextSpan(
                                text: ' /day',
                                style: TextStyle(color: AppColors.charcoal, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 32,
                        child: ElevatedButton(
                          onPressed: fullyBooked ? null : onReserve,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          child: Text(fullyBooked ? 'Full' : 'Book Now'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill({required Color color, required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}