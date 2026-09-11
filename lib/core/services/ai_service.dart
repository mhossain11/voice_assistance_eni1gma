import '../models/conversation_message.dart';

abstract class AIService {
  Future<String> ask({
    required String message,
    required List<ConversationMessage> history,
  });

  Future<void> dispose();
}

class AIServiceException implements Exception {
  const AIServiceException(this.message);
  final String message;
}
