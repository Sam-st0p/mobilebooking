// lib/routing/app_router.dart

import 'package:go_router/go_router.dart';
import '../models/booking.dart';
import '../screens/account/profile_screen.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/auth/sign_up_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/booking/booking_detail_screen.dart';
import '../screens/booking/bookings_list_screen.dart';
import '../screens/booking/payment_pending_screen.dart';
import '../screens/booking/reserve_screen.dart';
import '../screens/catalog/catalog_screen.dart';
import '../screens/catalog/product_detail_screen.dart';
import '../screens/coming_soon_screen.dart';
import '../screens/home_screen.dart';
import '../widgets/app_shell.dart';

/// Route table mirroring the `app/` folder in the Next.js project.
/// Everything under `app/admin/*` and `app/api/admin/*` is intentionally
/// excluded — this is the customer-facing app only.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/catalog', builder: (context, state) => const CatalogScreen()),
        GoRoute(
          path: '/account/bookings',
          builder: (context, state) => const BookingsListScreen(),
        ),
        GoRoute(
          path: '/account/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/account/payments',
          builder: (context, state) => const ComingSoonScreen(
            title: 'Payment History',
            note: 'Payment history (app/account/payments) — phase 2.',
          ),
        ),
      ],
    ),

    // Full-screen routes (no bottom nav) — product detail, reservation,
    // auth, and static guide pages.
    GoRoute(
      path: '/catalog/:id',
      builder: (context, state) => ProductDetailScreen(idOrSlug: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/catalog/:id/reserve',
      builder: (context, state) => ReserveScreen(idOrSlug: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/booking-payment-pending',
      builder: (context, state) => PaymentPendingScreen(booking: state.extra as Booking),
    ),
    GoRoute(
      path: '/account/bookings/:id',
      builder: (context, state) => BookingDetailScreen(
        bookingId: state.pathParameters['id']!,
        initialBooking: state.extra as Booking?,
      ),
    ),
    GoRoute(path: '/sign-in', builder: (context, state) => const SignInScreen()),
    GoRoute(path: '/sign-up', builder: (context, state) => const SignUpScreen()),
    GoRoute(
      path: '/verify-email',
      builder: (context, state) => VerifyEmailScreen(
        email: state.uri.queryParameters['email'] ?? '',
        flow: state.uri.queryParameters['flow'] ?? 'sign-in',
      ),
    ),
    GoRoute(
      path: '/how-to-book',
      builder: (context, state) => const ComingSoonScreen(title: 'How to Book'),
    ),
    GoRoute(
      path: '/rental-requirements',
      builder: (context, state) => const ComingSoonScreen(title: 'Rental Requirements'),
    ),
    GoRoute(path: '/terms', builder: (context, state) => const ComingSoonScreen(title: 'Terms & Conditions')),
    GoRoute(path: '/faq', builder: (context, state) => const ComingSoonScreen(title: 'FAQs')),
    GoRoute(path: '/contact', builder: (context, state) => const ComingSoonScreen(title: 'Contact')),
    GoRoute(path: '/privacy', builder: (context, state) => const ComingSoonScreen(title: 'Privacy Policy')),
  ],
);