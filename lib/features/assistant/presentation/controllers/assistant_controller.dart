import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/models/conversation_manager.dart';
import '../../../../core/services/ai_service.dart';
import '../../../../core/services/speech_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/services/wake_word_service.dart';
import '../../domain/entities/assistant_state.dart';
import '../../domain/utils/sleep_command_detector.dart';

/// Sleeping owns the mic through wake-word capture; listening owns it through
/// platform STT; thinking has no microphone owner.
class AssistantController {
  AssistantController(
    this._wakeWordService,
    this._speechService,
    this._aiService,
    this._ttsService,
  );

  final WakeWordService _wakeWordService;
  final SpeechService _speechService;
  final AIService _aiService;
  final TtsService _ttsService;
  final ConversationManager conversation = ConversationManager();
  final ValueNotifier<AssistantState> state = ValueNotifier(
    AssistantState.sleeping,
  );
  final ValueNotifier<String> currentTranscript = ValueNotifier('');
  final ValueNotifier<String> currentResponse = ValueNotifier('');
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  StreamSubscription<void>? _wakeWordSubscription;
  StreamSubscription<String>? _wakeWordErrorSubscription;
  StreamSubscription<String>? _recognizedTextSubscription;
  StreamSubscription<String>? _finalTextSubscription;
  StreamSubscription<bool>? _speechListeningSubscription;
  StreamSubscription<String>? _speechErrorSubscription;
  StreamSubscription<String>? _ttsErrorSubscription;
  bool _initialized = false;
  bool _disposed = false;
  bool _isProcessingRequest = false;
  bool _sessionActive = false;
  int _sessionGeneration = 0;
  bool _wakeWordRunning = false;
  bool _recoveringSpeech = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    debugPrint('[ENIGMA] Assistant initialized');
    _setState(AssistantState.sleeping);
    try {
      await _wakeWordService.initialize();
      await _speechService.initialize();
      await _ttsService.initialize();
      _wakeWordSubscription = _wakeWordService.wakeWordDetected.listen(
        (_) => onWakeWordDetected(),
        onError: (Object error) => _setError(error.toString()),
      );
      _wakeWordErrorSubscription = _wakeWordService.errors.listen(_setError);
      _recognizedTextSubscription = _speechService.recognizedText.listen((
        text,
      ) {
        if (_sessionActive && !_disposed) currentTranscript.value = text;
      });
      _finalTextSubscription = _speechService.finalRecognizedText.listen(
        _handleFinalTranscript,
      );
      _speechListeningSubscription = _speechService.listeningState.listen(
        (listening) => debugPrint('[STT] Listening: $listening'),
      );
      _speechErrorSubscription = _speechService.errors.listen(
        _handleSpeechError,
      );
      _ttsErrorSubscription = _ttsService.errors.listen(_setError);
      await startSleepingMode();
    } catch (error) {
      _setError(_messageFor(error));
    }
  }

  Future<void> startSleepingMode() async {
    await sleepAssistant(clearSession: false);
  }

  /// Ends the active session before returning microphone ownership to wake-word.
  Future<void> sleepAssistant({bool clearSession = true}) async {
    if (_disposed) return;
    if (!_sessionActive &&
        state.value == AssistantState.sleeping &&
        _wakeWordRunning) {
      return;
    }
    _sessionActive = false;
    _sessionGeneration++;
    _isProcessingRequest = false;
    await _ttsService.stop();
    await _speechService.stopListening();
    if (_sessionActive || _disposed) return;
    currentTranscript.value = '';
    if (clearSession) {
      currentResponse.value = '';
      conversation.clear();
    }
    try {
      await _wakeWordService.start();
      if (!_disposed) {
        _wakeWordRunning = true;
        _setState(AssistantState.sleeping);
      }
    } catch (error) {
      if (!_disposed) _setError(_messageFor(error));
    }
  }

  Future<void> onWakeWordDetected() async {
    if (_disposed || state.value != AssistantState.sleeping) return;
    debugPrint('[ENIGMA] Wake word detected');
    await _wakeWordService.stop();
    _wakeWordRunning = false;
    _sessionActive = true;
    _sessionGeneration++;
    currentTranscript.value = '';
    currentResponse.value = '';
    _setState(AssistantState.listening);
    try {
      await _startActiveSpeechListening();
    } catch (error) {
      _setError(_messageFor(error));
    }
  }

  Future<void> _handleFinalTranscript(String text) async {
    final normalized = text.trim();
    if (_disposed ||
        !_sessionActive ||
        _isProcessingRequest ||
        normalized.isEmpty ||
        state.value != AssistantState.listening) {
      return;
    }
    final generation = _sessionGeneration;
    if (isSleepCommand(normalized)) {
      await sleepAssistant();
      return;
    }
    _isProcessingRequest = true;
    currentTranscript.value = normalized;
    conversation.addUserMessage(normalized);
    // Thinking owns no microphone: release Android SpeechRecognizer before HTTP work.
    await _speechService.stopListening();
    if (!_isCurrentSession(generation)) return;
    _setState(AssistantState.thinking);
    try {
      final history = conversation.messages.sublist(
        0,
        conversation.messages.length - 1,
      );
      final response = await _aiService.ask(
        message: normalized,
        history: history,
      );
      if (!_isCurrentSession(generation) ||
          state.value != AssistantState.thinking) {
        return;
      }
      currentResponse.value = response;
      conversation.addAssistantMessage(response);
      _setState(AssistantState.speaking);
      await _ttsService.speak(response);
      if (!_isCurrentSession(generation) ||
          state.value != AssistantState.speaking) {
        return;
      }
      _setState(AssistantState.listening);
      await _startActiveSpeechListening();
    } catch (error) {
      if (_isCurrentSession(generation)) {
        _setError(_messageFor(error));
        _setState(AssistantState.listening);
        await _startActiveSpeechListening();
      }
    } finally {
      if (_sessionGeneration == generation) _isProcessingRequest = false;
    }
  }

  Future<void> startSpeechListening() async {
    if (_disposed) return;
    if (state.value == AssistantState.sleeping) {
      await onWakeWordDetected();
    }
    if (state.value == AssistantState.listening) {
      try {
        await _startActiveSpeechListening();
      } catch (error) {
        _setError(_messageFor(error));
      }
    }
  }

  Future<void> stopSpeechListening() => _speechService.stopListening();

  Future<void> _startActiveSpeechListening() async {
    if (_disposed || !_sessionActive || state.value != AssistantState.listening) {
      return;
    }
    debugPrint('[STT] recovery=start active session');
    await _speechService.startListening();
  }

  void _handleSpeechError(String error) {
    debugPrint('[STT] error=$error');
    unawaited(_recoverFromSpeechError(error));
  }

  Future<void> _recoverFromSpeechError(String error) async {
    if (_recoveringSpeech || _disposed) return;
    if (!_sessionActive || state.value != AssistantState.listening) {
      debugPrint('[STT] recovery=ignored stale error');
      return;
    }
    _recoveringSpeech = true;
    final generation = _sessionGeneration;
    try {
      debugPrint('[STT] recovery=release microphone');
      await _speechService.stopListening();
      if (!_isCurrentSession(generation) ||
          state.value != AssistantState.listening) {
        return;
      }
      debugPrint('[STT] recovery=restart active listening');
      await _startActiveSpeechListening();
    } catch (_) {
      if (_isCurrentSession(generation)) {
        _setError('Speech recognition stopped. Say “Enigma” to try again.');
        debugPrint('[STT] recovery=sleeping wake word resumed');
        await sleepAssistant();
      }
    } finally {
      _recoveringSpeech = false;
    }
  }
  Future<void> goToSleep() async {
    await sleepAssistant();
  }

  bool _isCurrentSession(int generation) =>
      !_disposed && _sessionActive && generation == _sessionGeneration;

  void _setState(AssistantState next) {
    state.value = next;
    debugPrint('[ENIGMA] State: ${next.name.toUpperCase()}');
  }

  void _setError(String message) {
    errorMessage.value = message;
    debugPrint('[ENIGMA] $message');
  }

  String _messageFor(Object error) =>
      error is AIServiceException ||
          error is SpeechServiceException ||
          error is WakeWordException
      ? (error as dynamic).message as String
      : "Sorry, I couldn't complete that request.";

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _wakeWordSubscription?.cancel();
    await _wakeWordErrorSubscription?.cancel();
    await _recognizedTextSubscription?.cancel();
    await _finalTextSubscription?.cancel();
    await _speechListeningSubscription?.cancel();
    await _speechErrorSubscription?.cancel();
    await _ttsErrorSubscription?.cancel();
    await _ttsService.stop();
    await _speechService.dispose();
    await _wakeWordService.dispose();
    await _aiService.dispose();
    await _ttsService.dispose();
    state.dispose();
    currentTranscript.dispose();
    currentResponse.dispose();
    errorMessage.dispose();
  }
}
