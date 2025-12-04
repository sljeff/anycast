import 'package:anycast/api/subtitles.dart';
import 'package:get/get.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:uuid/uuid.dart';

class ChatController extends GetxController {
  final chatController = InMemoryChatController();
  final isLoading = false.obs;

  static const humanId = 'human';
  static const aiId = 'ai';

  String? _currentAiMessageId;

  void sendMessage(String text, String enclosureUrl) {
    if (isLoading.value) return;

    final userMsg = TextMessage(
      id: const Uuid().v4(),
      authorId: humanId,
      createdAt: DateTime.now().toUtc(),
      text: text,
    );
    chatController.insertMessage(userMsg);

    List<Map<String, String>> history = [];
    final messages = chatController.messages;
    // 获取最近 10 条历史消息
    for (int i = 0; i < messages.length && i < 10; i++) {
      final msg = messages[i];
      if (msg is TextMessage) {
        history.add({msg.authorId: msg.text});
      }
    }
    history = history.reversed.toList();

    send2AI(enclosureUrl, text, history);
  }

  void send2AI(
      String enclosureUrl, String input, List<Map<String, String>> history) {
    isLoading.value = true;

    // AI 占位消息
    _currentAiMessageId = const Uuid().v4();
    final aiPlaceholder = TextMessage(
      id: _currentAiMessageId!,
      authorId: aiId,
      createdAt: DateTime.now().toUtc(),
      text: '...',
    );
    chatController.insertMessage(aiPlaceholder);

    chatAPI(enclosureUrl, input, history).then((result) {
      // 替换占位消息为实际响应
      final oldMessage = chatController.messages
          .whereType<TextMessage>()
          .firstWhere((m) => m.id == _currentAiMessageId);

      final newMessage = TextMessage(
        id: const Uuid().v4(),
        authorId: aiId,
        createdAt: DateTime.now().toUtc(),
        text: result,
      );

      chatController.updateMessage(oldMessage, newMessage);
      _currentAiMessageId = null;
      isLoading.value = false;
    });
  }

  void clearMessages() {
    // 清空所有消息
    final allMessages = List<Message>.from(chatController.messages);
    for (final msg in allMessages) {
      chatController.removeMessage(msg);
    }
  }

  @override
  void onClose() {
    chatController.dispose();
    super.onClose();
  }
}
