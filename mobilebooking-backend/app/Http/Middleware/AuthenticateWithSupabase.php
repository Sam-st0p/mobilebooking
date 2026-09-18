<?php

namespace App\Http\Middleware;

use Closure;
use Exception;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Illuminate\Http\Request;

class AuthenticateWithSupabase
{
    public function handle(Request $request, Closure $next)
    {
        $token = $request->bearerToken();

        if (!$token) {
            return response()->json(['error' => 'Unauthorized: Missing Bearer Token'], 401);
        }

        try {
            $jwtSecret = config('supabase.jwt_secret');
            $decoded = JWT::decode($token, new Key($jwtSecret, 'HS256'));

            // Attach decoded Supabase user payload to the request
            $request->merge(['supabase_user' => $decoded]);

        } catch (Exception $e) {
            return response()->json(['error' => 'Unauthorized: Invalid Token', 'details' => $e->getMessage()], 401);
        }

        return $next($request);
    }
}
