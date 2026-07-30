import 'package:anycast/design_system/anycast_components.dart';
import 'package:anycast/design_system/anycast_theme.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/pages/player.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        AnycastSpacing.pageH,
        AnycastSpacing.md,
        AnycastSpacing.pageH,
        AnycastSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlayerBar(),
          const SizedBox(height: AnycastSpacing.md),
          AnycastGlassSurface(
            borderRadius: BorderRadius.circular(AnycastRadius.pill),
            padding: const EdgeInsets.all(AnycastSpacing.xs),
            child: Row(
              children: [
                const Expanded(
                  child: BarIcon(
                    icon: Icons.home_rounded,
                    index: 0,
                    text: 'Podcast',
                  ),
                ),
                Expanded(
                  child: BarIcon(
                    key: playlistKey,
                    icon: Icons.video_library_rounded,
                    index: 1,
                    text: 'Playlist',
                  ),
                ),
                Expanded(
                  child: BarIcon(
                    icon: Icons.travel_explore_rounded,
                    index: 2,
                    text: 'Discover',
                  ),
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
  final bool bottomSafe;

  const PlayerBar({super.key, this.bottomSafe = false});

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
      var barWidth =
          MediaQuery.of(context).size.width - AnycastSpacing.pageH * 2;
      var playedWidth = barWidth * posPercent;
      if (playedWidth < 0 || playedWidth > barWidth || playedWidth.isNaN) {
        playedWidth = 0;
      }

      var bar = GestureDetector(
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
        child: AnycastGlassSurface(
          borderRadius: BorderRadius.circular(AnycastRadius.card),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AnycastRadius.card),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: playedWidth,
                    height: 56,
                    color: AnycastColor.goldAlpha9(
                      Theme.of(context).brightness,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AnycastSpacing.gap,
                    vertical: AnycastSpacing.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AnycastRadius.sm),
                        child: CachedNetworkImage(
                          width: 36,
                          height: 36,
                          imageUrl: controller.playlistEpisode.value.imageUrl ??
                              'https://placeholder.co/48.png?text=NoImage',
                        ),
                      ),
                      const SizedBox(width: AnycastSpacing.gap),
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
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              PlaylistEpisodeModel.getPlayedAndTotalTime(
                                  postion.value.position.inMilliseconds,
                                  postion.value.duration.inMilliseconds),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AnycastSpacing.pageH),
                      GestureDetector(
                        onTap: () {
                          if (controller.isPlaying.value) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                        },
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: PlayIcon(
                            size: 32,
                            color: Theme.of(context).colorScheme.onSurface,
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
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Remix.forward_30_fill,
                            color: Theme.of(context).colorScheme.onSurface,
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

      if (bottomSafe) {
        return SafeArea(child: bar);
      } else {
        return bar;
      }
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
      final theme = Theme.of(context);
      final iconColor = isSelected
          ? theme.colorScheme.onPrimaryContainer
          : theme.colorScheme.onSurfaceVariant;
      final textColor = isSelected
          ? theme.colorScheme.onPrimaryContainer
          : theme.colorScheme.onSurfaceVariant;

      return GestureDetector(
          onTap: () {
            if (index == 0 && controller.selectedIndex.value == 0) {
              var feedController = Get.find<FeedEpisodeController>();
              if (!feedController.scrollController.hasClients ||
                  feedController.scrollController.offset == 0) {
                feedController.refreshController.callRefresh();
              } else {
                feedController.scrollController.animateTo(0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut);
              }
            }

            controller.onItemTapped(index);
          },
          child: AnimatedContainer(
            duration: AnycastMotion.quick,
            curve: AnycastMotion.standardCurve,
            height: 56,
            decoration: BoxDecoration(
              color: isSelected
                  ? AnycastColor.sandAlpha2(theme.brightness)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AnycastRadius.pill),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(height: AnycastSpacing.xs),
                Text(
                  text,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ));
    });
  }
}
