<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Supabase\SupabaseRpcException;
use App\Services\Supabase\SupabaseRpcService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

/**
 * The signed-in customer's profile: GET / PUT /account/profile and
 * POST /account/profile/photo.
 *
 * The real profile lives in the `profiles` table (BookingDocumentController already
 * reads `profiles.display_name`). The old GET route only echoed Supabase Auth's
 * user_metadata, so the app saw an empty name/phone/address, and PUT/photo did not
 * exist at all.
 *
 * SECURITY BOUNDARY: like the other controllers, writes go through Laravel's own DB
 * connection, which bypasses row-level security. That is safe here only because every
 * query is pinned to `id = <the authenticated user's id>`, taken from Supabase Auth
 * for the bearer token — never from the request body.
 *
 * The exact column names in `profiles` were not visible to the backend, so each field
 * lists candidate column names and the first one the table really has is used
 * (Schema::getColumnListing). Fields with no matching column are simply skipped.
 */
class ProfileController extends Controller
{
    private const COLUMNS = [
        'firstName' => ['first_name'],
        'lastName' => ['last_name'],
        'displayName' => ['display_name', 'full_name', 'name'],
        'phoneNumber' => ['phone_number', 'phone'],
        'birthDate' => ['birth_date', 'birthdate', 'date_of_birth'],
        'fullAddress' => ['full_address', 'address'],
        'facebookLink' => ['facebook_link', 'facebook_url', 'facebook'],
        'instagramLink' => ['instagram_link', 'instagram_url', 'instagram'],
        'accountStatus' => ['account_status', 'status'],
        'photoPath' => ['photo_path', 'avatar_path', 'avatar_url', 'photo_url'],
        'createdAt' => ['created_at'],
        'updatedAt' => ['updated_at'],
    ];

    /** GET /account/profile */
    public function show(Request $request, SupabaseRpcService $supabase): JsonResponse
    {
        [, $user, $error] = $this->authenticate($request, $supabase);
        if ($error) {
            return $error;
        }

        return response()->json(['success' => true, 'profile' => $this->present($user)]);
    }

    /** PUT /account/profile */
    public function update(Request $request, SupabaseRpcService $supabase): JsonResponse
    {
        [, $user, $error] = $this->authenticate($request, $supabase);
        if ($error) {
            return $error;
        }

        $validator = Validator::make($request->all(), [
            'displayName' => ['sometimes', 'required', 'string', 'min:2', 'max:160'],
            'phoneNumber' => ['sometimes', 'nullable', 'string', 'regex:/^\d{11}$/'],
            'fullAddress' => ['sometimes', 'nullable', 'string', 'max:500'],
            'facebookLink' => ['sometimes', 'nullable', 'string', 'max:500'],
            'instagramLink' => ['sometimes', 'nullable', 'string', 'max:500'],
        ], [
            'displayName.required' => 'Please enter your full name.',
            'displayName.min' => 'Please enter your full name.',
            'phoneNumber.regex' => 'Use exactly 11 digits for your phone number.',
        ]);

        if ($validator->fails()) {
            return response()->json(['error' => $validator->errors()->first()], 422);
        }
        $data = $validator->validated();

        foreach (['facebookLink' => 'Facebook', 'instagramLink' => 'Instagram'] as $field => $label) {
            if (array_key_exists($field, $data)) {
                $link = $this->normalizeLink($data[$field]);
                if ($data[$field] !== null && $link === false) {
                    return response()->json(['error' => "Enter a valid {$label} link, e.g. https://facebook.com/yourname."], 422);
                }
                $data[$field] = $link === false ? null : $link;
            }
        }

        $userId = $user['id'];
        $existing = DB::table('profiles')->where('id', $userId)->first();
        if (!$existing) {
            return response()->json(['error' => 'We could not find your profile record. Please contact support.'], 404);
        }

        $columns = Schema::getColumnListing('profiles');
        $current = (array) $existing;
        $updates = [];

        foreach (['displayName', 'phoneNumber', 'fullAddress', 'facebookLink', 'instagramLink'] as $field) {
            if (!array_key_exists($field, $data)) {
                continue;
            }
            $column = $this->columnFor($field, $columns);
            if ($column !== null) {
                $updates[$column] = $data[$field];
            }
        }

        // Keep first/last name in step when they are both empty (never overwrite real data).
        if (isset($data['displayName'])) {
            $firstCol = $this->columnFor('firstName', $columns);
            $lastCol = $this->columnFor('lastName', $columns);
            if ($firstCol && $lastCol && blank($current[$firstCol] ?? null) && blank($current[$lastCol] ?? null)) {
                $parts = preg_split('/\s+/', trim($data['displayName'])) ?: [];
                if (count($parts) > 1) {
                    $updates[$lastCol] = array_pop($parts);
                    $updates[$firstCol] = implode(' ', $parts);
                } else {
                    $updates[$firstCol] = $parts[0] ?? $data['displayName'];
                }
            }
        }

        if ($updates !== []) {
            if (in_array('updated_at', $columns, true)) {
                $updates['updated_at'] = now();
            }

            DB::transaction(function () use ($userId, $updates) {
                // Let auth.uid() resolve for any trigger/default, as PostgREST would.
                DB::select(
                    "select set_config('request.jwt.claims', ?, true), set_config('request.jwt.claim.sub', ?, true)",
                    [json_encode(['sub' => $userId, 'role' => 'authenticated']), $userId],
                );
                DB::table('profiles')->where('id', $userId)->update($updates);
            });
        }

        return response()->json(['success' => true, 'profile' => $this->present($user)]);
    }

    /** POST /account/profile/photo  (multipart field: file) */
    public function uploadPhoto(Request $request, SupabaseRpcService $supabase): JsonResponse
    {
        [$token, $user, $error] = $this->authenticate($request, $supabase);
        if ($error) {
            return $error;
        }

        $validator = Validator::make($request->all(), [
            'file' => ['required', 'file', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
        ], [
            'file.mimes' => 'Choose a JPG, PNG or WEBP photo.',
            'file.max' => 'Please choose a photo up to 5 MB.',
        ]);
        if ($validator->fails()) {
            return response()->json(['error' => $validator->errors()->first()], 422);
        }

        $userId = $user['id'];
        $columns = Schema::getColumnListing('profiles');
        $photoColumn = $this->columnFor('photoPath', $columns);
        if ($photoColumn === null) {
            return response()->json(['error' => 'Profile photos are not set up for this account yet.'], 501);
        }
        if (!DB::table('profiles')->where('id', $userId)->exists()) {
            return response()->json(['error' => 'We could not find your profile record. Please contact support.'], 404);
        }

        $file = $request->file('file');
        $extension = match ($file->getMimeType()) {
            'image/png' => 'png',
            'image/webp' => 'webp',
            default => 'jpg',
        };
        $bucket = (string) config('services.supabase.profile_photo_bucket', 'profile-photos');
        $path = sprintf('%s/avatar-%s.%s', $userId, Str::uuid(), $extension);

        try {
            $supabase->uploadObject(
                bucket: $bucket,
                path: $path,
                contents: file_get_contents($file->getRealPath()),
                mimeType: $file->getMimeType() ?? 'image/jpeg',
                userAccessToken: $token,
                upsert: true,
            );
        } catch (SupabaseRpcException $e) {
            report($e);

            return response()->json([
                'error' => 'We could not upload your photo. Please try again.'
                    . (config('app.debug') ? " [debug: {$e->getMessage()} | bucket {$bucket}]" : ''),
            ], 502);
        }

        $updates = [$photoColumn => $path];
        if (in_array('updated_at', $columns, true)) {
            $updates['updated_at'] = now();
        }
        DB::table('profiles')->where('id', $userId)->update($updates);

        $profile = $this->present($user);

        return response()->json(['success' => true, 'photoUrl' => $profile['photoUrl'], 'profile' => $profile]);
    }

    // ---------------------------------------------------------------------

    /** @return array{0: ?string, 1: ?array, 2: ?JsonResponse} [token, supabase user, error response] */
    private function authenticate(Request $request, SupabaseRpcService $supabase): array
    {
        $token = $request->attributes->get('supabase_access_token') ?? $request->bearerToken();
        if (blank($token)) {
            return [null, null, response()->json(['success' => false, 'error' => 'You need to be signed in.'], 401)];
        }

        try {
            $user = $supabase->getCurrentUser($token);
        } catch (SupabaseRpcException $e) {
            return [null, null, response()->json(['success' => false, 'error' => 'Your session has expired. Please sign in again.'], 401)];
        }

        if (blank($user['id'] ?? null)) {
            return [null, null, response()->json(['success' => false, 'error' => 'Could not resolve your account.'], 401)];
        }

        return [$token, $user, null];
    }

    /** The profile in the exact shape the Flutter UserProfile model reads. */
    private function present(array $user): array
    {
        $row = DB::table('profiles')->where('id', $user['id'])->first();
        $p = $row ? (array) $row : [];

        $get = function (string $field) use ($p) {
            // Defensive: self::COLUMNS[$field] should always exist for the field
            // names used below, but a missing/mistyped entry must degrade to
            // "no value found" instead of crashing the whole profile load.
            foreach (self::COLUMNS[$field] ?? [] as $column) {
                if (array_key_exists($column, $p) && $p[$column] !== null && $p[$column] !== '') {
                    return $p[$column];
                }
            }

            return null;
        };
        $str = fn ($v) => $v === null ? null : (string) $v;

        $meta = $user['user_metadata'] ?? [];
        $first = $str($get('firstName'));
        $last = $str($get('lastName'));

        $displayName = $str($get('displayName'));
        if ($displayName === null) {
            $displayName = trim(($first ?? '') . ' ' . ($last ?? ''));
        }
        if ($displayName === '') {
            $displayName = (string) ($meta['full_name'] ?? $meta['display_name'] ?? '');
        }

        $photoPath = $str($get('photoPath'));

        return [
            'id' => $user['id'],
            'email' => $user['email'] ?? '',
            'firstName' => $first,
            'lastName' => $last,
            'displayName' => $displayName,
            'phoneNumber' => $str($get('phoneNumber')) ?? (filled($user['phone'] ?? null) ? (string) $user['phone'] : null),
            'birthDate' => $str($get('birthDate')),
            'fullAddress' => $str($get('fullAddress')),
            'facebookLink' => $str($get('facebookLink')),
            'instagramLink' => $str($get('instagramLink')),
            'accountStatus' => $str($get('accountStatus')) ?? 'active',
            'photoPath' => $photoPath,
            'photoUrl' => $this->photoUrl($photoPath),
            'createdAt' => $this->iso($get('createdAt')) ?? '',
            'updatedAt' => $this->iso($get('updatedAt')) ?? '',
        ];
    }

    private function photoUrl(?string $path): ?string
    {
        if ($path === null || $path === '') {
            return null;
        }
        if (str_starts_with($path, 'http://') || str_starts_with($path, 'https://')) {
            return $path;
        }

        // Public-bucket URL. If the bucket is private the image will not display;
        // make the bucket public or serve a signed URL instead.
        return rtrim((string) config('services.supabase.url'), '/')
            . '/storage/v1/object/public/'
            . config('services.supabase.profile_photo_bucket', 'profile-photos')
            . '/' . ltrim($path, '/');
    }

    private function iso(mixed $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        try {
            return Carbon::parse($value)->toIso8601String();
        } catch (\Throwable) {
            return (string) $value;
        }
    }

    /** First candidate column that really exists in the table. */
    private function columnFor(string $field, array $columns): ?string
    {
        foreach (self::COLUMNS[$field] ?? [] as $candidate) {
            if (in_array($candidate, $columns, true)) {
                return $candidate;
            }
        }

        return null;
    }

    /** null/'' -> null; adds https:// when missing; returns false when it is not a usable link. */
    private function normalizeLink(?string $value): string|false|null
    {
        $value = trim((string) $value);
        if ($value === '') {
            return null;
        }
        $candidate = preg_match('#^[a-z][a-z0-9+.\-]*://#i', $value) ? $value : 'https://' . $value;
        $host = parse_url($candidate, PHP_URL_HOST);
        $scheme = parse_url($candidate, PHP_URL_SCHEME);
        if (!in_array($scheme, ['http', 'https'], true) || !$host || !str_contains($host, '.') || preg_match('/\s/', $candidate)) {
            return false;
        }

        return $candidate;
    }
}