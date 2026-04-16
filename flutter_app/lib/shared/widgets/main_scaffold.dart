import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/live_sharing_provider.dart';

class MainScaffold extends ConsumerStatefulWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold>
    with WidgetsBindingObserver {
  static const _exitConfirmWindow = Duration(seconds: 2);
  DateTime? _lastBackPressAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Pull any pre-existing active sharing session from the server on
    // first shell mount. If a previous run left a session alive (user
    // force-killed the app, time-boxed session hasn't expired, etc.),
    // this repopulates the in-memory state so the home-screen tile can
    // reflect it and the user can tap to view/stop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(liveSharingProvider.notifier).hydrateFromServer();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Re-hydrate the live-sharing state whenever the app comes to the
    // foreground. Dart Timers don't fire while the app is backgrounded,
    // so if a time-boxed session expired while the user was away, the
    // in-memory state is stale. A server query catches that up and
    // triggers stop() via hydrateFromServer's empty-response path.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(liveSharingProvider.notifier).hydrateFromServer();
    }
  }

  int _getCurrentIndex(String location) {
    if (location.startsWith('/sos')) return 1;
    if (location.startsWith('/contacts')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  void _handlePop(String location) {
    if (location != '/') {
      context.go('/');
      return;
    }
    final now = DateTime.now();
    if (_lastBackPressAt == null ||
        now.difference(_lastBackPressAt!) > _exitConfirmWindow) {
      _lastBackPressAt = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: _exitConfirmWindow,
          ),
        );
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _getCurrentIndex(location);
    final isTabRoot = location == '/'
        || location == '/sos'
        || location == '/contacts'
        || location == '/settings';

    return PopScope(
      canPop: !isTabRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handlePop(location);
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (index) {
            switch (index) {
              case 0:
                context.go('/');
                break;
              case 1:
                context.go('/sos');
                break;
              case 2:
                context.go('/contacts');
                break;
              case 3:
                context.go('/settings');
                break;
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.warning_amber_outlined),
              selectedIcon: Icon(Icons.warning_amber),
              label: 'SOS',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Contacts',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
