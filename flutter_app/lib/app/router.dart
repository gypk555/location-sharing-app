import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/contact_model.dart';
import '../core/models/user_model.dart';
import '../core/providers/auth_provider.dart';
import '../features/auth/screens/otp_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/unified_auth_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/sos/screens/sos_screen.dart';
import '../features/contacts/screens/contacts_screen.dart';
import '../features/contacts/screens/add_contact_screen.dart';
import '../features/settings/screens/notifications_settings_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/settings/screens/profile_edit_screen.dart';
import '../features/settings/screens/sos_message_screen.dart';
import '../features/settings/screens/fake_caller_screen.dart';
import '../features/fake_call/screens/fake_call_screen.dart';
import '../features/live_sharing/presentation/screens/active_share_screen.dart';
import '../features/live_sharing/presentation/screens/receive_share_screen.dart';
import '../features/live_sharing/presentation/screens/start_share_screen.dart';
import '../shared/widgets/main_scaffold.dart';
import 'routes.dart';

/// Listenable that notifies GoRouter when auth state changes
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen(authStateProvider, (prev, next) => notifyListeners());
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthNotifier(ref);
  // Riverpod caches `Provider`s, but `_AuthNotifier` holds a ChangeNotifier
  // subscription and must be disposed if the provider is ever invalidated
  // (hot restart, ProviderScope teardown in tests). Without this hook the
  // listener is leaked on recreation (code-review finding §3.7).
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggedIn = authState.isAuthenticated;
      final hasInitialized = authState.hasInitialized;
      final initError = authState.initError;
      final isSplashRoute = state.matchedLocation == AppRoutes.splash;
      final isAuthRoute = state.matchedLocation == AppRoutes.auth ||
          state.matchedLocation == AppRoutes.otp;

      // App not initialized yet - always show splash screen
      // This prevents a brief flash of the auth screen before session restore completes.
      if (!hasInitialized) return isSplashRoute ? null : AppRoutes.splash;

      // Initialization error - keep user on splash to show retry UI
      // Allow logged-in users to proceed (offline-friendly)
      if (initError != null && !isLoggedIn) {
        return isSplashRoute ? null : AppRoutes.splash;
      }

      // Loading complete - proceed with auth checks
      if (hasInitialized && isSplashRoute) {
        // If logged in, go to home, otherwise go to auth
        return isLoggedIn ? AppRoutes.home : AppRoutes.auth;
      }

      // Not logged in and not on auth page
      if (!isLoggedIn && !isAuthRoute) return AppRoutes.auth;

      // Logged in but on auth page
      if (isLoggedIn && isAuthRoute) return AppRoutes.home;

      return null;
    },
    routes: [
      // Splash screen shown during initialization
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      // Auth routes - unified auth screen replaces login/register
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const UnifiedAuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
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
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.sos,
            builder: (context, state) => const SosScreen(),
          ),
          GoRoute(
            path: AppRoutes.contacts,
            builder: (context, state) => const ContactsScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),

      // Additional routes
      GoRoute(
        path: AppRoutes.addContact,
        builder: (context, state) {
          // Safe type check to prevent runtime crash if wrong type is passed
          final contact = state.extra is ContactModel ? state.extra as ContactModel : null;
          return AddContactScreen(contact: contact);
        },
      ),
      GoRoute(
        path: AppRoutes.fakeCall,
        builder: (context, state) => const FakeCallScreen(),
      ),
      GoRoute(
        path: AppRoutes.notificationsSettings,
        builder: (context, state) => const NotificationsSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsProfile,
        builder: (context, state) {
          final user = state.extra as UserModel?;
          if (user == null) {
            // Fallback if accessed without extra
            return const SettingsScreen(); 
          }
          return ProfileEditScreen(user: user);
        },
      ),
      GoRoute(
        path: AppRoutes.settingsSos,
        builder: (context, state) => const SosMessageScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsFakeCall,
        builder: (context, state) {
          final focus = state.extra as FakeCallerField? ?? FakeCallerField.name;
          return FakeCallerScreen(focus: focus);
        },
      ),

      // Live location sharing
      GoRoute(
        path: AppRoutes.liveShareStart,
        builder: (context, state) => const StartShareScreen(),
      ),
      GoRoute(
        path: AppRoutes.liveShareActive,
        builder: (context, state) => const ActiveShareScreen(),
      ),
      GoRoute(
        path: AppRoutes.liveShareViewPattern,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return ReceiveShareScreen(sharingId: id);
        },
      ),
    ],
  );
});
