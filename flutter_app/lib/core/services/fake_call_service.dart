import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_preferences_provider.dart'
    show kFakeCallerNamePrefKey, kFakeCallerNumberPrefKey;
import '../../shared/utils/logger.dart';

enum FakeCallStatus {
  idle,
  scheduled,
  ringing,
  answered,
  ended,
}

class FakeCallService {
  static final FakeCallService _instance = FakeCallService._internal();
  factory FakeCallService() => _instance;
  FakeCallService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final _statusController = StreamController<FakeCallStatus>.broadcast();

  Stream<FakeCallStatus> get statusStream => _statusController.stream;

  FakeCallStatus _currentStatus = FakeCallStatus.idle;
  FakeCallStatus get currentStatus => _currentStatus;

  Timer? _scheduledCallTimer;
  String _callerName = 'Mom';
  String _callerNumber = '+1 234 567 8900';

  String get callerName => _callerName;
  String get callerNumber => _callerNumber;

  /// Hydrate caller info from SharedPreferences. Call once from main.dart.
  Future<void> loadPersistedCallerInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(kFakeCallerNamePrefKey);
      final number = prefs.getString(kFakeCallerNumberPrefKey);
      if (name != null && name.isNotEmpty) _callerName = name;
      if (number != null && number.isNotEmpty) _callerNumber = number;
    } catch (e) {
      AppLogger.debug('FakeCallService: could not load caller info: $e');
    }
  }

  Future<void> setCallerInfo(String name, String number) async {
    _callerName = name;
    _callerNumber = number;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kFakeCallerNamePrefKey, name);
      await prefs.setString(kFakeCallerNumberPrefKey, number);
    } catch (e) {
      AppLogger.debug('FakeCallService: could not persist caller info: $e');
    }
  }

  void scheduleCall(Duration delay) {
    _scheduledCallTimer?.cancel();
    _updateStatus(FakeCallStatus.scheduled);

    _scheduledCallTimer = Timer(delay, () {
      triggerCall();
    });
  }

  void cancelScheduledCall() {
    _scheduledCallTimer?.cancel();
    _scheduledCallTimer = null;
    _updateStatus(FakeCallStatus.idle);
  }

  Future<void> triggerCall() async {
    _updateStatus(FakeCallStatus.ringing);

    try {
      // Play ringtone
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('sounds/ringtone.mp3'));
    } catch (e) {
      AppLogger.debug('Error playing ringtone: $e');
      // Continue even if audio fails
    }
  }

  Future<void> answerCall() async {
    await _audioPlayer.stop();
    _updateStatus(FakeCallStatus.answered);

    try {
      // Play fake conversation audio
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(AssetSource('sounds/fake_conversation.mp3'));
    } catch (e) {
      AppLogger.debug('Error playing conversation: $e');
    }
  }

  Future<void> endCall() async {
    await _audioPlayer.stop();
    _updateStatus(FakeCallStatus.ended);

    // Reset to idle after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      _updateStatus(FakeCallStatus.idle);
    });
  }

  Future<void> declineCall() async {
    await _audioPlayer.stop();
    _updateStatus(FakeCallStatus.idle);
  }

  void _updateStatus(FakeCallStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  void dispose() {
    _scheduledCallTimer?.cancel();
    _audioPlayer.dispose();
    _statusController.close();
  }
}
