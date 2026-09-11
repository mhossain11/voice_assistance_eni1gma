import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/conversation_message.dart';
import 'ai_service.dart';

const en1gmaSystemInstruction =
    '''You are EN1GMA, a lightweight personal voice assistant.
Give natural, concise, useful answers suitable for a voice conversation. Avoid unnecessarily long responses. For technical questions, provide enough detail to be useful. Never mention internal implementation details unless asked.''';

String _localEnvironmentValue(String name) =>
    dotenv.isInitialized ? dotenv.env[name] ?? '' : '';

String _configuredValue(String local, String fallback) =>
    local.trim().isEmpty ? fallback : local;

class GeminiAIService implements AIService {
  GeminiAIService({http.Client? client, String? apiKey, String? model})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ??
          _configuredValue(
            _localEnvironmentValue('GEMINI_API_KEY'),
            const String.fromEnvironment('GEMINI_API_KEY'),
          ),
      _model =
          model ??
          _configuredValue(
            _localEnvironmentValue('GEMINI_MODEL'),
            const String.fromEnvironment(
              'GEMINI_MODEL',
              defaultValue: 'gemini-3.6-flash',
            ),
          );

  final http.Client _client;
  final String _apiKey;
  final String _model;
  bool _disposed = false;

  @override
  Future<String> ask({
    required String message,
    required List<ConversationMessage> history,
  }) async {
    if (_disposed) {
      throw const AIServiceException('Gemini service is unavailable.');
    }
    if (_apiKey.trim().isEmpty) {
      throw const AIServiceException(
        'Gemini is not configured. Add GEMINI_API_KEY to .env.',
      );
    }
    final contents = [
      ...history.map(_contentFor),
      {
        'role': 'user',
        'parts': [
          {'text': message},
        ],
      },
    ];
    try {
      final response = await _client
          .post(
            Uri.https(
              'generativelanguage.googleapis.com',
              '/v1beta/models/$_model:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey,
            },
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': en1gmaSystemInstruction},
                ],
              },
              'contents': contents,
              'generationConfig': {'maxOutputTokens': 280, 'temperature': 0.5},
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AIServiceException("Sorry, I couldn't reach Gemini.");
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = payload['candidates'] as List<dynamic>?;
      final candidate = candidates?.firstOrNull as Map<String, dynamic>?;
      final content = candidate?['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      final text = parts
          ?.whereType<Map<String, dynamic>>()
          .map((part) => part['text'])
          .whereType<String>()
          .join()
          .trim();
      if (text == null || text.isEmpty) {
        throw const AIServiceException('Gemini returned an empty response.');
      }
      return text;
    } on TimeoutException {
      throw const AIServiceException("Sorry, Gemini took too long to respond.");
    } on AIServiceException {
      rethrow;
    } catch (_) {
      throw const AIServiceException("Sorry, I couldn't reach Gemini.");
    }
  }

  Map<String, dynamic> _contentFor(ConversationMessage message) => {
    'role': message.role == 'assistant' ? 'model' : 'user',
    'parts': [
      {'text': message.content},
    ],
  };

  @override
  Future<void> dispose() async {
    _disposed = true;
    _client.close();
  }
}
