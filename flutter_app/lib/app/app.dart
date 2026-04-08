import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import '../core/providers/sos_provider.dart';
import '../core/services/sos_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/utils/logger.dart';

class SafetyApp extends ConsumerStatefulWidget {
  const SafetyApp({super.key});

  @override
  ConsumerState<SafetyApp> createState() => _SafetyAppState();
}

class _SafetyAppState extends ConsumerState<SafetyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        _handleAppPaused();
        break;
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.inactive:
        // App is transitioning (e.g., during call) - maintain state
        break;
      case AppLifecycleState.detached:
        // App is being destroyed - cleanup will be handled by dispose
        break;
      case AppLifecycleState.hidden:
        // App window is hidden (desktop/web)
        break;
    }
  }

  /// Handle app entering background - reduce battery usage
  void _handleAppPaused() {
    AppLogger.info('App backgrounded - entering power-save mode');

    // Stop shake detection to save battery (unless SOS is actively being sent)
    final sosState = ref.read(sosProvider);
    if (sosState.status == SosStatus.idle && sosState.shakeEnabled) {
      ref.read(sosProvider.notifier).stopShakeDetection();
    }
  }

  /// Handle app returning to foreground - resume normal operations
  void _handleAppResumed() {
    AppLogger.info('App resumed - restoring normal operations');

    // Resume shake detection if it was enabled
    final sosState = ref.read(sosProvider);
    if (sosState.shakeEnabled && sosState.status == SosStatus.idle) {
      ref.read(sosProvider.notifier).startShakeDetection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Safety App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
