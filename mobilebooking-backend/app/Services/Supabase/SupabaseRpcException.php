<?php

namespace App\Services\Supabase;

use RuntimeException;
use Throwable;

/**
 * Thrown by SupabaseRpcService for any non-2xx reply from Supabase (PostgREST
 * RPCs, table reads/inserts, Storage, Auth) or when Supabase can't be reached.
 *
 * `getMessage()` carries the raw upstream message. For Postgres functions that
 * `raise exception 'FOO'` it is exactly `FOO`, which is what the controllers
 * match on (e.g. PRODUCT_NOT_AVAILABLE, NO_TIME_AVAILABILITY:...). Transport
 * failures use UPSTREAM_UNAVAILABLE and a missing/invalid token uses
 * NOT_AUTHENTICATED.
 *
 * Constructed both positionally  new SupabaseRpcException($msg, $code, $status, $e)
 * and with named arguments        new SupabaseRpcException(message: ..., pgCode: ...,
 * httpStatus: ..., previous: ...), so those parameter names must not change.
 */
class SupabaseRpcException extends RuntimeException
{
    /** Postgres SQLSTATE or PostgREST code (e.g. "P0001", "PGRST203"), if any. */
    public readonly ?string $pgCode;

    /** The HTTP status Supabase answered with (or 503 for transport errors). */
    public readonly int $httpStatus;

    public function __construct(
        string $message,
        int|string|null $pgCode = null,
        int $httpStatus = 500,
        ?Throwable $previous = null,
    ) {
        parent::__construct($message, 0, $previous);

        $this->pgCode = $pgCode === null ? null : (string) $pgCode;
        $this->httpStatus = $httpStatus;
    }
}