import 'dart:async';

import 'package:en1gma/core/models/conversation_message.dart';
import 'package:en1gma/core/services/ai_service.dart';
import 'package:en1gma/core/services/speech_service.dart';
import 'package:en1gma/core/services/tts_service.dart';
import 'package:en1gma/core/services/wake_word_service.dart';
import 'package:en1gma/features/assistant/domain/entities/assistant_state.dart';
import 'package:en1gma/features/assistant/domain/utils/sleep_command_detector.dart';
import 'package:en1gma/features/assistant/presentation/controllers/assistant_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'final transcript moves to thinking, calls AI, stores history and resumes listening',
    () async {
      final wake = _FakeWakeWordService();
      final speech = _FakeSpeechService();
      final ai = _FakeAIService();
      final tts = _FakeTtsService();
      final controller = AssistantController(wake, speech, ai, tts);
      await controller.initialize();
      await controller.onWakeWordDetected();
      speech.emitFinal('What is Flutter?');
      await Future<void>.delayed(Duration.zero);
      expect(ai.messages, ['What is Flutter?']);
      expect(controller.state.value, AssistantState.listening);
      expect(controller.currentResponse.value, 'Flutter is a UI toolkit.');
      expect(controller.conversation.messages.map((m) => m.role), [
        'user',
        'assistant',
      ]);
      expect(speech.stopCalls, greaterThanOrEqualTo(1));
      await controller.dispose();
      expect(ai.disposed, isTrue);
    },
  );

  test(
    'empty and duplicate final transcripts do not create duplicate requests',
    () async {
      final wake = _FakeWakeWordService();
      final speech = _FakeSpeechService();
      final ai = _FakeAIService(completer: Completer<String>());
      final controller = AssistantController(
        wake,
        speech,
        ai,
        _FakeTtsService(),
      );
      await controller.initialize();
      await controller.onWakeWordDetected();
      speech.emitFinal('  ');
      speech.emitFinal('Hello');
      speech.emitFinal('Hello');
      await Future<void>.delayed(Duration.zero);
      expect(ai.messages, ['Hello']);
      ai.completer!.complete('Hi');
      await Future<void>.delayed(Duration.zero);
      await controller.dispose();
    },
  );

  test('AI error returns safely to listening', () async {
    final wake = _FakeWakeWordService();
    final speech = _FakeSpeechService();
    final ai = _FakeAIService(throwsError: true);
    final controller = AssistantController(wake, speech, ai, _FakeTtsService());
    await controller.initialize();
    await controller.onWakeWordDetected();
    speech.emitFinal('Hello');
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.value, AssistantState.listening);
    expect(controller.errorMessage.value, isNotNull);
    await controller.dispose();
  });

  test('Gemini response is spoken before STT resumes', () async {
    final wake = _FakeWakeWordService();
    final speech = _FakeSpeechService();
    final tts = _FakeTtsService(autoComplete: false);
    final controller = AssistantController(wake, speech, _FakeAIService(), tts);
    await controller.initialize();
    await controller.onWakeWordDetected();
    speech.emitFinal('Hello');
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.value, AssistantState.speaking);
    expect(tts.spoken, ['Flutter is a UI toolkit.']);
    tts.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.value, AssistantState.listening);
    await controller.dispose();
    expect(tts.stopCalls, greaterThanOrEqualTo(1));
  });

  test('local sleep commands end the session without calling Gemini', () async {
    for (final command in [
      'sleep',
      'go to sleep',
      'Enigma, go to sleep',
      'stop listening',
    ]) {
      final wake = _FakeWakeWordService();
      final speech = _FakeSpeechService();
      final ai = _FakeAIService();
      final tts = _FakeTtsService();
      final controller = AssistantController(wake, speech, ai, tts);
      await controller.initialize();
      await controller.onWakeWordDetected();
      speech.emitFinal(command);
      await Future<void>.delayed(Duration.zero);
      expect(ai.messages, isEmpty);
      expect(controller.state.value, AssistantState.sleeping);
      expect(wake.startCalls, 2);
      expect(speech.stopCalls, greaterThanOrEqualTo(1));
      expect(tts.stopCalls, greaterThanOrEqualTo(1));
      expect(controller.conversation.messages, isEmpty);
      await controller.dispose();
    }
    expect(isSleepCommand('Why does sleep matter?'), isFalse);
  });

  test('sleep invalidates an old Gemini response and is idempotent', () async {
    final wake = _FakeWakeWordService();
    final speech = _FakeSpeechService();
    final ai = _FakeAIService(completer: Completer<String>());
    final controller = AssistantController(wake, speech, ai, _FakeTtsService());
    await controller.initialize();
    await controller.onWakeWordDetected();
    speech.emitFinal('Tell me something');
    await Future<void>.delayed(Duration.zero);
    await controller.sleepAssistant();
    await controller.sleepAssistant();
    ai.completer!.complete('Old response');
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.value, AssistantState.sleeping);
    expect(controller.currentResponse.value, isEmpty);
    expect(wake.startCalls, 2);
    await controller.dispose();
  });

  test('duplicate wake events do not restart an active STT session', () async {
    final wake = _FakeWakeWordService();
    final speech = _FakeSpeechService();
    final controller = AssistantController(wake, speech, _FakeAIService(), _FakeTtsService());
    await controller.initialize();
    await controller.onWakeWordDetected();
    await controller.onWakeWordDetected();
    expect(speech.startCalls, 1);
    expect(controller.state.value, AssistantState.listening);
    await controller.dispose();
  });
}

class _FakeWakeWordService implements WakeWordService {
  final _events = StreamController<void>.broadcast(sync: true);
  bool disposed = false;
  int startCalls = 0;
  @override
  Stream<void> get wakeWordDetected => _events.stream;
  @override
  Stream<WakeWordServiceState> get serviceStates => const Stream.empty();
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> start() async => startCalls++;
  @override
  Future<void> stop() async {}
  @override
  Future<WakeWordServiceState> getServiceState() async =>
      WakeWordServiceState.stopped;
  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}

class _FakeSpeechService implements SpeechService {
  final _text = StreamController<String>.broadcast(sync: true);
  final _finalText = StreamController<String>.broadcast(sync: true);
  final _state = StreamController<bool>.broadcast(sync: true);
  final _errors = StreamController<String>.broadcast(sync: true);
  int stopCalls = 0;
  int startCalls = 0;
  @override
  Stream<String> get recognizedText => _text.stream;
  @override
  Stream<String> get finalRecognizedText => _finalText.stream;
  @override
  Stream<bool> get listeningState => _state.stream;
  @override
  Stream<String> get errors => _errors.stream;
  void emitFinal(String value) {
    _text.add(value);
    _finalText.add(value);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<void> startListening() async => startCalls++;
  @override
  Future<void> stopListening() async => stopCalls++;
  @override
  Future<void> dispose() async {
    await _text.close();
    await _finalText.close();
    await _state.close();
    await _errors.close();
  }
}

class _FakeAIService implements AIService {
  _FakeAIService({this.completer, this.throwsError = false});
  final Completer<String>? completer;
  final bool throwsError;
  final List<String> messages = [];
  bool disposed = false;
  @override
  Future<String> ask({
    required String message,
    required List<ConversationMessage> history,
  }) async {
    messages.add(message);
    if (throwsError) {
      throw const AIServiceException('Sorry, I could not reach Gemini.');
    }
    return completer?.future ?? 'Flutter is a UI toolkit.';
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeTtsService implements TtsService {
  _FakeTtsService({this.autoComplete = true});
  final bool autoComplete;
  final _states = StreamController<bool>.broadcast(sync: true);
  final _errors = StreamController<String>.broadcast(sync: true);
  final List<String> spoken = [];
  Completer<void>? _pending;
  int stopCalls = 0;
  @override
  Stream<bool> get speakingState => _states.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    _states.add(true);
    if (autoComplete) {
      _states.add(false);
      return;
    }
    _pending = Completer<void>();
    await _pending!.future;
  }

  void complete() {
    _states.add(false);
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.complete();
    }
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    complete();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _states.close();
    await _errors.close();
  }
}
