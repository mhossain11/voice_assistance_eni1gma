import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

abstract class TtsService {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
  Stream<bool> get speakingState;
  Stream<String> get errors;
  Future<void> dispose();
}

class TtsServiceException implements Exception {
  const TtsServiceException(this.message);
  final String message;
}

class NativeTtsService implements TtsService {
  NativeTtsService({FlutterTts? engine}) : _engine = engine ?? FlutterTts();

  static const _speechRate = 0.46;
  static const _pitch = 1.0;
  static const _volume = 1.0;
  final FlutterTts _engine;
  final _speakingState = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  Completer<void>? _completion;
  bool _initialized = false;
  bool _disposed = false;

  @override
  Stream<bool> get speakingState => _speakingState.stream;
  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _engine.setStartHandler(() {
        if (!_disposed) _speakingState.add(true);
      });
      _engine.setCompletionHandler(_completeSpeech);
      _engine.setCancelHandler(_completeSpeech);
      _engine.setErrorHandler((message) {
        if (!_disposed) _errors.add('Text-to-speech is unavailable.');
        _completeSpeech();
      });
      await _engine.awaitSpeakCompletion(true);
      await _engine.setSpeechRate(_speechRate);
      await _engine.setPitch(_pitch);
      await _engine.setVolume(_volume);
      // Use English if installed; otherwise retain the platform-default voice.
      final available = await _engine.isLanguageAvailable('en-US');
      if (available == 1 || available == true) {
        await _engine.setLanguage('en-US');
      }
      _initialized = true;
    } catch (_) {
      throw const TtsServiceException('Text-to-speech is unavailable.');
    }
  }

  @override
  Future<void> speak(String text) async {
    final utterance = text.trim();
    if (utterance.isEmpty) return;
    await initialize();
    if (_completion != null && !_completion!.isCompleted) return;
    _completion = Completer<void>();
    try {
      await _engine.speak(utterance);
      await _completion!.future;
    } catch (_) {
      _completeSpeech();
      throw const TtsServiceException(
        'Text-to-speech could not play the response.',
      );
    }
  }

  void _completeSpeech() {
    if (!_disposed) _speakingState.add(false);
    if (_completion != null && !_completion!.isCompleted) {
      _completion!.complete();
    }
  }

  @override
  Future<void> stop() async {
    await _engine.stop();
    _completeSpeech();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _engine.stop();
    _completeSpeech();
    await _speakingState.close();
    await _errors.close();
  }
}
