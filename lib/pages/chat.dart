import 'package:anycast/models/episode.dart';
import 'package:anycast/states/chat.dart';
import 'package:flutter/material.dart';

import 'package:flutter_chat_ui/flutter_chat_ui.dart' as chat;
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ant_design.dart';

class Chat extends GetView<ChatController> {
  final Episode episode;

  const Chat({super.key, required this.episode});

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
        ),
        body: Obx(
          () {
            return chat.Chat(
              messages: controller.messages.value,
              emptyState: Center(
                child: Text(
                  "Curious about the podcast?\n"
                  "Let's chat!",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.comfortaa(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ),
              onSendPressed: (text) {
                if (controller.isLoading.value) {
                  return;
                }

                var inputTextController = controller.getTC();

                inputTextController.clear();

                final enclosureUrl = episode.enclosureUrl!;
                controller.sendMessage(text, enclosureUrl);
              },
              user: controller.human,
              onAttachmentPressed: () {
                controller.clearMessages();
              },
              theme: const chat.DarkChatTheme(
                attachmentButtonIcon: Iconify(
                  AntDesign.clear,
                  color: Colors.white,
                ),
              ),
              inputOptions: chat.InputOptions(
                inputClearMode: chat.InputClearMode.never,
                autocorrect: false,
                textEditingController: controller.getTC(),
              ),
            );
          },
        ),
      ),
    );
  }
}
