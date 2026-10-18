import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/driving_voice_service.dart';
import '../widgets/common_widgets.dart';

class DrivingVoiceModeSheet extends StatefulWidget {
  final ValueChanged<int> onNavigate;

  const DrivingVoiceModeSheet({super.key, required this.onNavigate});

  @override
  State<DrivingVoiceModeSheet> createState() => _DrivingVoiceModeSheetState();
}

class _DrivingVoiceModeSheetState extends State<DrivingVoiceModeSheet> {
  final _voice = DrivingVoiceService.instance;
  StreamSubscription<DrivingVoiceEvent>? _subscription;
  String _transcript = '';
  String _message = 'Tap the microphone and say a screen name.';
  bool _listening = false;
  bool _busy = false;
  bool _openSettings = false;

  @override
  void initState() {
    super.initState();
    _subscription = _voice.events.listen(_onVoiceEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_voice.isListening) _voice.stop();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_busy) return;
    if (_voice.isListening) {
      await _voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    setState(() {
      _busy = true;
      _message = 'Requesting microphone access…';
      _openSettings = false;
      _transcript = '';
    });

    try {
      final permissionGranted = await _requestPermissions();
      if (!permissionGranted) return;

      final available = await _voice.listen();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _listening = available && _voice.isListening;
        _message = available
            ? 'Listening for one short command…'
            : 'Speech recognition is unavailable on this device.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _listening = false;
        _message = 'Could not start voice recognition. Try again.';
      });
    }
  }

  Future<void> _closeVoiceMode() async {
    final navigator = Navigator.of(context);
    await _voice.stop();
    if (!mounted) return;
    navigator.pop();
  }

  Future<bool> _requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.microphone.request();
      if (status.isGranted) return true;
      if (!mounted) return false;
      setState(() {
        _busy = false;
        _openSettings = status.isPermanentlyDenied || status.isRestricted;
        _message = _openSettings
            ? 'Microphone access is blocked. Enable it in app settings.'
            : 'Allow microphone access to use voice commands.';
      });
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final statuses =
          await [Permission.microphone, Permission.speech].request();
      final granted = statuses.values.every((status) => status.isGranted);
      if (granted) return true;
      if (!mounted) return false;
      final blocked = statuses.values.any(
        (status) => status.isPermanentlyDenied || status.isRestricted,
      );
      setState(() {
        _busy = false;
        _openSettings = blocked;
        _message = blocked
            ? 'Speech or microphone access is blocked. Enable it in app settings.'
            : 'Allow speech recognition and microphone access to use voice commands.';
      });
      return false;
    }

    if (!mounted) return false;
    setState(() {
      _busy = false;
      _message = 'Driving voice mode is available on Android and iOS.';
    });
    return false;
  }

  void _onVoiceEvent(DrivingVoiceEvent event) {
    if (!mounted) return;
    if (event.error != null) {
      setState(() {
        _busy = false;
        _listening = false;
        _message = 'Voice recognition error: ${event.error}';
      });
      return;
    }

    if (event.status != null) {
      setState(() {
        _listening = event.status == 'listening';
        if (event.status == 'done' || event.status == 'notListening') {
          _busy = false;
          if (_transcript.isEmpty) {
            _message = 'No command heard. Tap to try again.';
          }
        }
      });
    }

    final result = event.result;
    if (result == null) return;
    setState(() => _transcript = result.recognizedWords);
    if (result.finalResult) _handleCommand(result.recognizedWords);
  }

  Future<void> _handleCommand(String words) async {
    final command = words
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (command.contains('stop listening') || command == 'stop') {
      await _voice.stop();
      if (mounted) {
        setState(() {
          _listening = false;
          _message = 'Voice listening stopped.';
        });
      }
      return;
    }

    if (command.contains('close voice') || command.contains('exit driving')) {
      await _voice.stop();
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    final destination = command.contains('emergency') || command.contains('sos')
        ? 0
        : command.contains('safety')
            ? 1
            : command.contains('mechanic')
                ? 2
                : null;

    if (destination == null) {
      setState(() {
        _listening = false;
        _message = 'Say “emergency”, “safety”, or “mechanics”.';
      });
      return;
    }

    await _voice.stop();
    widget.onNavigate(destination);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.directions_car_filled_rounded,
                    color: C.navy, size: 26),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Driving voice mode',
                      style: TextStyle(
                          color: C.dark,
                          fontSize: 21,
                          fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Close voice mode',
                  onPressed: _closeVoiceMode,
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              const SizedBox(height: 10),
              const Text(
                'Use short commands while the app is open. Voice mode listens only after you tap the microphone; it is not always listening.',
                style: TextStyle(color: Colors.black54, height: 1.45),
              ),
              const SizedBox(height: 16),
              const Text('Commands',
                  style: TextStyle(color: C.dark, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                  '“Emergency”, “Safety”, “Mechanics”, or “Stop listening”.',
                  style: TextStyle(color: Colors.black54, height: 1.4)),
              const Spacer(),
              Center(
                child: Semantics(
                  button: true,
                  label: _listening ? 'Stop listening' : 'Start listening',
                  child: SizedBox.square(
                    dimension: 144,
                    child: FilledButton(
                      onPressed: _busy ? null : _toggleListening,
                      style: FilledButton.styleFrom(
                        backgroundColor: _listening ? C.sosDark : C.navy,
                        shape: const CircleBorder(),
                      ),
                      child: _busy
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Icon(
                              _listening
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: C.dark, fontWeight: FontWeight.w600, height: 1.4),
              ),
              if (_transcript.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Heard: “$_transcript”',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54)),
              ],
              if (_openSettings)
                TextButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Open Settings'),
                ),
              const Spacer(),
              const Text(
                'Keep your attention on the road. Pull over before using the screen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
