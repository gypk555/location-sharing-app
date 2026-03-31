import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/auth_provider.dart';
import '../features/auth/screens/otp_screen.dart';
import '../features/auth/screens/unified_auth_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/sos/screens/sos_screen.dart';
import '../features/contacts/screens/contacts_screen.dart';
import '../features/contacts/screens/add_contact_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/fake_call/screens/fake_call_screen.dart';
import '../shared/widgets/main_scaffold.dart';

/// Listenable that notifies GoRouter when auth state changes
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen(authStateProvider, (prev, next) => notifyListeners());
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthNotifier(ref);

  return GoRouter(
    initialLocation: '/auth',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggedIn = authState.isAuthenticated;
      final isLoading = authState.isLoading;
      final isAuthRoute = state.matchedLocation == '/auth' ||
          state.matchedLocation == '/otp';

      // Still loading - allow current route
      if (isLoading) return null;

      // Not logged in and not on auth page
      if (!isLoggedIn && !isAuthRoute) return '/auth';

      // Logged in but on auth page
      if (isLoggedIn && isAuthRoute) return '/';

      return null;
    },
    routes: [
      // Auth routes - unified auth screen replaces login/register
      GoRoute(
        path: '/auth',
        builder: (context, state) => const UnifiedAuthScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final phone = state.extra as String? ?? '';
          return OtpScreen(phone: phone);
        },
      ),

      // Main app with bottom navigation
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/sos',
            builder: (context, state) => const SosScreen(),
          ),
          GoRoute(
            path: '/contacts',
            builder: (context, state) => const ContactsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),

      // Additional routes
      GoRoute(
        path: '/add-contact',
        builder: (context, state) => const AddContactScreen(),
      ),
      GoRoute(
        path: '/fake-call',
        builder: (context, state) => const FakeCallScreen(),
      ),
    ],
  );
});
