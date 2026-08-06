// lib/widgets/app_shell.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';

/// Mobile equivalent of `components/navbar/Navbar.tsx`. The web navbar is a
/// horizontal link bar + dropdowns, which doesn't translate well to a phone
/// screen — a bottom nav bar is the native pattern for the same four
/// destinations (Home, Browse, Bookings, Account).
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    (path: '/', icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    (path: '/catalog', icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view, label: 'Browse'),
    (path: '/account/bookings', icon: Icons.event_note_outlined, activeIcon: Icons.event_note, label: 'Bookings'),
    (path: '/account/profile', icon: Icons.person_outline, activeIcon: Icons.person, label: 'Account'),
  ];

  int _currentIndex(String location) {
    if (location.startsWith('/catalog')) return 1;
    if (location.startsWith('/account/bookings')) return 2;
    if (location.startsWith('/account')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _currentIndex(location);
    final auth = context.watch<AppAuth>();

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          final tab = _tabs[index];
          // Account/Bookings require sign-in — same guard as RequireCustomer.tsx.
          if (index >= 2 && auth.user == null) {
            context.push('/sign-in?redirect=${Uri.encodeComponent(tab.path)}');
            return;
          }
          context.go(tab.path);
        },
        destinations: _tabs
            .map((tab) => NavigationDestination(
                  icon: Icon(tab.icon),
                  selectedIcon: Icon(tab.activeIcon),
                  label: tab.label,
                ))
            .toList(),
      ),
    );
  }
}
