// lib/services/supabase_client.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Equivalent of `src/lib/supabase/client.ts` — the customer app talks
/// directly to the same Supabase project the Next.js site uses (same
/// Postgres tables, RLS policies, and RPCs), just from Dart instead of JS.
///
/// Fill these in from your `.env` / `.env.local`:
///   NEXT_PUBLIC_SUPABASE_URL             -> supabaseUrl
///   NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY  -> supabaseAnonKey
///
/// Do NOT put the service-role key here — this is the public, RLS-scoped
/// anon key only, same as the browser client in the web app.
class SupabaseConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR-PROJECT.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR-PUBLISHABLE-ANON-KEY',
  );

  static bool get isConfigured =>
      !supabaseUrl.contains('YOUR-PROJECT') && !supabaseAnonKey.contains('YOUR-PUBLISHABLE');

  static Future<void> init() async {
    if (!isConfigured) {
      // Fail loudly and clearly here instead of letting every screen hit a
      // confusing ERR_NAME_NOT_RESOLVED / ClientException later. See README
      // "Setup" — you must pass real values via --dart-define, e.g.:
      //   flutter run \
      //     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
      //     --dart-define=SUPABASE_ANON_KEY=eyJ...
      throw StateError(
        'Supabase is not configured. Pass --dart-define=SUPABASE_URL=... and '
        '--dart-define=SUPABASE_ANON_KEY=... when running/building the app '
        '(same values as NEXT_PUBLIC_SUPABASE_URL / '
        'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY in your .env.local).',
      );
    }
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }
}

/// Shorthand accessor, mirrors calling `createClient()` in the TS services.
SupabaseClient get supabase => Supabase.instance.client;