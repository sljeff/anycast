import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/widgets/player_page.dart';
import 'package:flutter/material.dart';
import 'package:anycast/states/player.dart';
import 'package:get/get.dart';
import 'package:dismissible_page/dismissible_page.dart';

class PlayerWidget extends StatelessWidget {
  final PlayerController controller = Get.put(PlayerController());

  PlayerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        var episode = controller.playlistEpisode;

        if (episode == null) {
          return const SizedBox.shrink();
        }

        var imageUrl = episode.imageUrl;

        return Stack(
          children: [
            // backgroud with blur, click effect, shadow
            Positioned(
              width: 100,
              height: 56,
              right: 8,
              bottom: 8,
              child: Hero(
                tag: 'play_background',
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueGrey.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
                right: 58, bottom: 16, child: PlayerImage(imageUrl: imageUrl)),
            const Positioned(
              right: 16,
              bottom: 16,
              child: PlayerButton(),
            ),
          ],
        );
      },
    );
  }
}

class PlayerButton extends StatelessWidget {
  const PlayerButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var audioHandler = MyAudioHandler();
    return StreamBuilder(
        stream: audioHandler.playbackStateStream,
        builder: (context, snapshot) {
          var isPlaying = snapshot.data?.playing ?? false;
          return GestureDetector(
            onTap: () {
              if (isPlaying) {
                audioHandler.pause();
              } else {
                audioHandler.play();
              }
            },
            child: SizedBox(
              width: 40,
              height: 40,
              child: Hero(
                tag: 'play_button',
                child: isPlaying
                    ? const Icon(Icons.pause)
                    : const Icon(Icons.play_arrow),
              ),
            ),
          );
        });
  }
}

class PlayerImage extends StatelessWidget {
  const PlayerImage({
    super.key,
    required this.imageUrl,
  });

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (imageUrl == null) {
      child = const SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.image),
      );
    } else {
      child = ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.network(imageUrl!, width: 40, height: 40));
    }

    return GestureDetector(
      onTap: () {
        context.pushTransparentRoute(const PlayerPage());
      },
      child: Hero(tag: 'play_image', child: child),
    );
  }
}
