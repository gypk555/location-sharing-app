import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';
import 'secure_hive.dart';
import 'sms_service.dart';
import '../models/contact_model.dart';
import '../providers/app_preferences_provider.dart' show kSosTemplatePrefKey;
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/logger.dart';

enum SosStatus {
  idle,
  countdown,
  triggered,
  sending,
  sent,
  partiallySent, // Some contacts received SOS, but not all
  failed,
}

class SosService {
  static final SosService _instance = SosService._internal();
  factory SosService() => _instance;
  SosService._internal();

  final LocationService _locationService = LocationService();
  final SmsService _smsService = SmsService();

  // Cache Hive box to avoid repeated openBox() calls (performance optimization)
  Box<ContactModel>? _contactsBox;

  StreamSubscription<AccelerometerEvent>? _shakeSubscription;
  final _sosStatusController = StreamController<SosStatus>.broadcast();
  final _countdownController = StreamController<int>.broadcast();

  Stream<SosStatus> get sosStatusStream => _sosStatusController.stream;
  Stream<int> get countdownStream => _countdownController.stream;

  SosStatus _currentStatus = SosStatus.idle;
  SosStatus get currentStatus => _currentStatus;

  Timer? _countdownTimer;
  Timer? _resetTimer;
  int _shakeCount = 0;
  DateTime? _lastShakeTime;

  bool _isShakeEnabled = true;
  int _countdownSeconds = 5;
  String? _sosTemplateOverride;

  static const _prefShakeEnabled = 'sos_shake_enabled';
  static const _prefCountdownSeconds = 'sos_countdown_seconds';

  bool get shakeEnabled => _isShakeEnabled;
  int get countdownSeconds => _countdownSeconds;

  /// Called by AppPreferencesNotifier whenever the user edits the SOS
  /// template so the hot path (_triggerSos) can read a cached field
  /// instead of awaiting SharedPreferences on every alert.
  void updateSosTemplateOverride(String? template) {
    _sosTemplateOverride = template;
  }

  /// Loads persisted SOS preferences. Must be awaited from main.dart before
  /// any provider reads service state, otherwise the notifier seeds with
  /// static defaults and the user's choices appear to reset on every launch.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isShakeEnabled = prefs.getBool(_prefShakeEnabled) ?? _isShakeEnabled;
      _countdownSeconds =
          prefs.getInt(_prefCountdownSeconds) ?? _countdownSeconds;
      _sosTemplateOverride = prefs.getString(kSosTemplatePrefKey);
    } catch (e) {
      AppLogger.debug('SosService: could not load prefs: $e');
    }
  }

  Future<void> setShakeEnabled(bool enabled) async {
    _isShakeEnabled = enabled;
    if (enabled) {
      startShakeDetection();
    } else {
      stopShakeDetection();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefShakeEnabled, enabled);
    } catch (e) {
      AppLogger.debug('SosService: could not persist shake flag: $e');
    }
  }

  Future<void> setCountdownSeconds(int seconds) async {
    _countdownSeconds = seconds;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefCountdownSeconds, seconds);
    } catch (e) {
      AppLogger.debug('SosService: could not persist countdown: $e');
    }
  }

  void startShakeDetection() {
    if (!_isShakeEnabled) return;

    _shakeSubscription?.cancel();
    _shakeSubscription = accelerometerEventStream().listen((event) {
      final acceleration =
          event.x.abs() + event.y.abs() + event.z.abs() - 9.81; // Remove gravity

      if (acceleration > AppConstants.shakeThreshold) {
        _handleShake();
      }
    });
  }

  void stopShakeDetection() {
    _shakeSubscription?.cancel();
    _shakeSubscription = null;
  }

  void _handleShake() {
    final now = DateTime.now();

    if (_lastShakeTime != null) {
      final diff = now.difference(_lastShakeTime!).inMilliseconds;
      if (diff > AppConstants.shakeTimeWindowMs) {
        _shakeCount = 0;
      }
    }

    _shakeCount++;
    _lastShakeTime = now;

    if (_shakeCount >= AppConstants.shakeCountToTrigger) {
      _shakeCount = 0;
      triggerSosWithCountdown();
    }
  }

  Future<void> triggerSosWithCountdown() async {
    if (_currentStatus == SosStatus.countdown ||
        _currentStatus == SosStatus.sending) {
      return;
    }

    _updateStatus(SosStatus.countdown);

    int remaining = _countdownSeconds;
    _countdownController.add(remaining);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining--;
      _countdownController.add(remaining);

      if (remaining <= 0) {
        timer.cancel();
        _triggerSos();
      }
    });
  }

  void cancelSos() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _updateStatus(SosStatus.idle);
    _countdownController.add(_countdownSeconds);
  }

  Future<void> triggerSosImmediately() async {
    _countdownTimer?.cancel();
    await _triggerSos();
  }

  Future<void> _triggerSos() async {
    _updateStatus(SosStatus.triggered);

    try {
      _updateStatus(SosStatus.sending);

      // Get current location
      final location = await _locationService.getCurrentLocation();
      if (location == null) {
        AppLogger.warning('Could not get location for SOS');
        _updateStatus(SosStatus.failed);
        return;
      }

      // Get SOS contacts
      final contacts = await _getSosContacts();
      if (contacts.isEmpty) {
        AppLogger.warning('No SOS contacts configured');
        _updateStatus(SosStatus.failed);
        return;
      }

      // Send SOS SMS (one to each contact). The template cache is
      // populated by init() and refreshed via updateSosTemplateOverride
      // whenever the user saves in Settings — no awaits on the hot path.
      final sentCount = await _smsService.sendSosAlert(
        contacts: contacts,
        location: location,
        customMessage: _sosTemplateOverride,
      );

      // Track send status: success, partial, or failure
      if (sentCount == contacts.length) {
        // All contacts received the SOS alert
        _updateStatus(SosStatus.sent);
        AppLogger.info('SOS sent to all $sentCount contacts');
      } else if (sentCount > 0) {
        // Only some contacts received the SOS alert
        _updateStatus(SosStatus.partiallySent);
        AppLogger.warning('SOS sent to $sentCount/${contacts.length} contacts');
      } else {
        // No contacts received the SOS alert
        _updateStatus(SosStatus.failed);
        AppLogger.error('SOS failed to send to any contacts');
      }

      // Reset to idle after 3 seconds (use Timer instead of Future.delayed so it can be cancelled)
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(seconds: 3), () {
        // Check if controller is still open before updating status
        if (!_sosStatusController.isClosed) {
          _updateStatus(SosStatus.idle);
        }
      });
    } catch (e) {
      AppLogger.error('SOS Error', e);
      _updateStatus(SosStatus.failed);

      // Reset to idle after 3 seconds (use Timer instead of Future.delayed so it can be cancelled)
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(seconds: 3), () {
        // Check if controller is still open before updating status
        if (!_sosStatusController.isClosed) {
          _updateStatus(SosStatus.idle);
        }
      });
    }
  }

  /// Get cached Hive box, opening it if necessary (performance: avoid reopening on every operation)
  Future<Box<ContactModel>> _getContactsBox() async {
    // Check if cached box is still open
    if (_contactsBox != null && _contactsBox!.isOpen) {
      return _contactsBox!;
    }

    // Try to get existing open box before creating new one
    try {
      if (Hive.isBoxOpen(AppConstants.contactsBoxName)) {
        _contactsBox = Hive.box<ContactModel>(AppConstants.contactsBoxName);
        return _contactsBox!;
      }
    } catch (e) {
      AppLogger.debug('Box not open in registry, opening new instance');
    }

    // Open new box if not already open
    _contactsBox = await SecureHive.openBox<ContactModel>(AppConstants.contactsBoxName);
    return _contactsBox!;
  }

  Future<List<ContactModel>> _getSosContacts() async {
    try {
      final box = await _getContactsBox();
      return box.values.where((c) => c.isSosContact).toList();
    } catch (e) {
      AppLogger.error('Error getting SOS contacts', e);
      return [];
    }
  }

  void _updateStatus(SosStatus status) {
    _currentStatus = status;
    _sosStatusController.add(status);
  }

  void dispose() {
    // Cancel all subscriptions and timers
    _shakeSubscription?.cancel();
    _shakeSubscription = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _resetTimer?.cancel();
    _resetTimer = null;

    // Close stream controllers safely (check if already closed)
    if (!_sosStatusController.isClosed) {
      _sosStatusController.close();
    }
    if (!_countdownController.isClosed) {
      _countdownController.close();
    }

    // DON'T close the Hive box - it's shared across the app via singleton pattern
    // Closing it here would cause crashes in other parts of the app that still
    // reference this box. Just clear our cached reference.
    _contactsBox = null;
  }
}
