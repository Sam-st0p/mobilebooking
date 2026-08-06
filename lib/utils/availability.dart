// lib/utils/availability.dart

import 'dart:math' as math;

/// Direct port of `lib/availability.ts`. Keep in sync with the web app.
enum AvailabilityLevel { available, limited, full }

class UnitCounts {
  final int totalUnits;
  final int availableUnits;
  final int reservedUnits;
  final int rentedUnits;

  const UnitCounts({
    required this.totalUnits,
    required this.availableUnits,
    required this.reservedUnits,
    required this.rentedUnits,
  });
}

AvailabilityLevel getAvailabilityLevel(int availableUnits, int totalUnits) {
  if (availableUnits <= 0) return AvailabilityLevel.full;
  final limitedThreshold = math.max(1, (totalUnits * 0.3).ceil());
  if (availableUnits <= limitedThreshold) return AvailabilityLevel.limited;
  return AvailabilityLevel.available;
}

String getAvailabilityLabel(AvailabilityLevel level) {
  switch (level) {
    case AvailabilityLevel.available:
      return 'Available';
    case AvailabilityLevel.limited:
      return 'Limited Units';
    case AvailabilityLevel.full:
      return 'Fully Booked';
  }
}

bool isFullyBooked(int availableUnits) => availableUnits <= 0;

String getUnitsAvailableText(int availableUnits) {
  return '$availableUnits unit${availableUnits == 1 ? '' : 's'} available';
}

String getUnitsInUseText(int totalUnits, int availableUnits) {
  final inUse = totalUnits - availableUnits;
  return '$inUse of $totalUnits units currently rented or reserved';
}

String getFullyBookedMessage(int totalUnits) {
  return 'All $totalUnits units are currently reserved.\n'
      'Thank you for your interest. Please check back later for updated availability.';
}
