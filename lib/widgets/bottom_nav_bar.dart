import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/pages/player.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:remixicon/remixicon.dart';

class BottomNavBar extends StatelessWidget {
  static final playerController = Get.find<PlayerController>();
  static final playlistKey = GlobalKey();

  const BottomNavBar({super.key});

  static Offset getPlaylistPosition() {
    var r = playlistKey.currentContext?.findRenderObject() as RenderBox;
    return r.localToGlobal(r.size.center(Offset.zero));
  }

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
            width: double.infinity,
            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const BarIcon(
                  icon: Icons.home_rounded,
                  index: 0,
                  text: 'Podcast',
                ),
                BarIcon(
                  key: playlistKey,
                  icon: Icons.video_library_rounded,
                  index: 1,
                  text: 'Playlist',
                ),
                BarIcon(
                  icon: MdiIcons.cloudSearch,
                  index: 2,
                  text: 'Discover',
                ),
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

      if (episode.enclosureUrl == null) {
        return const SizedBox.shrink();
      }

      var postion = controller.positionData;
      var posPercent = postion.value.position.inMilliseconds /
          postion.value.duration.inMilliseconds;
      // width of played bar * posPercent
      var barWidth = MediaQuery.of(context).size.width - 12 * 2;
      var playedWidth = barWidth * posPercent;
      if (playedWidth < 0 || playedWidth > barWidth || playedWidth.isNaN) {
        playedWidth = 0;
      }

      return GestureDetector(
        onTap: () {
          showMaterialModalBottomSheet(
            context: context,
            builder: (context) => const PlayerPage(),
            expand: true,
            closeProgressThreshold: 0.9,
          );
        },
        // 上拉，显示 PlayerPage
        onVerticalDragUpdate: (details) {
          showMaterialModalBottomSheet(
            context: context,
            builder: (context) => const PlayerPage(),
            expand: true,
            closeProgressThreshold: 0.9,
          );
        },
        child: Container(
          height: 58,
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
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: playedWidth,
                    height: 58,
                    color: Colors.white.withOpacity(0.2),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          width: 36,
                          height: 36,
                          imageUrl:
                              controller.playlistEpisode.value.imageUrl ?? '',
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
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              PlaylistEpisodeModel.getPlayedAndTotalTime(
                                  postion.value.position.inMilliseconds,
                                  postion.value.duration.inMilliseconds),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
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
          onTap: () {
            if (index == 0 && controller.selectedIndex.value == 0) {
              var feedController = Get.find<FeedEpisodeController>();
              if (!feedController.scrollController.hasClients ||
                  feedController.scrollController.offset == 0) {
                feedController.refreshIndicatorKey.currentState?.show();
              } else {
                feedController.scrollController.animateTo(0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut);
              }
            }

            controller.onItemTapped(index);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                alignment: Alignment.center,
                width: 48,
                height: 48,
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(36),
                  ),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontFamily: GoogleFonts.comfortaa().fontFamily,
                  fontWeight: FontWeight.w400,
                  height: 0,
                ),
              ),
            ],
          ));
    });
  }
}
