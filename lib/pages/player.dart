import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/pages/player_page.dart';
import 'package:anycast/styles.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dismissible_page/dismissible_page.dart';

class PlayerWidget extends GetView<PlayerController> {
  const PlayerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        // if playlists not loaded, return empty
        var playlistController = Get.find<PlaylistController>();
        if (playlistController.isLoading.value) {
          return const SizedBox.shrink();
        }

        var episode = controller.playlistEpisode.value;

        if (episode.guid == null) {
          return const SizedBox.shrink();
        }

        var imageUrl = episode.imageUrl;

        // get rotate angle by position
        var pos = controller.refreshFrameTime.value; // 0-999
        var rotateAngle = 0.0;
        if (controller.isPlaying.value) {
          rotateAngle = pos * 1.0 / 2000;
        }

        return GestureDetector(
          onTap: () {
            context.pushTransparentRoute(const PlayerPage());
          },
          child: Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(0.53),
            decoration: ShapeDecoration(
              color: DarkColor.primaryBackground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(64),
              ),
              shadows: const [
                BoxShadow(
                  color: DarkColor.primaryDark,
                  blurRadius: 20,
                  offset: Offset(0, 0),
                  spreadRadius: 0,
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Hero(
                  tag: 'play_image',
                  child: Transform.rotate(
                    angle: rotateAngle,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: ShapeDecoration(
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(imageUrl!),
                          fit: BoxFit.fill,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
