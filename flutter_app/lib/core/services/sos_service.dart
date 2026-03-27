import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'location_service.dart';
import 'sms_service.dart';
import '../models/contact_model.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/logger.dart';

enum SosStatus {
  idle,
  countdown,
  triggered,
  sending,
  sent,
  failed,
}

class SosService {
  static final SosService _instance = SosService._internal();
  factory SosService() => _instance;
  SosService._internal();

  final LocationService _locationService = LocationService();
  final SmsService _smsService = SmsService();

  StreamSubscription<AccelerometerEvent>? _shakeSubscription;
  final _sosStatusController = StreamController<SosStatus>.broadcast();
  final _countdownController = StreamController<int>.broadcast();

  Stream<SosStatus> get sosStatusStream => _sosStatusController.stream;
  Stream<int> get countdownStream => _countdownController.stream;

  SosStatus _currentStatus = SosStatus.idle;
  SosStatus get currentStatus => _currentStatus;

  Timer? _countdownTimer;
  int _shakeCount = 0;
  DateTime? _lastShakeTime;

  bool _isShakeEnabled = true;
  int _countdownSeconds = 5;

  void setShakeEnabled(bool enabled) {
    _isShakeEnabled = enabled;
    if (enabled) {
      startShakeDetection();
    } else {
      stopShakeDetection();
    }
  }

  void setCountdownSeconds(int seconds) {
    _countdownSeconds = seconds;
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

      // Send SOS SMS
      await _smsService.sendSosAlert(
        contacts: contacts,
        location: location,
      );

      _updateStatus(SosStatus.sent);

      // Reset to idle after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        _updateStatus(SosStatus.idle);
      });
    } catch (e) {
      AppLogger.error('SOS Error', e);
      _updateStatus(SosStatus.failed);

      // Reset to idle after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        _updateStatus(SosStatus.idle);
      });
    }
  }

  Future<List<ContactModel>> _getSosContacts() async {
    try {
      final box =
          await Hive.openBox<ContactModel>(AppConstants.contactsBoxName);
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
    _shakeSubscription?.cancel();
    _countdownTimer?.cancel();
    _sosStatusController.close();
    _countdownController.close();
  }
}
