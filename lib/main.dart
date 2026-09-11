// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'routing/app_router.dart';
import 'services/api_client.dart';
import 'services/auth_provider.dart';
import 'services/favorites_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FavoritesService.init();
  runApp(const RentalApp());
}

/// Wraps the app in the auth provider, which tracks a backend-issued JWT
/// session. If API_BASE_URL isn't configured (see ApiConfig.isConfigured),
/// the app still runs fully — catalog/product screens fall back to sample
/// data (see ProductService + MockData) so you can preview the UI with
/// zero setup. Sign-in and account features need a real backend, since
/// there's no data to sign into without one.
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
        builder: (context, child) {
          if (ApiConfig.isConfigured) return child ?? const SizedBox.shrink();
          // Small persistent badge instead of blocking the whole app —
          // lets you browse the catalog with sample data right away.
          return Stack(
            children: [
              if (child != null) child,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    color: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: const Text(
                      'DEMO MODE — sample data, no backend connected',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.white, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
