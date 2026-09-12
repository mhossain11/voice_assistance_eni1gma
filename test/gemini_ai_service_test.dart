import 'dart:convert';

import 'package:en1gma/core/services/ai_service.dart';
import 'package:en1gma/core/services/gemini_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('uses the Gemini generateContent endpoint and expected request body', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Hello.'},
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final service = GeminiAIService(
      client: client,
      apiKey: 'test-key',
      model: 'gemini-3.6-flash',
    );

    expect(await service.ask(message: 'Hello', history: const []), 'Hello.');
    expect(captured.method, 'POST');
    expect(
      captured.url.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent',
    );
    expect(captured.headers['content-type'], 'application/json');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final contents = body['contents'] as List<dynamic>;
    expect((contents.single as Map<String, dynamic>)['parts'], [
      {'text': 'Hello'},
    ]);
    await service.dispose();
  });

  test('keeps the user-facing message safe for a Gemini API error', () async {
    final service = GeminiAIService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 404, 'status': 'NOT_FOUND', 'message': 'Model not found'},
          }),
          404,
        ),
      ),
      apiKey: 'test-key',
    );

    await expectLater(
      service.ask(message: 'Hello', history: const []),
      throwsA(
        isA<AIServiceException>().having(
          (error) => error.message,
          'friendly message',
          "Sorry, I couldn't reach Gemini.",
        ),
      ),
    );
    await service.dispose();
  });
}
