import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/constants/app_constants.dart';
import '../../shared/utils/logger.dart';
import '../models/location_model.dart';
import 'location_service.dart';

/// Namespaced SharedPreferences keys used to bridge state from the UI
/// isolate into the background isolate. The background isolate cannot share
/// memory with the UI isolate, so everything it needs is persisted here.
///
/// Supabase URL and anon key are deliberately NOT stored here: the
/// background isolate loads them from the bundled `.env` asset via
/// flutter_dotenv, avoiding plaintext credentials in SharedPreferences.
class _BgPrefsKeys {
  static const sessionGroupId = 'bg.session_group_id';
  static const trackingTier = 'bg.tracking_tier';
  static const recipientCount = 'bg.recipient_count';
}

/// Notification channel for the live-sharing foreground service.
/// Must match the channel created via flutter_local_notifications on the
/// UI side if we ever show non-service notifications there.
const String _notificationChannelId = 'live_sharing';
const int _notificationId = 7734; // Arbitrary stable ID for the foreground notification

/// Public API called from the UI isolate to configure and manage the
/// background service. The service itself runs in a separate isolate whose
/// entry point is [_onBackgroundStart] below.
class BackgroundService {
  BackgroundService._();

  /// Configure the service. Safe to call multiple times (subsequent calls
  /// are no-ops inside the plugin). Call once from main.dart after dotenv
  /// is loaded and Supabase is initialized on the UI side.
  static Future<void> configure() async {
    try {
      // Create the notification channel used by the foreground service.
      // flutter_background_service only configures the channel *id*; the
      // channel itself must exist on the device before any FGS tries to
      // post to it, or Android 8+ rejects the notification with
      // "invalid channel for service notification" and kills the process.
      // Must happen BEFORE service.configure() because Android may auto-
      // restart a previously-crashed service the moment this app boots.
      await _ensureNotificationChannel();

      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onBackgroundStart,
          autoStart: false, // We start explicitly when sharing begins
          isForegroundMode: true,
          notificationChannelId: _notificationChannelId,
          initialNotificationTitle: 'Safety App',
          initialNotificationContent: 'Preparing live location sharing…',
          foregroundServiceNotificationId: _notificationId,
          foregroundServiceTypes: [AndroidForegroundType.location],
        ),
        iosConfiguration: IosConfiguration(
          onForeground: _onBackgroundStart,
          onBackground: _onIosBackground,
          autoStart: false,
        ),
      );
      AppLogger.info('Background service configured');
    } catch (e, stack) {
      AppLogger.error('Background service configure failed', e, stack);
    }
  }

  /// Create the Android notification channel that backs the foreground
  /// service notification. Idempotent — Android de-dupes by channel id.
  /// No-op on iOS. Uses `low` importance so the ongoing notification
  /// doesn't make sound / pop up when a share starts.
  static Future<void> _ensureNotificationChannel() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return; // not Android
      const channel = AndroidNotificationChannel(
        _notificationChannelId,
        'Live location sharing',
        description:
            'Ongoing notification shown while your live location is being shared.',
        importance: Importance.low,
        showBadge: false,
      );
      await android.createNotificationChannel(channel);
    } catch (e, stack) {
      AppLogger.error('createNotificationChannel failed', e, stack);
    }
  }

  /// Ensure we hold the runtime POST_NOTIFICATIONS permission required on
  /// Android 13+ (API 33) before the foreground service posts its persistent
  /// notification. Without this, `startService()` succeeds but the OS kills
  /// the process with `CannotPostForegroundServiceNotificationException` the
  /// instant the FGS tries to show its ongoing notification.
  ///
  /// Returns true if the permission is granted (or not required on the
  /// current platform), false if the user declined. On older Android /
  /// iOS the plugin short-circuits to granted.
  static Future<bool> ensureNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) return false;
      final result = await Permission.notification.request();
      return result.isGranted;
    } catch (e, stack) {
      AppLogger.error('notification permission request failed', e, stack);
      return false;
    }
  }

  /// Start the background service with a session group and recipient count.
  /// The notification will display how many contacts are receiving updates.
  ///
  /// Returns true on success, false if a required runtime permission (e.g.
  /// POST_NOTIFICATIONS on Android 13+) was denied — callers should surface
  /// this to the user instead of silently crashing when the foreground
  /// service notification gets rejected.
  static Future<bool> startSharing({
    required String sessionGroupId,
    required int recipientCount,
    required TrackingTier initialTier,
  }) async {
    final granted = await ensureNotificationPermission();
    if (!granted) {
      AppLogger.warning(
          'startSharing aborted: notification permission denied');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_BgPrefsKeys.sessionGroupId, sessionGroupId);
    await prefs.setInt(_BgPrefsKeys.recipientCount, recipientCount);
    await prefs.setString(_BgPrefsKeys.trackingTier, initialTier.name);

    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    } else {
      // Already running: just tell it to refresh state
      service.invoke('refresh', {
        'sessionGroupId': sessionGroupId,
        'recipientCount': recipientCount,
        'tier': initialTier.name,
      });
    }
    return true;
  }

  /// Stop the background service gracefully. `invoke('stop')` is
  /// fire-and-forget by design of the plugin — we can't confirm the
  /// isolate processed it. A single-shot 2s check used to log a
  /// warning and give up; a stuck foreground notification then
  /// lingered indefinitely (bad UX + battery drain).
  ///
  /// We now poll `isRunning()` on an exponential-ish schedule (code-
  /// review finding §3.4) and re-send `stop` on each iteration in
  /// case the earlier message was dropped. After 3.5s total we give
  /// up and log a warning — when a crash reporter is wired this is
  /// where we'd record a non-fatal for visibility.
  static Future<void> stopSharing() async {
    // Clear the bridge-prefs BEFORE signalling stop. If Android later
    // auto-restarts the foreground service (START_STICKY +
    // stopWithTask="false"), `_onBackgroundStart` will see an empty
    // sessionGroupId and immediately stopSelf() instead of posting a
    // stale "Sharing your live location" notification.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_BgPrefsKeys.sessionGroupId);
      await prefs.remove(_BgPrefsKeys.recipientCount);
      await prefs.remove(_BgPrefsKeys.trackingTier);
    } catch (e) {
      AppLogger.error('bg: clear prefs on stop failed', e);
    }
    final service = FlutterBackgroundService();
    service.invoke('stop');
    await _confirmStopped(service);
  }

  static Future<void> _confirmStopped(FlutterBackgroundService service) async {
    const delaysMs = [500, 1000, 2000];
    for (final ms in delaysMs) {
      await Future<void>.delayed(Duration(milliseconds: ms));
      try {
        if (!await service.isRunning()) return;
      } catch (_) {
        // Plugin may throw if the channel is torn down — treat as stopped.
        return;
      }
      service.invoke('stop');
    }
    AppLogger.warning(
        'bg: stop not honored after ${delaysMs.length} retries');
    // TODO: when Crashlytics is wired, record a non-fatal here so this
    // case shows up in telemetry instead of only in debug logs.
  }

  /// Change the tracking tier (e.g. when SOS fires).
  static void setTier(TrackingTier tier) {
    final service = FlutterBackgroundService();
    service.invoke('setTier', {'tier': tier.name});
  }

  /// Stream of positions emitted by the background isolate. The UI isolate
  /// can listen to reflect the latest point on the in-app map without
  /// starting its own geolocator stream.
  static Stream<Map<String, dynamic>?> positionStream() {
    final service = FlutterBackgroundService();
    return service.on('position');
  }
}

// ===== Background isolate entry point =====================================
// Everything below runs in a SEPARATE isolate. It cannot access:
//   - Any Supabase client created in the UI isolate (must re-initialize)
//   - Any Riverpod providers / GoRouter / Flutter widgets
//   - Hive boxes opened by the UI isolate (will deadlock)
//
// The `onStart` function must be a top-level or static method annotated
// with @pragma('vm:entry-point') so the background isolate can dispatch to
// it after Dart tree-shaking.

@pragma('vm:entry-point')
Future<void> _onBackgroundStart(ServiceInstance service) async {
  // Required so platform plugins (SharedPreferences, geolocator, battery_plus)
  // can be called from this isolate.
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // Boot Supabase in this isolate. The background isolate is a separate
  // Dart VM and does not inherit the UI isolate's in-memory dotenv; we
  // re-load the bundled `.env` asset here. Session persistence is backed
  // by SharedPreferences on both platforms, so the auth session we
  // signed in with on the UI side is recovered automatically.
  String url = '';
  String anonKey = '';
  try {
    if (!dotenv.isInitialized) {
      await dotenv.load(fileName: '.env');
    }
    url = dotenv.env['SUPABASE_URL'] ?? '';
    anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  } catch (e) {
    AppLogger.error('bg: dotenv load failed', e);
  }
  SupabaseClient? supabase;
  if (url.isNotEmpty && anonKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: url, anonKey: anonKey);
      supabase = Supabase.instance.client;
      AppLogger.info('bg: Supabase initialized in background isolate');
    } catch (e) {
      // If the OS auto-restarted the foreground service inside the
      // same isolate, Supabase.initialize will throw "already
      // initialized" — fall back to the existing singleton instead
      // of crashing the isolate silently.
      try {
        supabase = Supabase.instance.client;
        AppLogger.info('bg: reusing existing Supabase client');
      } catch (_) {
        AppLogger.error('bg: Supabase init failed', e);
      }
    }
  }

  // Mark LocationService as background-isolate-aware so it skips geocoding
  // and local Hive writes.
  final locationService = LocationService();
  locationService.markAsBackgroundIsolate();

  // Read session state
  var sessionGroupId = prefs.getString(_BgPrefsKeys.sessionGroupId) ?? '';
  var recipientCount = prefs.getInt(_BgPrefsKeys.recipientCount) ?? 0;
  final tierName = prefs.getString(_BgPrefsKeys.trackingTier) ?? 'normal';
  TrackingTier tier = TrackingTier.values.firstWhere(
    (t) => t.name == tierName,
    orElse: () => TrackingTier.normal,
  );

  // If this is an OS-driven restart (START_STICKY + stopWithTask="false")
  // after the user explicitly stopped sharing, the bridge-prefs were
  // cleared in stopSharing() and we must not run or post the persistent
  // notification — the user would see "Sharing your live location" with
  // no matching DB rows. Bail out before wiring heartbeats/listeners.
  if (sessionGroupId.isEmpty) {
    AppLogger.info('bg: no active session in prefs, stopping restarted service');
    await service.stopSelf();
    return;
  }

  // Update the persistent notification with recipient count.
  Future<void> updateNotification() async {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Sharing your live location',
        content: recipientCount > 0
            ? 'With $recipientCount ${recipientCount == 1 ? 'contact' : 'contacts'}'
            : 'Preparing…',
      );
    }
  }

  await updateNotification();

  // Sink that writes each position to Supabase.
  Future<void> writePositionToSupabase(LocationModel loc) async {
    if (supabase == null) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase.from('location_history').insert({
        'user_id': user.id,
        'latitude': loc.latitude,
        'longitude': loc.longitude,
        'accuracy': loc.accuracy,
        'altitude': loc.altitude,
        'speed': loc.speed,
        'heading': loc.heading,
        'address': loc.address,
        'is_sos_location': tier == TrackingTier.emergency,
      });

      // Emit to UI isolate so the in-app map can mirror the point.
      service.invoke('position', {
        'latitude': loc.latitude,
        'longitude': loc.longitude,
        'accuracy': loc.accuracy,
        'speed': loc.speed,
        'heading': loc.heading,
        'timestamp': loc.timestamp.toIso8601String(),
      });
    } catch (e) {
      AppLogger.error('bg: write position failed', e);
    }
  }

  locationService.addSink(writePositionToSupabase);

  // Start position stream at the requested tier.
  await locationService.setTier(tier);
  await locationService.startTracking();

  // Heartbeat: every 60s update last_heartbeat_at on active rows for this session.
  Timer? heartbeatTimer;
  heartbeatTimer = Timer.periodic(AppConstants.kHeartbeatInterval, (_) async {
    if (supabase == null || sessionGroupId.isEmpty) return;
    try {
      await supabase
          .from('location_sharing')
          .update({'last_heartbeat_at': DateTime.now().toUtc().toIso8601String()})
          .eq('session_group_id', sessionGroupId)
          .eq('is_active', true);
    } catch (e) {
      AppLogger.error('bg: heartbeat failed', e);
    }
  });

  // Listen for commands from the UI isolate. Subscriptions are captured so
  // they can be cancelled in the 'stop' handler — otherwise a stop→start
  // cycle (OS-driven restart) would accumulate duplicate listeners and
  // process each tick N times on the second and subsequent sessions.
  final setTierSub = service.on('setTier').listen((event) async {
    final name = event?['tier'] as String? ?? 'normal';
    final newTier = TrackingTier.values.firstWhere(
      (t) => t.name == name,
      orElse: () => TrackingTier.normal,
    );
    tier = newTier;
    await locationService.setTier(newTier);
  });

  final refreshSub = service.on('refresh').listen((event) async {
    sessionGroupId = event?['sessionGroupId'] as String? ?? sessionGroupId;
    recipientCount = (event?['recipientCount'] as int?) ?? recipientCount;
    final newTierName = event?['tier'] as String?;
    if (newTierName != null) {
      tier = TrackingTier.values.firstWhere(
        (t) => t.name == newTierName,
        orElse: () => tier,
      );
      await locationService.setTier(tier);
    }
    await updateNotification();
  });

  // stopSelf() tears down the isolate, so anything after it (including
  // cancelling this very subscription) is effectively unreachable —
  // that's fine, because a fresh _onBackgroundStart gets its own set of
  // subscriptions anyway.
  service.on('stop').listen((event) async {
    heartbeatTimer?.cancel();
    await setTierSub.cancel();
    await refreshSub.cancel();
    locationService.removeSink(writePositionToSupabase);
    locationService.stopTracking();
    await service.stopSelf();
  });
}

/// iOS background handler. Called briefly when iOS wakes the app for
/// background fetch. iOS background execution is much more limited than
/// Android: we do NOT run a continuous stream here. Continuous background
/// location on iOS is handled by the `UIBackgroundModes: location` flag
/// combined with a live subscription in the UI isolate (which keeps
/// running while the app is in the background).
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}
