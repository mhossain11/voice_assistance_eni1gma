import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/conversation_message.dart';
import 'ai_service.dart';

const en1gmaSystemInstruction =
    '''You are EN1GMA, a lightweight personal voice assistant.
Give natural, concise, useful answers suitable for a voice conversation. Avoid unnecessarily long responses. For technical questions, provide enough detail to be useful. Never mention internal implementation details unless asked.''';

const preferredGeminiModels = <String>[
  'gemini-3.8-flash',
  'gemini-3.7-flash',
  'gemini-3.6-flash',
  'gemini-3.5-flash',
  'gemini-3.5-flash-lite',
  'gemini-3.1-flash-lite',
  'gemini-2.5-flash',
  'gemini-2.5-flash-lite',
];

const configuredGeminiModel = String.fromEnvironment(
  'GEMINI_MODEL',
  defaultValue: 'gemini-3.6-flash',
);
const _hasConfiguredGeminiModel = bool.hasEnvironment('GEMINI_MODEL');

String _localEnvironmentValue(String name) =>
    dotenv.isInitialized ? dotenv.env[name] ?? '' : '';

String _configuredValue(String local, String fallback) =>
    local.trim().isEmpty ? fallback : local;

enum _FailureKind { quota, modelUnavailable, authentication, server, other }

class _GeminiRequestFailure implements Exception {
  const _GeminiRequestFailure(this.kind);

  final _FailureKind kind;
}

class GeminiAIService implements AIService {
  GeminiAIService({
    http.Client? client,
    String? apiKey,
    String? model,
    List<String>? preferredModels,
  }) : _client = client ?? http.Client(),
       _apiKey = apiKey ??
           _configuredValue(
             _localEnvironmentValue('GEMINI_API_KEY'),
             const String.fromEnvironment('GEMINI_API_KEY'),
           ),
       _modelOverride =
           model ?? (_hasConfiguredGeminiModel ? configuredGeminiModel : ''),
       _preferredModels = preferredModels ?? preferredGeminiModels;

  final http.Client _client;
  final String _apiKey;
  final String _modelOverride;
  final List<String> _preferredModels;
  final Map<String, DateTime> _modelCooldowns = {};
  bool _disposed = false;

  /// Diagnostic only; it does not pin future requests to this model.
  String? lastSuccessfulModel;

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

    final contents = <Map<String, dynamic>>[
      ...history.map(_contentFor),
      {
        'role': 'user',
        'parts': [
          {'text': message},
        ],
      },
    ];
    final models = _attemptOrder();
    for (var index = 0; index < models.length; index++) {
      final model = models[index];
      if (_isCoolingDown(model)) {
        _log('skipping cooldown model=$model');
        continue;
      }
      try {
        _log('trying model=$model');
        final response = await _requestWithModel(model, contents);
        lastSuccessfulModel = model;
        _log('success model=$model');
        _log('active model=$model');
        return response;
      } on _GeminiRequestFailure catch (failure) {
        if (failure.kind == _FailureKind.authentication) {
          throw const AIServiceException(
            'Gemini rejected the API key or project access.',
          );
        }
        if (failure.kind == _FailureKind.other) {
          throw const AIServiceException(
            "Sorry, Gemini couldn't process that request.",
          );
        }
        if (failure.kind == _FailureKind.quota) {
          _modelCooldowns[model] = DateTime.now().add(_quotaCooldown);
          _log('quota exceeded');
        } else if (failure.kind == _FailureKind.modelUnavailable) {
          _log('model unavailable, trying next');
        } else {
          _log('server error; trying next model once');
        }
        if (_hasNextModel(models, index)) {
          _log('fallback → ${models[index + 1]}');
          continue;
        }
      }
    }
    throw const AIServiceException(
      'All configured Gemini models are currently unavailable.',
    );
  }

  List<String> _attemptOrder() {
    final models = <String>[];
    void add(String value) {
      final model = value.trim();
      if (model.isNotEmpty && !models.contains(model)) models.add(model);
    }

    add(_modelOverride);
    for (final model in _preferredModels) {
      add(model);
    }
    return models;
  }

  bool _hasNextModel(List<String> models, int index) => index + 1 < models.length;

  bool _isCoolingDown(String model) {
    final until = _modelCooldowns[model];
    return until != null && DateTime.now().isBefore(until);
  }

  Future<String> _requestWithModel(
    String model,
    List<Map<String, dynamic>> contents,
  ) async {
    final endpoint = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
    );
    _log('request started');
    _log('model=$model');
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
          .timeout(_requestTimeout);
      _log('response status=${response.statusCode}');
      _log('response received');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = _safeApiError(response.body);
        _log('API error: $detail');
        throw _GeminiRequestFailure(
          _failureKind(response.statusCode, response.body),
        );
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
      _log('network error: ${error.runtimeType}');
      throw const AIServiceException("Sorry, I couldn't reach Gemini.");
    } on http.ClientException catch (error) {
      _log('network error: ${error.runtimeType}');
      throw const AIServiceException("Sorry, I couldn't reach Gemini.");
    } on FormatException catch (error) {
      _log('parse error: ${error.message}');
      throw const AIServiceException('Gemini returned an invalid response.');
    } on TypeError {
      _log('parse error: unexpected response shape');
      throw const AIServiceException('Gemini returned an invalid response.');
    }
  }

  bool _isQuotaError(int statusCode, String body) =>
      statusCode == 429 ||
      _bodyHas(body, ['resource_exhausted', 'quota', 'rate limit']);

  bool _isModelUnavailableError(int statusCode, String body) =>
      statusCode == 404 ||
      ((statusCode == 400 || statusCode == 404) &&
          _bodyHas(body, [
            'model not found',
            'model unavailable',
            'unsupported model',
            'not supported',
          ]));

  _FailureKind _failureKind(int statusCode, String body) {
    if (_isQuotaError(statusCode, body)) return _FailureKind.quota;
    if (_isModelUnavailableError(statusCode, body)) {
      return _FailureKind.modelUnavailable;
    }
    if (statusCode == 401 ||
        statusCode == 403 ||
        _bodyHas(body, ['api key', 'unauthenticated', 'permission denied'])) {
      return _FailureKind.authentication;
    }
    if (statusCode == 500 || statusCode == 502 || statusCode == 503) {
      return _FailureKind.server;
    }
    return _FailureKind.other;
  }

  bool _bodyHas(String body, List<String> phrases) {
    final value = body.toLowerCase();
    return phrases.any(value.contains);
  }

  Map<String, dynamic> _decodeResponse(String body) =>
      jsonDecode(body) as Map<String, dynamic>;

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

  Map<String, dynamic> _contentFor(ConversationMessage message) => {
    'role': message.role == 'assistant' ? 'model' : 'user',
    'parts': [
      {'text': message.content},
    ],
  };

  void _log(String message) => debugPrint('[GEMINI] $message');

  @override
  Future<void> dispose() async {
    _disposed = true;
    _client.close();
  }

  static const _requestTimeout = Duration(seconds: 60);
  static const _quotaCooldown = Duration(minutes: 1);
}
