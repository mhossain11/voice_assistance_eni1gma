import 'dart:convert';

import 'package:en1gma/core/models/conversation_message.dart';
import 'package:en1gma/core/services/ai_service.dart';
import 'package:en1gma/core/services/gemini_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const models = ['model-a', 'model-b', 'model-c'];

  test('first model succeeds and is the only model called', () async {
    final calls = <String>[];
    final service = _service(calls, (_) => _success('First response'));

    expect(
      await service.ask(message: 'Hello', history: const []),
      'First response',
    );
    expect(calls, ['model-a']);
    expect(service.lastSuccessfulModel, 'model-a');
    await service.dispose();
  });

  test('429 falls back to the next model once', () async {
    final calls = <String>[];
    final service = _service(
      calls,
      (model) => model == 'model-a'
          ? _error(429, 'RESOURCE_EXHAUSTED', 'Quota exceeded')
          : _success('Fallback'),
    );

    expect(await service.ask(message: 'Hello', history: const []), 'Fallback');
    expect(calls, ['model-a', 'model-b']);
    await service.dispose();
  });

  test('two quota failures reach the third model', () async {
    final calls = <String>[];
    final service = _service(
      calls,
      (model) => model == 'model-c'
          ? _success('Third')
          : _error(429, 'RESOURCE_EXHAUSTED', 'Quota exceeded'),
    );

    expect(await service.ask(message: 'Hello', history: const []), 'Third');
    expect(calls, models);
    await service.dispose();
  });

  test('model-not-found skips to the next model', () async {
    final calls = <String>[];
    final service = _service(
      calls,
      (model) => model == 'model-a'
          ? _error(404, 'NOT_FOUND', 'Model not found')
          : _success('Available'),
    );

    expect(await service.ask(message: 'Hello', history: const []), 'Available');
    expect(calls, ['model-a', 'model-b']);
    await service.dispose();
  });

  test('all quota failures return a controlled error', () async {
    final calls = <String>[];
    final service = _service(
      calls,
      (_) => _error(429, 'RESOURCE_EXHAUSTED', 'Quota exceeded'),
    );

    await expectLater(
      service.ask(message: 'Hello', history: const []),
      throwsA(
        isA<AIServiceException>().having(
          (error) => error.message,
          'message',
          'All configured Gemini models are currently unavailable.',
        ),
      ),
    );
    expect(calls, models);
    await service.dispose();
  });

  test('authentication failure does not try every model', () async {
    final calls = <String>[];
    final service = _service(
      calls,
      (_) => _error(401, 'UNAUTHENTICATED', 'Invalid API key'),
    );

    await expectLater(
      service.ask(message: 'Hello', history: const []),
      throwsA(isA<AIServiceException>()),
    );
    expect(calls, ['model-a']);
    await service.dispose();
  });

  test('fallback reuses one unchanged conversation context', () async {
    final calls = <String>[];
    final requestBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      calls.add(_modelFrom(request));
      requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return calls.length == 1
          ? _error(429, 'RESOURCE_EXHAUSTED', 'Quota exceeded')
          : _success('Fallback');
    });
    final service = GeminiAIService(
      client: client,
      apiKey: 'test-key',
      preferredModels: models,
    );
    final history = [
      const ConversationMessage(role: 'user', content: 'Earlier question'),
    ];

    expect(
      await service.ask(message: 'What is Flutter?', history: history),
      'Fallback',
    );
    expect(requestBodies[0]['contents'], requestBodies[1]['contents']);
    expect((requestBodies[0]['contents'] as List).length, 2);
    await service.dispose();
  });

  test('model override is attempted before configured fallback models', () async {
    final calls = <String>[];
    final service = _service(
      calls,
      (_) => _success('Override'),
      model: 'model-override',
    );

    expect(await service.ask(message: 'Hello', history: const []), 'Override');
    expect(calls, ['model-override']);
    await service.dispose();
  });
}

GeminiAIService _service(
  List<String> calls,
  http.Response Function(String model) response, {
  String? model,
}) => GeminiAIService(
  client: MockClient((request) async {
    final requestedModel = _modelFrom(request);
    calls.add(requestedModel);
    return response(requestedModel);
  }),
  apiKey: 'test-key',
  model: model,
  preferredModels: const ['model-a', 'model-b', 'model-c'],
);

String _modelFrom(http.Request request) =>
    request.url.pathSegments.last.replaceFirst(':generateContent', '');

http.Response _success(String text) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  }),
  200,
);

http.Response _error(int status, String code, String message) => http.Response(
  jsonEncode({
    'error': {'code': status, 'status': code, 'message': message},
  }),
  status,
);
