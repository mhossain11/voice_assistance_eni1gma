import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
          const String.fromEnvironment(
            'GEMINI_MODEL',
            defaultValue: 'gemini-3.6-flash',
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
      _log('API key missing');
      throw const AIServiceException(
        'Gemini is not configured. Add GEMINI_API_KEY before running the app.',
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
    final endpoint = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$_model:generateContent',
    );
    _log('request started');
    _log('model=$_model');
    _log('endpoint=$endpoint');
    try {
      final response = await _client
          .post(
            endpoint,
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
          .timeout(const Duration(seconds: 60));
      _log('response status=${response.statusCode}');
      _log('response received');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = _safeApiError(response.body);
        _log('API error: $error');
        throw const AIServiceException("Sorry, I couldn't reach Gemini.");
      }
      final payload = _decodeResponse(response.body);
      _log('response parsed');
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
        _log('parse error: empty response text');
        throw const AIServiceException('Gemini returned an empty response.');
      }
      _log('response text length=${text.length}');
      return text;
    } on TimeoutException {
      _log('timeout');
      throw const AIServiceException("Sorry, Gemini took too long to respond.");
    } on SocketException catch (error) {
      _log('network error: ${_safeNetworkReason(error)}');
      throw const AIServiceException("Sorry, I couldn't reach Gemini.");
    } on http.ClientException catch (error) {
      _log('network error: ${_safeNetworkReason(error)}');
      throw const AIServiceException("Sorry, I couldn't reach Gemini.");
    } on FormatException catch (error) {
      _log('parse error: ${error.message}');
      throw const AIServiceException('Gemini returned an invalid response.');
    } on TypeError {
      _log('parse error: unexpected response shape');
      throw const AIServiceException('Gemini returned an invalid response.');
    } on AIServiceException {
      rethrow;
    } catch (error) {
      _log('network error: ${error.runtimeType}');
      throw const AIServiceException("Sorry, I couldn't reach Gemini.");
    }
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      _log('parse error: invalid JSON');
      rethrow;
    } on TypeError {
      _log('parse error: unexpected JSON shape');
      throw const FormatException('Unexpected JSON shape.');
    }
  }

  String _safeApiError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      final status = error?['status'] as String?;
      final message = error?['message'] as String?;
      if (status != null && message != null) return '$status: $message';
      return status ?? message ?? 'No API error detail supplied.';
    } catch (_) {
      return 'Unreadable API error response.';
    }
  }

  String _safeNetworkReason(Object error) => error.runtimeType.toString();

  void _log(String message) => debugPrint('[GEMINI] $message');

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
