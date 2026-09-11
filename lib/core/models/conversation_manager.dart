import 'conversation_message.dart';

class ConversationManager {
  ConversationManager({this.maxMessages = 16});

  final int maxMessages;
  final List<ConversationMessage> _messages = [];

  List<ConversationMessage> get messages => List.unmodifiable(_messages);

  void addUserMessage(String text) => _add('user', text);
  void addAssistantMessage(String text) => _add('assistant', text);
  void clear() => _messages.clear();

  void _add(String role, String text) {
    _messages.add(ConversationMessage(role: role, content: text));
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
  }
}
