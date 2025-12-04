import 'package:anycast/models/episode.dart';
import 'package:anycast/states/chat.dart' as state;
import 'package:flutter/material.dart';

import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatPage extends GetView<state.ChatController> {
  final Episode episode;

  const ChatPage({super.key, required this.episode});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          controller.clearMessages();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          backgroundColor: Colors.deepPurpleAccent,
          foregroundColor: Colors.white,
          leading: IconButton(
            onPressed: () {
              controller.clearMessages();
              Get.back();
            },
            style: IconButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: Colors.black26,
            ),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              episode.title ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.comfortaa(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          actions: [
            IconButton(
              onPressed: () {
                controller.clearMessages();
              },
              icon: const Icon(Icons.delete_outline, color: Colors.white),
            ),
          ],
        ),
        body: Chat(
          chatController: controller.chatController,
          currentUserId: state.ChatController.humanId,
          theme: ChatTheme.dark(),
          onMessageSend: (text) {
            if (controller.isLoading.value) return;
            final enclosureUrl = episode.enclosureUrl!;
            controller.sendMessage(text, enclosureUrl);
          },
          resolveUser: (userId) async {
            return User(
              id: userId,
              name: userId == state.ChatController.humanId ? 'You' : 'AI',
            );
          },
        ),
      ),
    );
  }
}
