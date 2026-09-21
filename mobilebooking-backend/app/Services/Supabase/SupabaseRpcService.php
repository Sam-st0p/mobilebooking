<?php

namespace App\Services\Supabase;

use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Thin wrapper around Supabase's REST surface: PostgREST RPC calls,
 * plain table inserts (also via PostgREST), filtered table reads,
 * Storage uploads/listing, and the Auth /user lookup.
 *
 * Every call here is made AS THE CUSTOMER, using their own Supabase
 * access token — never the service-role key — so that both `auth.uid()`
 * inside Postgres functions and RLS policies on direct table
 * inserts/reads resolve to the real caller. Established for
 * /account/profile and booking creation; extended for the payment-proof
 * upload flow, Step 4's read-only requirements listing, and the combined
 * documents+agreement submission endpoint.
 */
class SupabaseRpcService
{
    // NOTE: these are declared as plain readonly properties, NOT promoted
    // constructor parameters. A promoted `private readonly string $baseUrl`
    // is already initialised the moment the constructor starts, so
    // re-assigning it in the body threw "Cannot modify readonly property"
    // on every instantiation — i.e. on every endpoint that injects this
    // service (bookings, payment submissions, documents, ...).
    private readonly string $baseUrl;
    private readonly string $anonKey;

    public function __construct(string $baseUrl = '', string $anonKey = '')
    {
        $this->baseUrl = $baseUrl !== '' ? $baseUrl : rtrim((string) config('services.supabase.url'), '/');
        $this->anonKey = $anonKey !== '' ? $anonKey : (string) config('services.supabase.anon_key');

        if ($this->baseUrl === '' || $this->anonKey === '') {
            // Fail loudly with an actionable message instead of a cryptic
            // 401/404 from Supabase later. Set both in .env, then run
            // `php artisan config:clear`.
            \Illuminate\Support\Facades\Log::error('Supabase is not configured', [
                'has_url' => $this->baseUrl !== '',
                'has_anon_key' => $this->anonKey !== '',
                'hint' => 'Set SUPABASE_URL and SUPABASE_ANON_KEY in .env',
            ]);
        }
    }

    /**
     * Call a Postgres function exposed via PostgREST's /rpc/ route, for
     * scalar/single-row-returning functions (e.g. RETURNS bookings).
     * Collapses an array response down to its first element — do NOT use
     * this for a function that legitimately returns multiple rows; use
     * callMany() instead, or every row past the first is silently lost.
     *
     * @param string $functionName   e.g. 'create_multi_day_time_based_booking'
     * @param array  $params         must match the Postgres function's
     *                               parameter names exactly (p_product_id, etc.)
     * @param string $userAccessToken the CALLER's Supabase access token —
     *                                required for functions that touch auth.uid()
     *
     * @return array the decoded JSON response body (the returned row)
     *
     * @throws SupabaseRpcException on any non-2xx response, with the
     *         parsed Postgres error code/message attached so the caller
     *         can map it to an HTTP status.
     */
    public function call(string $functionName, array $params, string $userAccessToken): array
    {
        try {
            $response = Http::withHeaders([
                'apikey' => $this->anonKey,
                'Authorization' => "Bearer {$userAccessToken}",
                'Content-Type' => 'application/json',
                // Ask PostgREST to return the single object, not [object]
                'Prefer' => 'return=representation',
            ])
                ->timeout(15)
                ->post("{$this->baseUrl}/rest/v1/rpc/{$functionName}", $params);
        } catch (\Throwable $e) {
            Log::error('Supabase RPC transport error', [
                'function' => $functionName,
                'error' => $e->getMessage(),
            ]);

            throw new SupabaseRpcException(
                message: 'UPSTREAM_UNAVAILABLE',
                pgCode: null,
                httpStatus: 503,
                previous: $e,
            );
        }

        if (! $response->successful()) {
            $body = $response->json() ?? [];

            // PostgREST surfaces `raise exception 'FOO'` as body.message == 'FOO'
            // (and body.code for the Postgres SQLSTATE, e.g. P0001).
            $message = $body['message'] ?? $response->body();
            $pgCode = $body['code'] ?? null;

            Log::warning('Supabase RPC returned an error', [
                'function' => $functionName,
                'status' => $response->status(),
                'pg_code' => $pgCode,
                'message' => $message,
            ]);

            throw new SupabaseRpcException(
                message: $message,
                pgCode: $pgCode,
                httpStatus: $response->status(),
            );
        }

        $decoded = $response->json();

        // PostgREST returns a single JSON object for scalar/row-returning
        // functions when called without `Accept: application/vnd.pgrst.object+json`
        // it can sometimes wrap in an array — normalize defensively.
        if (is_array($decoded) && array_is_list($decoded)) {
            return $decoded[0] ?? [];
        }

        return $decoded ?? [];
    }

    /**
     * Like call(), but for table-returning Postgres functions
     * (get_booking_unit_assignments, etc.) where collapsing to a single
     * row would silently drop every row but the first. call()
     * intentionally does that collapse for scalar/single-row RPCs; this
     * doesn't.
     *
     * @return array list of rows
     * @throws SupabaseRpcException
     */
    public function callMany(string $functionName, array $params, string $userAccessToken): array
    {
        try {
            $response = Http::withHeaders([
                'apikey' => $this->anonKey,
                'Authorization' => "Bearer {$userAccessToken}",
                'Content-Type' => 'application/json',
            ])
                ->timeout(15)
                ->post("{$this->baseUrl}/rest/v1/rpc/{$functionName}", $params);
        } catch (\Throwable $e) {
            Log::error('Supabase RPC transport error', ['function' => $functionName, 'error' => $e->getMessage()]);

            throw new SupabaseRpcException('UPSTREAM_UNAVAILABLE', null, 503, $e);
        }

        if (! $response->successful()) {
            $body = $response->json() ?? [];

            throw new SupabaseRpcException($body['message'] ?? $response->body(), $body['code'] ?? null, $response->status());
        }

        $decoded = $response->json();

        return is_array($decoded) ? $decoded : [];
    }

    /**
     * Insert a row into a plain table via PostgREST. RLS on that table
     * still applies — this does not bypass it, it runs AS the caller.
     *
     * @throws SupabaseRpcException
     */
    public function insert(string $table, array $row, string $userAccessToken): array
    {
        try {
            $response = Http::withHeaders([
                'apikey' => $this->anonKey,
                'Authorization' => "Bearer {$userAccessToken}",
                'Content-Type' => 'application/json',
                'Prefer' => 'return=representation',
            ])
                ->timeout(15)
                ->post("{$this->baseUrl}/rest/v1/{$table}", $row);
        } catch (\Throwable $e) {
            Log::error('Supabase insert transport error', ['table' => $table, 'error' => $e->getMessage()]);

            throw new SupabaseRpcException('UPSTREAM_UNAVAILABLE', null, 503, $e);
        }

        if (! $response->successful()) {
            $body = $response->json() ?? [];
            $message = $body['message'] ?? $response->body();

            Log::warning('Supabase insert failed', [
                'table' => $table,
                'status' => $response->status(),
                'message' => $message,
            ]);

            throw new SupabaseRpcException($message, $body['code'] ?? null, $response->status());
        }

        $decoded = $response->json();

        return (is_array($decoded) && array_is_list($decoded)) ? ($decoded[0] ?? []) : ($decoded ?? []);
    }

    /**
     * Filtered read against a plain table via PostgREST, running AS the
     * caller so RLS SELECT policies apply.
     *
     * @param string $table   e.g. 'booking_requirements'
     * @param array  $filters PostgREST filter query params, e.g.
     *                        ['booking_id' => 'eq.' . $bookingId]
     * @param string|null $select PostgREST select= column list, or null
     *                             for '*'
     *
     * @return array list of matching rows (always an array, even if empty)
     *
     * @throws SupabaseRpcException
     */
    public function select(
        string $table,
        array $filters,
        string $userAccessToken,
        ?string $select = null,
    ): array {
        $query = $filters;
        if ($select !== null) {
            $query['select'] = $select;
        }

        try {
            $response = Http::withHeaders([
                'apikey' => $this->anonKey,
                'Authorization' => "Bearer {$userAccessToken}",
            ])
                ->timeout(15)
                ->get("{$this->baseUrl}/rest/v1/{$table}", $query);
        } catch (\Throwable $e) {
            Log::error('Supabase select transport error', ['table' => $table, 'error' => $e->getMessage()]);

            throw new SupabaseRpcException('UPSTREAM_UNAVAILABLE', null, 503, $e);
        }

        if (! $response->successful()) {
            $body = $response->json() ?? [];
            $message = $body['message'] ?? $response->body();

            Log::warning('Supabase select failed', [
                'table' => $table,
                'status' => $response->status(),
                'message' => $message,
            ]);

            throw new SupabaseRpcException($message, $body['code'] ?? null, $response->status());
        }

        return $response->json() ?? [];
    }

    /**
     * Resolve the caller's own user record from their access token.
     * Used whenever a write needs to know the caller's user id up front
     * (e.g. customer_documents.owner_user_id, which has no default and
     * isn't auto-filled by RLS — only validated against auth.uid()).
     *
     * @throws SupabaseRpcException if the token is missing/invalid
     */
    public function getCurrentUser(string $userAccessToken): array
    {
        try {
            $response = Http::withHeaders([
                'apikey' => $this->anonKey,
                'Authorization' => "Bearer {$userAccessToken}",
            ])->timeout(10)->get("{$this->baseUrl}/auth/v1/user");
        } catch (\Throwable $e) {
            throw new SupabaseRpcException('UPSTREAM_UNAVAILABLE', null, 503, $e);
        }

        if (! $response->successful()) {
            throw new SupabaseRpcException('NOT_AUTHENTICATED', null, 401);
        }

        return $response->json() ?? [];
    }

    /**
     * Upload raw file bytes to Supabase Storage.
     *
     * @param string $bucket   e.g. 'payment-proofs'
     * @param string $path     object path within the bucket, e.g.
     *                         "{userId}/{bookingId}/{uuid}-{filename}"
     * @param string $contents raw file bytes
     * @param string $mimeType e.g. 'image/jpeg'
     * @param bool   $upsert   when true, overwrite an existing object at
     *                         this exact path instead of failing; defaults
     *                         to false to preserve every prior caller's
     *                         behavior. Used by the document-upload
     *                         endpoint, which mirrors the real app's
     *                         upsert:true retry behavior for the same
     *                         kind+submissionId path.
     *
     * @throws SupabaseRpcException
     */
    public function uploadObject(
        string $bucket,
        string $path,
        string $contents,
        string $mimeType,
        string $userAccessToken,
        bool $upsert = false,
    ): void {
        try {
            $response = Http::withHeaders([
                'apikey' => $this->anonKey,
                'Authorization' => "Bearer {$userAccessToken}",
                'Content-Type' => $mimeType,
                'x-upsert' => $upsert ? 'true' : 'false',
            ])
                ->timeout(30)
                ->withBody($contents, $mimeType)
                ->post("{$this->baseUrl}/storage/v1/object/{$bucket}/{$path}");
        } catch (\Throwable $e) {
            Log::error('Supabase storage upload transport error', ['bucket' => $bucket, 'error' => $e->getMessage()]);

            throw new SupabaseRpcException('UPSTREAM_UNAVAILABLE', null, 503, $e);
        }

        if (! $response->successful()) {
            $body = $response->json() ?? [];
            $message = $body['message'] ?? $response->body();

            Log::warning('Supabase storage upload failed', [
                'bucket' => $bucket,
                'path' => $path,
                'status' => $response->status(),
                'message' => $message,
            ]);

            throw new SupabaseRpcException($message, null, $response->status());
        }
    }

    /**
     * List objects in a Storage bucket folder, optionally filtered to an
     * exact filename via $search. Used to confirm a client-reported
     * upload path actually exists before trusting it (mirrors the real
     * app's verifyUploadedFile(), which does this with the admin/
     * service-role client; here it runs as the customer's own token
     * instead — see class docblock). ASSUMPTION FLAGGED: assumes Storage
     * RLS lets a customer list their own folder, the same assumption
     * uploadObject()'s success already depends on. If listing is blocked
     * where uploading isn't, this needs revisiting.
     *
     * @throws SupabaseRpcException
     */
    public function listObjects(string $bucket, string $prefix, string $userAccessToken, ?string $search = null): array
    {
        try {
            $response = Http::withHeaders([
                'apikey' => $this->anonKey,
                'Authorization' => "Bearer {$userAccessToken}",
                'Content-Type' => 'application/json',
            ])
                ->timeout(15)
                ->post("{$this->baseUrl}/storage/v1/object/list/{$bucket}", array_filter([
                    'prefix' => $prefix,
                    'search' => $search,
                    'limit' => 100,
                ]));
        } catch (\Throwable $e) {
            Log::error('Supabase storage list transport error', ['bucket' => $bucket, 'error' => $e->getMessage()]);

            throw new SupabaseRpcException('UPSTREAM_UNAVAILABLE', null, 503, $e);
        }

        if (! $response->successful()) {
            $body = $response->json() ?? [];

            throw new SupabaseRpcException($body['message'] ?? $response->body(), $body['code'] ?? null, $response->status());
        }

        return $response->json() ?? [];
    }

    /**
     * Delete an object from Storage — used to clean up an uploaded file
     * if a later step (e.g. the customer_documents insert) fails, so a
     * partial submission doesn't leave an orphaned file behind.
     */
    public function deleteObject(string $bucket, string $path, string $userAccessToken): void
    {
        try {
            Http::withHeaders([
                'apikey' => $this->anonKey,
                'Authorization' => "Bearer {$userAccessToken}",
            ])->timeout(15)->delete("{$this->baseUrl}/storage/v1/object/{$bucket}/{$path}");
        } catch (\Throwable $e) {
            // Best-effort cleanup — log and move on, don't let a cleanup
            // failure mask the original error that triggered it.
            Log::error('Supabase storage cleanup failed', [
                'bucket' => $bucket, 'path' => $path, 'error' => $e->getMessage(),
            ]);
        }
    }
}