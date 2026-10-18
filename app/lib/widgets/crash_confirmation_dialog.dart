import 'dart:async';

import 'package:flutter/material.dart';

import 'common_widgets.dart';

class CrashConfirmationDialog extends StatefulWidget {
  final double impactMps2;

  const CrashConfirmationDialog({
    super.key,
    required this.impactMps2,
  });

  @override
  State<CrashConfirmationDialog> createState() =>
      _CrashConfirmationDialogState();
}

class _CrashConfirmationDialogState extends State<CrashConfirmationDialog>
    with WidgetsBindingObserver {
  static const _countdownDuration = Duration(minutes: 5);
  Timer? _timer;
  late DateTime _deadline;
  int _secondsRemaining = _countdownDuration.inSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deadline = DateTime.now().add(_countdownDuration);
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateCountdown());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _updateCountdown();
  }

  void _updateCountdown() {
    final remaining = _deadline.difference(DateTime.now());
    final seconds =
        remaining.isNegative ? 0 : (remaining.inMilliseconds / 1000).ceil();
    if (seconds == 0) {
      _timer?.cancel();
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    if (mounted && seconds != _secondsRemaining) {
      setState(() => _secondsRemaining = seconds);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  String get _countdownText {
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final impactG = widget.impactMps2 / 9.80665;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.car_crash_rounded, color: C.sosDark, size: 36),
        title: const Text('Possible crash detected'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'A strong phone movement was detected (${impactG.toStringAsFixed(1)} g). If you do not respond, RoadRescue will register an alert in:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Text(
              _countdownText,
              style: const TextStyle(
                color: C.sosDark,
                fontSize: 40,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Keep RoadRescue open and online. If the app closes or loses connection, automatic registration may fail. False alarms are possible; external emergency services are not connected in this prototype.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("I'm okay"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: C.sosDark),
            child: const Text('Send alert now'),
          ),
        ],
      ),
    );
  }
}
