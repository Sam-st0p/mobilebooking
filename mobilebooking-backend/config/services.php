<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Resend, Postmark, AWS, and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'supabase' => [
        'url' => env('SUPABASE_URL'),
        // Anon/public key only — never put the service_role key here.
        // Every call using this key also carries a specific user's own
        // bearer token, so it can't be used to bypass RLS.
        'anon_key' => env('SUPABASE_ANON_KEY'),
        // Storage bucket for profile photos. Set SUPABASE_PROFILE_PHOTO_BUCKET in .env if yours is named differently.
        'profile_photo_bucket' => env('SUPABASE_PROFILE_PHOTO_BUCKET', 'profile-photos'),
    ],

];