<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Confirmed against src/services/notificationService.ts: notifications are
 * USER-scoped, not booking-scoped (the web app's realtime subscription is
 * keyed by uid, filtered client-side per page). Real table: `notifications`
 * — id, user_id, booking_id (nullable), notification_type, title, message,
 * action_url (nullable), is_read, created_at, read_at (nullable),
 * expires_at (nullable).
 *
 * No RPC is involved on the real side (plain supabase-js .select()/.update()
 * under RLS) — reads/writes here go through Laravel's own DB connection
 * with a manual ownership check, matching the rest of this codebase's
 * pattern (see BookingController).
 *
 * NOT ported: Postgres realtime push. Flutter should poll this endpoint
 * (the real web app itself falls back to a 30s poll + focus/visibility
 * refresh alongside its realtime channel — see subscribeToUserNotifications
 * in notificationService.ts) unless/until a push mechanism is wired up.
 */
class NotificationController extends Controller
{
    /** GET /notifications */
    public function index(Request $request): JsonResponse
    {
        $userId = $request->attributes->get('supabase_user_id');
        if (blank($userId)) {
            return response()->json(['error' => 'You need to be signed in to view notifications.'], 401);
        }

        $notifications = DB::table('notifications')
            ->where('user_id', $userId)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn ($row) => $this->mapNotification($row))
            ->values();

        return response()->json(['notifications' => $notifications]);
    }

    /** POST /notifications/{id}/read */
    public function markRead(Request $request, string $id): JsonResponse
    {
        $userId = $request->attributes->get('supabase_user_id');
        if (blank($userId)) {
            return response()->json(['error' => 'You need to be signed in to update notifications.'], 401);
        }

        $updated = DB::table('notifications')
            ->where('id', $id)
            ->where('user_id', $userId)
            ->update([
                'is_read' => true,
                'read_at' => now(),
            ]);

        if (!$updated) {
            return response()->json(['error' => 'Notification not found.'], 404);
        }

        $row = DB::table('notifications')->where('id', $id)->first();

        return response()->json(['notification' => $this->mapNotification($row)]);
    }

    private function mapNotification(object $row): array
    {
        return [
            'id' => $row->id,
            'userId' => $row->user_id,
            'bookingId' => $row->booking_id,
            'type' => $row->notification_type,
            'title' => $row->title,
            'message' => $row->message,
            'actionUrl' => $row->action_url,
            'isRead' => (bool) $row->is_read,
            'createdAt' => \Carbon\Carbon::parse($row->created_at)->toIso8601String(),
            'readAt' => $row->read_at ? \Carbon\Carbon::parse($row->read_at)->toIso8601String() : null,
            'expiresAt' => $row->expires_at ? \Carbon\Carbon::parse($row->expires_at)->toIso8601String() : null,
        ];
    }
}