import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/pages/player_page.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:remixicon/remixicon.dart';
import 'package:dismissible_page/dismissible_page.dart';

class BottomNavBar extends GetView<HomeTabController> {
  final playerController = Get.find<PlayerController>();

  BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(0.00, -1.00),
          end: Alignment(0, 1),
          colors: [Color(0xF014171A), Color(0xFF16191D)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PlayerBar(),
          Container(
            height: 96,
            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                    child: BarIcon(
                  icon: Icons.home_rounded,
                  index: 0,
                  text: 'Podcast',
                )),
                const Expanded(
                    child: BarIcon(
                  icon: Icons.video_library_rounded,
                  index: 1,
                  text: 'Playlist',
                )),
                Expanded(
                    child: BarIcon(
                  icon: MdiIcons.cloudSearch,
                  index: 2,
                  text: 'Discover',
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerBar extends GetView<PlayerController> {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var episode = controller.playlistEpisode.value;

      if (episode.guid == null) {
        return const SizedBox.shrink();
      }

      var postion = controller.positionData;
      var posPercent = postion.value.position.inMilliseconds /
          postion.value.duration.inMilliseconds;
      // width of played bar * posPercent
      var barWidth = MediaQuery.of(context).size.width - 12 * 2;
      var playedWidth = barWidth * posPercent;
      if (playedWidth < 0 || playedWidth > barWidth) {
        playedWidth = 0;
      }

      return GestureDetector(
        onTap: () {
          context.pushTransparentRoute(const PlayerPage());
        },
        // 上拉，显示 PlayerPage
        onVerticalDragUpdate: (details) {
          context.pushTransparentRoute(const PlayerPage());
        },
        child: Container(
          height: 56,
          margin: const EdgeInsets.only(left: 12, right: 12),
          decoration: ShapeDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Container(
                  width: playedWidth,
                  color: Colors.white.withOpacity(0.2),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'play_image',
                        child: Container(
                          width: 36,
                          height: 36,
                          clipBehavior: Clip.antiAlias,
                          decoration: ShapeDecoration(
                            image: DecorationImage(
                              image:
                                  CachedNetworkImageProvider(episode.imageUrl!),
                              fit: BoxFit.fill,
                            ),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Text(
                                episode.title!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontFamily: 'PingFangSC-Regular,PingFang SC',
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Opacity(
                              opacity: 0.50,
                              child: Text(
                                PlaylistEpisodeModel.getPlayedAndTotalTime(
                                    postion.value.position.inMilliseconds,
                                    postion.value.duration.inMilliseconds),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontFamily: 'PingFangSC-Regular,PingFang SC',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (controller.isPlaying.value) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                        },
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: PlayIcon(
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          controller.seek(Duration(
                              milliseconds:
                                  postion.value.position.inMilliseconds +
                                      30000));
                        },
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Remix.forward_30_fill,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      );
    });
  }
}

class BarIcon extends GetView<HomeTabController> {
  final IconData icon;
  final int index;
  final String text;

  const BarIcon({
    super.key,
    required this.icon,
    required this.index,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var isSelected = controller.selectedIndex.value == index;
      var color =
          isSelected ? const Color(0xFF6EE7B7) : const Color(0xFF6b7280);

      return GestureDetector(
          onTap: () => controller.onItemTapped(index),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(36),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  icon,
                                  color: color,
                                  size: 24,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontFamily: 'Comfortaa',
                  fontWeight: FontWeight.w400,
                  height: 0,
                ),
              ),
            ],
          ));
    });
  }
}
