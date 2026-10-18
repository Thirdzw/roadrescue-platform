import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class DrivingVoiceEvent {
  final String? status;
  final String? error;
  final SpeechRecognitionResult? result;

  const DrivingVoiceEvent({this.status, this.error, this.result});
}

class DrivingVoiceService {
  DrivingVoiceService._();

  static final instance = DrivingVoiceService._();

  final SpeechToText _speech = SpeechToText();
  final StreamController<DrivingVoiceEvent> _events =
      StreamController<DrivingVoiceEvent>.broadcast();
  bool _initialized = false;
  bool _available = false;

  Stream<DrivingVoiceEvent> get events => _events.stream;
  bool get isListening => _speech.isListening;

  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;
    _available = await _speech.initialize(
      onStatus: (status) => _events.add(DrivingVoiceEvent(status: status)),
      onError: (error) => _events.add(DrivingVoiceEvent(error: error.errorMsg)),
    );
    return _available;
  }

  Future<bool> listen() async {
    if (!await initialize()) return false;
    await _speech.listen(
      onResult: (result) => _events.add(DrivingVoiceEvent(result: result)),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        cancelOnError: true,
        partialResults: true,
      ).copyWith(
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
      ),
    );
    return true;
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();
}
