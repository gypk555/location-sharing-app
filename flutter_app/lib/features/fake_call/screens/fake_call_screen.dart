import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/fake_call_service.dart';
import '../../../shared/theme/app_theme.dart';

final fakeCallServiceProvider = Provider<FakeCallService>((ref) {
  return FakeCallService();
});

final fakeCallStatusProvider = StreamProvider<FakeCallStatus>((ref) {
  return ref.watch(fakeCallServiceProvider).statusStream;
});

class FakeCallScreen extends ConsumerStatefulWidget {
  const FakeCallScreen({super.key});

  @override
  ConsumerState<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends ConsumerState<FakeCallScreen> {
  int _selectedDelay = 0; // 0 = immediate, or seconds

  @override
  Widget build(BuildContext context) {
    final fakeCallService = ref.watch(fakeCallServiceProvider);
    final statusAsync = ref.watch(fakeCallStatusProvider);

    return statusAsync.when(
      data: (status) {
        if (status == FakeCallStatus.ringing) {
          return _IncomingCallScreen(
            callerName: fakeCallService.callerName,
            callerNumber: fakeCallService.callerNumber,
            onAnswer: () => fakeCallService.answerCall(),
            onDecline: () => fakeCallService.declineCall(),
          );
        }

        if (status == FakeCallStatus.answered) {
          return _OnCallScreen(
            callerName: fakeCallService.callerName,
            onEndCall: () => fakeCallService.endCall(),
          );
        }

        return _ScheduleCallScreen(
          selectedDelay: _selectedDelay,
          onDelayChanged: (delay) => setState(() => _selectedDelay = delay),
          onTriggerCall: () {
            if (_selectedDelay == 0) {
              fakeCallService.triggerCall();
            } else {
              fakeCallService.scheduleCall(Duration(seconds: _selectedDelay));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Fake call scheduled in $_selectedDelay seconds'),
                ),
              );
              context.pop();
            }
          },
          status: status,
          onCancelScheduled: () => fakeCallService.cancelScheduledCall(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _ScheduleCallScreen(
        selectedDelay: _selectedDelay,
        onDelayChanged: (delay) => setState(() => _selectedDelay = delay),
        onTriggerCall: () {
          final fakeCallService = ref.read(fakeCallServiceProvider);
          if (_selectedDelay == 0) {
            fakeCallService.triggerCall();
          } else {
            fakeCallService.scheduleCall(Duration(seconds: _selectedDelay));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Fake call scheduled in $_selectedDelay seconds'),
              ),
            );
            context.pop();
          }
        },
        status: FakeCallStatus.idle,
        onCancelScheduled: () {},
      ),
    );
  }
}

class _ScheduleCallScreen extends StatelessWidget {
  final int selectedDelay;
  final Function(int) onDelayChanged;
  final VoidCallback onTriggerCall;
  final FakeCallStatus status;
  final VoidCallback onCancelScheduled;

  const _ScheduleCallScreen({
    required this.selectedDelay,
    required this.onDelayChanged,
    required this.onTriggerCall,
    required this.status,
    required this.onCancelScheduled,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fake Call'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon
            const Icon(
              Icons.phone_callback,
              size: 80,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(height: 24),

            Text(
              'Schedule a Fake Call',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Receive an incoming call to help you escape uncomfortable situations',
              style: TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Delay options
            Text(
              'When should the call come?',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DelayChip(
                  label: 'Now',
                  value: 0,
                  selectedValue: selectedDelay,
                  onSelected: onDelayChanged,
                ),
                _DelayChip(
                  label: '30 sec',
                  value: 30,
                  selectedValue: selectedDelay,
                  onSelected: onDelayChanged,
                ),
                _DelayChip(
                  label: '1 min',
                  value: 60,
                  selectedValue: selectedDelay,
                  onSelected: onDelayChanged,
                ),
                _DelayChip(
                  label: '2 min',
                  value: 120,
                  selectedValue: selectedDelay,
                  onSelected: onDelayChanged,
                ),
                _DelayChip(
                  label: '5 min',
                  value: 300,
                  selectedValue: selectedDelay,
                  onSelected: onDelayChanged,
                ),
              ],
            ),

            const Spacer(),

            if (status == FakeCallStatus.scheduled) ...[
              Card(
                color: AppTheme.warningColor.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.timer, color: AppTheme.warningColor),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Call scheduled',
                          style: TextStyle(color: AppTheme.warningColor),
                        ),
                      ),
                      TextButton(
                        onPressed: onCancelScheduled,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            ElevatedButton.icon(
              onPressed: onTriggerCall,
              icon: const Icon(Icons.phone),
              label: Text(
                selectedDelay == 0 ? 'Call Now' : 'Schedule Call',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DelayChip extends StatelessWidget {
  final String label;
  final int value;
  final int selectedValue;
  final Function(int) onSelected;

  const _DelayChip({
    required this.label,
    required this.value,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selectedValue;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
      selectedColor: AppTheme.primaryColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
      ),
    );
  }
}

class _IncomingCallScreen extends StatelessWidget {
  final String callerName;
  final String callerNumber;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const _IncomingCallScreen({
    required this.callerName,
    required this.callerNumber,
    required this.onAnswer,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            // Caller info
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey.shade800,
              child: const Icon(
                Icons.person,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              callerNumber,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Incoming call...',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
              ),
            ),

            const Spacer(),

            // Answer/Decline buttons
            Padding(
              padding: const EdgeInsets.all(48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline
                  GestureDetector(
                    onTap: onDecline,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),

                  // Answer
                  GestureDetector(
                    onTap: onAnswer,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                      child: const Icon(
                        Icons.call,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnCallScreen extends StatefulWidget {
  final String callerName;
  final VoidCallback onEndCall;

  const _OnCallScreen({
    required this.callerName,
    required this.onEndCall,
  });

  @override
  State<_OnCallScreen> createState() => _OnCallScreenState();
}

class _OnCallScreenState extends State<_OnCallScreen> {
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _seconds++);
      } else {
        timer.cancel();
      }
    });
  }

  String get _formattedTime {
    final minutes = _seconds ~/ 60;
    final secs = _seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            // Caller info
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey.shade800,
              child: const Icon(
                Icons.person,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _formattedTime,
              style: const TextStyle(
                color: Colors.green,
                fontSize: 20,
              ),
            ),

            const Spacer(),

            // Call controls
            Padding(
              padding: const EdgeInsets.all(48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: Icons.mic_off,
                    label: 'Mute',
                    onTap: () {},
                  ),
                  _CallButton(
                    icon: Icons.volume_up,
                    label: 'Speaker',
                    onTap: () {},
                  ),
                  _CallButton(
                    icon: Icons.dialpad,
                    label: 'Keypad',
                    onTap: () {},
                  ),
                ],
              ),
            ),

            // End call
            GestureDetector(
              onTap: widget.onEndCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade800,
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
