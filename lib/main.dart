// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'routing/app_router.dart';
import 'services/auth_provider.dart';
import 'services/favorites_service.dart';
import 'services/supabase_client.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SupabaseConfig.init();
    await FavoritesService.init();
    runApp(const RentalApp());
  } catch (e) {
    runApp(_SetupNeededApp(message: e.toString()));
  }
}

/// Shown instead of the real app when SUPABASE_URL / SUPABASE_ANON_KEY
/// weren't passed in — see README "Setup".
class _SetupNeededApp extends StatelessWidget {
  final String message;
  const _SetupNeededApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_outlined, size: 40),
                const SizedBox(height: 12),
                const Text('Setup needed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Equivalent of `app/layout.tsx` — wraps the whole app in the auth
/// provider (AuthProvider) the same way the web root layout does.
class RentalApp extends StatelessWidget {
  const RentalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppAuth()..init(),
      child: MaterialApp.router(
        title: 'Rental by Maddy & Cassy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: appRouter,
      ),
    );
  }
}