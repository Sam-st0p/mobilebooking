# Mobile Booking

Flutter port of the customer-facing part of your Next.js app. **Admin is
intentionally excluded** — this app only covers what a renting customer sees.

## Architecture decision (read this first)

Your web app talks to Supabase **directly from the browser** (see
`src/lib/supabase/client.ts`, `src/services/productService.ts`,
`src/services/authService.ts`) — no custom backend API for products, auth,
or reads. So this Flutter app does the same thing: it uses the
`supabase_flutter` package to talk **directly to your same Supabase
project** — same tables, same RLS policies, same RPCs
(`get_product_availability`, `get_product_reviews`), same Storage bucket.
That means:

- No new backend to build or maintain.
- Any RLS policy, RPC, or trigger you already have "just works" from mobile.
- Things that require server secrets — PayMongo checkout/webhook, PDF
  generation, web push registration, sending the rental agreement — **stay
  on your Next.js API routes** (`/api/payments/checkout`, `/api/paymongo/webhook`,
  etc.). Those get called over plain HTTPS from Flutter in phase 2; they were
  never meant to run client-side, on web or mobile.

## Setup

1. Install Flutter (flutter.dev) if you haven't already.
2. `cd rental_by_maddy_and_cassy && flutter pub get`
3. Run with your Supabase credentials (same values as your `.env.local`
   `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`):

   ```bash
   flutter run \
     --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLISHABLE-ANON-KEY
   ```

   (For a real build, put these in a launch config / CI secret rather than
   typing them every time — `--dart-define-from-file` works well.)

## What's fully converted (phase 1)

| Web (Next.js) | Flutter |
|---|---|
| `app/globals.css` palette + Poppins | `lib/theme/app_theme.dart` |
| `types/product.ts` | `lib/models/product.dart` |
| `lib/availability.ts` | `lib/utils/availability.dart` |
| `src/services/productService.ts` | `lib/services/product_service.dart` |
| `src/services/authService.ts` | `lib/services/auth_service.dart` |
| `src/contexts/AuthContext.tsx` | `lib/services/auth_provider.dart` |
| `src/services/userService.ts` (customer parts) | `lib/services/profile_service.dart` |
| `hooks/useFavorites.ts` | `lib/services/favorites_service.dart` |
| `app/page.tsx` (Home) | `lib/screens/home_screen.dart` |
| `app/catalog/page.tsx` + `CatalogView.tsx` | `lib/screens/catalog/catalog_screen.dart` |
| `app/catalog/[id]/...` | `lib/screens/catalog/product_detail_screen.dart` |
| `(auth)/sign-in`, `sign-up`, `verify-email` | `lib/screens/auth/*.dart` |
| `components/navbar/Navbar.tsx` | `lib/widgets/app_shell.dart` (bottom nav — the native mobile pattern instead of a link bar) |

## What's stubbed as "Coming Soon" (phase 2 — next up)

These render a placeholder screen right now so the app runs end-to-end;
converting them is the natural next step, roughly in this priority order:

1. **Reservation flow** (`app/catalog/[id]/reserve/ReserveFlowClient.tsx` +
   `components/reservation/*`) — the multi-step booking wizard: dates →
   requirements → signature/agreement → payment → confirmation. This is
   your highest-value screen and the biggest one (signature pad, file
   upload, PayMongo checkout call).
2. **Account section** (`app/account/bookings`, `.../profile`,
   `.../payments`) — booking list/detail, profile editing, payment history.
3. **Static guide pages** (FAQ, Terms, How to Book, Rental Requirements,
   Contact, Privacy) — straightforward content screens, low effort.
4. **Live inventory** (`hooks/useInventory.ts`) — Supabase realtime
   subscription for live unit counts; currently the catalog uses the
   same point-in-time snapshot the web app's initial page load uses.
5. **Push notifications** (`components/push/PushNotificationButton.tsx`) —
   swap web push for `firebase_messaging` or native push, since
   `src/lib/webpush/*` is browser-specific.

Want me to keep going with the reservation flow next? That's the one
worth doing carefully given the signature pad + payment step.
