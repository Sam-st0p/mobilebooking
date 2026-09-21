<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

/**
 * requirementsStatus and agreementStatus are NOT columns you can trust on
 * `bookings` anymore -- confirmed against src/services/bookingService.ts
 * and src/types/booking.ts on the real (Next.js) side. They must be
 * derived from booking_requirements / booking_agreements child rows every
 * time a booking is read. bookings.requirements_status /
 * bookings.agreement_status still exist as columns (leftover from before
 * the 2026-08-04 schema normalization) but the real submit flow never
 * writes to them, so reading them directly returns stale/default values,
 * not the truth. This mirrors deriveRequirementsStatus() +
 * the agreementStatus one-liner from bookingService.ts exactly.
 */
class BookingStatusDeriver
{
    /** @return string one of: not_submitted, pending_review, approved, rejected */
    public static function requirementsStatus(string $bookingId): string
    {
        $statuses = DB::table('booking_requirements')
            ->where('booking_id', $bookingId)
            ->pluck('status');

        if ($statuses->isEmpty()) {
            return 'not_submitted';
        }
        if ($statuses->contains('rejected')) {
            return 'rejected';
        }
        if ($statuses->contains('pending_review')) {
            return 'pending_review';
        }
        if ($statuses->every(fn ($s) => in_array($s, ['approved', 'waived'], true))) {
            return 'approved';
        }

        return 'not_submitted';
    }

    /** @return string an agreement_status enum value, or 'not_created' */
    public static function agreementStatus(string $bookingId): string
    {
        return DB::table('booking_agreements')
            ->where('booking_id', $bookingId)
            ->value('status') ?? 'not_created';
    }
}