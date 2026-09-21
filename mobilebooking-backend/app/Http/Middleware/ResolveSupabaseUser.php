<?php

namespace App\Http\Middleware;

use App\Services\Supabase\SupabaseRpcException;
use App\Services\Supabase\SupabaseRpcService;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * Resolves WHO is calling, from the Supabase bearer token the Flutter app
 * sends, and exposes it to controllers as request attributes:
 *
 *   supabase_access_token  the raw bearer token
 *   supabase_user_id       the Supabase auth user's id (uuid)
 *   supabase_user          the full /auth/v1/user payload
 *
 * BookingController::index()/show() and NotificationController read
 * `supabase_user_id`, but nothing in the app ever set it, so those routes
 * answered 401 "You need to be signed in..." even for signed-in users.
 *
 * This middleware NEVER rejects a request itself. If the token is missing,
 * invalid or expired it simply leaves the attributes unset, and each
 * controller keeps returning its own 401 — so public routes are unaffected.
 */
class ResolveSupabaseUser
{
    public function handle(Request $request, Closure $next): Response
    {
        $token = $request->bearerToken();

        if (filled($token) && $this->routeNeedsUser($request)) {
            try {
                $user = app(SupabaseRpcService::class)->getCurrentUser($token);

                if (filled($user['id'] ?? null)) {
                    $request->attributes->set('supabase_access_token', $token);
                    $request->attributes->set('supabase_user_id', $user['id']);
                    $request->attributes->set('supabase_user', $user);
                }
            } catch (SupabaseRpcException $e) {
                // Expired/invalid token (or Supabase unreachable). Leave the
                // attributes unset; the controller will answer 401.
                Log::info('ResolveSupabaseUser: could not resolve user', ['reason' => $e->getMessage()]);
            }
        }

        return $next($request);
    }

    /** Public routes (catalog/availability and the auth endpoints) never need it. */
    private function routeNeedsUser(Request $request): bool
    {
        return !$request->is('*catalog*', '*/auth/*');
    }
}