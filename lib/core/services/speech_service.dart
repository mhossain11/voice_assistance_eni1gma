import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

abstract class SpeechService {
  Future<void> initialize();
  Future<void> startListening();
  Future<void> stopListening();
  Stream<String> get recognizedText;
  Stream<String> get finalRecognizedText;
  Stream<bool> get listeningState;
  Stream<String> get errors;
  Future<void> dispose();
}

class SpeechServiceException implements Exception {
  const SpeechServiceException(this.message);
  final String message;
}

/// Short-response STT backed by Android's installed recognition service.
class NativeSpeechService implements SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final _recognizedText = StreamController<String>.broadcast();
  final _finalRecognizedText = StreamController<String>.broadcast();
  final _listeningState = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  bool _initialized = false;
  bool _disposed = false;

  @override
  Stream<String> get recognizedText => _recognizedText.stream;
  @override
  Stream<String> get finalRecognizedText => _finalRecognizedText.stream;
  @override
  Stream<bool> get listeningState => _listeningState.stream;
  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    final available = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onError,
      finalTimeout: const Duration(seconds: 2),
    );
    if (!available) {
      throw const SpeechServiceException(
        'Speech recognition is unavailable or permission was denied.',
      );
    }
    _initialized = true;
  }

  @override
  Future<void> startListening() async {
    await initialize();
    if (_speech.isListening) return;
    debugPrint('[STT] session started');
    await _speech.listen(
      onResult: _onResult,
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
        partialResults: true,
        listenMode: stt.ListenMode.confirmation,
      ),
    );
    _listeningState.add(_speech.isListening);
  }

  @override
  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    } else {
      await _speech.cancel();
    }
    debugPrint('[STT] session stopped');
    if (!_disposed) _listeningState.add(false);
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!_disposed && result.recognizedWords.trim().isNotEmpty) {
      final text = result.recognizedWords.trim();
      _recognizedText.add(text);
      if (result.finalResult) _finalRecognizedText.add(text);
    }
  }

  void _onStatus(String status) {
    if (_disposed) return;
    _listeningState.add(status == 'listening');
  }

  void _onError(SpeechRecognitionError error) {
    if (!_disposed) {
      debugPrint('[STT] error=${error.errorMsg}');
      _errors.add(error.errorMsg);
      _listeningState.add(false);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _speech.cancel();
    await _recognizedText.close();
    await _finalRecognizedText.close();
    await _listeningState.close();
    await _errors.close();
  }
}
