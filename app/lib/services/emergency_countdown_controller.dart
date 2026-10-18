import 'dart:async';

import 'package:flutter/foundation.dart';

class EmergencyCountdownController extends ChangeNotifier {
  EmergencyCountdownController({
    required this.countdownSeconds,
    required this.dryRun,
    required this.onCall,
    this.onDryRun,
    this.onTick,
    this.onCancel,
    this.tickInterval = const Duration(seconds: 1),
  }) : secondsRemaining = countdownSeconds;

  final int countdownSeconds;
  final bool dryRun;
  final Future<void> Function() onCall;
  final VoidCallback? onDryRun;
  final VoidCallback? onTick;
  final VoidCallback? onCancel;
  final Duration tickInterval;

  Timer? _timer;
  Completer<void>? _completion;
  bool _active = false;
  bool _paused = false;
  int secondsRemaining;

  bool get isActive => _active;
  Future<void> get completed => _completion?.future ?? Future.value();

  void start() {
    if (_active || _completion != null) return;
    _active = true;
    _completion = Completer<void>();
    notifyListeners();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  void pause() {
    if (!_active || _paused) return;
    _paused = true;
    _timer?.cancel();
  }

  void resume() {
    if (!_active || !_paused) return;
    _paused = false;
    _startTimer();
  }

  void _tick() {
    if (!_active) return;
    onTick?.call();
    secondsRemaining--;
    if (secondsRemaining <= 0) {
      secondsRemaining = 0;
      _active = false;
      _timer?.cancel();
      notifyListeners();
      unawaited(_finish());
      return;
    }
    notifyListeners();
  }

  Future<void> _finish() async {
    try {
      if (dryRun) {
        onDryRun?.call();
      } else {
        await onCall();
      }
    } finally {
      if (!(_completion?.isCompleted ?? true)) _completion!.complete();
    }
  }

  void cancel() {
    if (!_active) return;
    _active = false;
    _paused = false;
    _timer?.cancel();
    onCancel?.call();
    notifyListeners();
    if (!(_completion?.isCompleted ?? true)) _completion!.complete();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _active = false;
    _paused = false;
    if (!(_completion?.isCompleted ?? true)) _completion!.complete();
    super.dispose();
  }
}
