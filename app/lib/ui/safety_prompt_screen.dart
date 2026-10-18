import 'package:flutter/material.dart';

import '../logic/crash_controller.dart';
import '../services/crash_notification_service.dart';

class SafetyPromptScreen extends StatefulWidget {
  const SafetyPromptScreen({super.key});

  @override
  State<SafetyPromptScreen> createState() => _SafetyPromptScreenState();
}

class _SafetyPromptScreenState extends State<SafetyPromptScreen> {
  final _controller = CrashController.instance;

  bool get _alertAttempted => _controller.state == CrashState.alertSent;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    _controller.sync();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmOkay() async {
    _controller.cancelAlert();
    try {
      await CrashNotificationService.instance.clearCrashPrompt();
    } catch (error) {
      debugPrint('Clearing crash prompt notification failed: $error');
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _dismissAlert() async {
    try {
      await CrashNotificationService.instance.clearCrashPrompt();
    } catch (error) {
      debugPrint('Clearing crash prompt notification failed: $error');
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _sendTestFalseAlarm() async {
    _controller.sendTestFalseAlarm();
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alertAttempted = _alertAttempted;
    final dispatching = _controller.isDispatching;
    final error = _controller.alertError;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFB00020),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.car_crash_rounded,
                      color: Colors.white, size: 88),
                  const SizedBox(height: 24),
                  Text(
                    dispatching
                        ? 'Sending emergency alerts'
                        : alertAttempted
                            ? _controller.isTestMode
                                ? 'TEST alert attempt completed'
                                : 'Alert attempt completed'
                            : 'Crash detected',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    dispatching
                        ? 'RoadRescue is attempting to notify your contacts.'
                        : alertAttempted
                            ? 'RoadRescue attempted to notify your contacts. This is not a guarantee that help has been dispatched.'
                            : 'Are you OK?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                  ),
                  if (!alertAttempted) ...[
                    const SizedBox(height: 28),
                    Text(
                      '${_controller.secondsRemaining}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 64,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Emergency contacts will be alerted when the timer ends.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                  if (dispatching) ...[
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(color: Colors.white),
                  ],
                  if (error case final message?) ...[
                    const SizedBox(height: 20),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                  if (_controller.testError case final testMessage?) ...[
                    const SizedBox(height: 16),
                    Text(
                      testMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 72,
                    child: FilledButton(
                      onPressed: dispatching
                          ? null
                          : alertAttempted
                              ? _controller.testAlertSent
                                  ? _sendTestFalseAlarm
                                  : _dismissAlert
                              : _confirmOkay,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFB00020),
                        textStyle: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: Text(
                        alertAttempted
                            ? _controller.testAlertSent
                                ? 'FALSE ALARM (TEST)'
                                : 'DISMISS'
                            : "I'M OK",
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Safety aid only — sensor or network failures may prevent an alert.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
