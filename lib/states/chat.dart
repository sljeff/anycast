import 'package:anycast/api/subtitles.dart';
import 'package:get/get.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:uuid/uuid.dart';

class ChatController extends GetxController {
  final Rx<List<types.Message>> messages = Rx<List<types.Message>>([]);
  final isLoading = false.obs;

  final human = const types.User(id: 'human');
  final ai = const types.User(id: 'ai');

  void sendMessage(types.PartialText message, String enclosureUrl) {
    final textMessage = types.TextMessage(
      id: const Uuid().v4(),
      text: message.text,
      author: human,
    );

    messages.value = [textMessage, ...messages.value];

    List<Map<String, String>> history = [];
    if (messages.value.length > 1) {
      for (int i = 1; i <= 10 && i < messages.value.length; i++) {
        history.add({
          messages.value[i].author.id:
              (messages.value[i] as types.TextMessage).text,
        });
      }
    }
    history = history.reversed.toList();

    send2AI(enclosureUrl, textMessage.text, history);
  }

  void send2AI(
      String enclosureUrl, String input, List<Map<String, String>> history) {
    isLoading.value = true;

    messages.value = [
      types.TextMessage(
        id: const Uuid().v4(),
        text: '...',
        author: ai,
      ),
      ...messages.value,
    ];

    chatAPI(enclosureUrl, input, history).then((result) {
      messages.value = [
        types.TextMessage(
          id: const Uuid().v4(),
          text: result,
          author: ai,
        ),
        ...messages.value.skip(1),
      ];
      isLoading.value = false;
    });
  }

  void clearMessages() {
    messages.value = [];
  }
}
