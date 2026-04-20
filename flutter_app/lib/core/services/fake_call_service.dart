import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
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

  void updateCallerInfo(String name, String number) {
    _callerName = name;
    _callerNumber = number;
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

    // Reset to idle after a short delay (guard against disposed controller)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_statusController.isClosed) {
        _updateStatus(FakeCallStatus.idle);
      }
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
    if (!_statusController.isClosed) {
      _statusController.close();
    }
  }
}
