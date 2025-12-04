/*
有三种 card:
1. inbox 里面，点击是播放、添加到播放列表、移除
2. 播放列表里面，点击是播放、AI 生成、移除
3. 频道页里面，点击是播放、添加到播放列表

播放列表的卡片有背景表示播放进度
*/
import 'package:anycast/models/episode.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/pages/channel.dart';
import 'package:anycast/states/cache.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/detail.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:iconify_flutter/icons/icon_park_solid.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:percent_indicator/percent_indicator.dart';

class Card extends StatelessWidget {
  final Episode episode;
  final List<CardBtn> actions;
  final int index;
  final CardListController clController;

  const Card({
    super.key,
    required this.episode,
    required this.actions,
    required this.index,
    required this.clController,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        var barWidth = MediaQuery.of(context).size.width - 48;

        var rightText =
            '${formatDuration(episode.duration ?? 0)} • ${formatDatetime(episode.pubDate!)}';
        var playedWidth = 0.0;

        Widget back = Container(
          width: playedWidth,
          height: 100,
          color: Colors.white.withValues(alpha: 0.1),
        );

        if (episode is PlaylistEpisodeModel) {
          var pe = episode as PlaylistEpisodeModel;
          if (pe.playedDuration != null && pe.playedDuration! > 0) {
            rightText = formatRemainingTime(
              Duration(milliseconds: pe.duration ?? 0),
              Duration(milliseconds: pe.playedDuration!),
            );
          }

          var playerController = Get.find<PlayerController>();

          if (pe.enclosureUrl ==
              playerController.playlistEpisode.value.enclosureUrl) {
            var positionData = playerController.positionData.value;
            if (positionData.duration.inMilliseconds != 0 &&
                positionData.position.inMilliseconds != 0) {
              playedWidth = positionData.position.inMilliseconds /
                  positionData.duration.inMilliseconds *
                  barWidth;
            }
            back = Container(
              width: playedWidth,
              height: 100,
              color: Colors.white.withValues(alpha: 0.1),
            );
          } else {
            if (pe.duration != null) {
              playedWidth =
                  ((pe.playedDuration ?? 0) / pe.duration!) * barWidth;
            }
            back = Container(
              width: playedWidth,
              height: 100,
              color: Colors.white.withValues(alpha: 0.1),
            );
          }
        }

        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    child: back,
                  ),
                  GestureDetector(
                    onTap: () {
                      clController.expand(index);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: ShapeDecoration(
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: Colors.grey.shade800,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                useSafeArea: true,
                                isScrollControlled: true,
                                context: context,
                                builder: (context) =>
                                    Detail(episode: episode, actions: actions),
                              );
                            },
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: ShapeDecoration(
                                image: DecorationImage(
                                  image: CachedNetworkImageProvider(episode
                                          .imageUrl ??
                                      'https://placeholder.co/48.png?text=NoImage'),
                                  fit: BoxFit.fill,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  episode.title!,
                                  style: const TextStyle(
                                    decoration: TextDecoration.none,
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontFamily:
                                        'PingFangSC-Regular,PingFang SC',
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 114,
                                      ),
                                      child: Text(
                                        episode.channelTitle!,
                                        style: const TextStyle(
                                          decoration: TextDecoration.none,
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontFamily:
                                              'PingFangSC-Regular,PingFang SC',
                                          fontWeight: FontWeight.w500,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      rightText,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        decoration: TextDecoration.none,
                                        color: Color(0xFF6B7280),
                                        fontSize: 12,
                                        fontFamily:
                                            'PingFangSC-Regular,PingFang SC',
                                        fontWeight: FontWeight.w400,
                                        height: 0,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                                Text(
                                  htmlToText(episode.description),
                                  style: TextStyle(
                                    decoration: TextDecoration.none,
                                    color: const Color(0xFF6B7280),
                                    fontSize: 12,
                                    fontFamily: GoogleFonts.inter().fontFamily,
                                    fontWeight: FontWeight.w400,
                                    height: 0,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                )
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                      right: 12,
                      bottom: 16,
                      child: episode is! PlaylistEpisodeModel
                          ? const SizedBox.shrink()
                          : Obx(() {
                              var controller = Get.find<CacheController>();
                              var progress =
                                  controller.get(episode.enclosureUrl!);
                              if (progress == null) {
                                return GestureDetector(
                                  onTap: () {
                                    controller.download(episode.enclosureUrl!);
                                  },
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.blue.withValues(alpha: 0.7),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Iconify(
                                      Ic.round_download,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                );
                              }
                              if (progress >= 1) {
                                return Iconify(
                                  IconParkSolid.check_one,
                                  color: Colors.green.withValues(alpha: 0.7),
                                  size: 16,
                                );
                              }
                              return CircularPercentIndicator(
                                radius: 8,
                                lineWidth: 3,
                                percent: progress,
                                progressColor: Colors.blue,
                              );
                            })),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              height: clController.expandedIndex.value == index ? 60 : 0,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children:
                      clController.expandedIndex.value == index ? actions : [],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CardBtn extends StatelessWidget {
  final Widget icon;
  final Function() onPressed;

  const CardBtn({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: icon,
      padding: const EdgeInsets.all(12),
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        backgroundColor: Colors.white,
      ),
    );
  }
}

class PodcastCard extends StatelessWidget {
  final SubscriptionModel subscription;

  const PodcastCard({super.key, required this.subscription});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Get.lazyPut(() => ChannelController(channel: subscription),
            tag: subscription.rssFeedUrl);
        showMaterialModalBottomSheet(
          expand: true,
          context: context,
          builder: (context) {
            return Channel(rssFeedUrl: subscription.rssFeedUrl!);
          },
          closeProgressThreshold: 0.9,
        );
      },
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 12),
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      width: 1,
                      color: Colors.grey.shade800,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: ShapeDecoration(
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(
                              subscription.imageUrl ??
                                  'https://placeholder.co/48.png?text=NoImage'),
                          fit: BoxFit.fill,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: ShapeDecoration(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: const BoxDecoration(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      child: Text(
                                        subscription.title!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          decoration: TextDecoration.none,
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontFamily: GoogleFonts.comfortaa()
                                              .fontFamily,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subscription.description!,
                              style: const TextStyle(
                                decoration: TextDecoration.none,
                                color: Colors.white,
                                fontSize: 12,
                                fontFamily: 'PingFangSC-Regular,PingFang SC',
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const tablerTopology =
    '<svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24"><path fill="none" stroke="white" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19a2 2 0 1 0-4 0a2 2 0 0 0 4 0m8-14a2 2 0 1 0-4 0a2 2 0 0 0 4 0m-8 0a2 2 0 1 0-4 0a2 2 0 0 0 4 0m-4 7a2 2 0 1 0-4 0a2 2 0 0 0 4 0m12 7a2 2 0 1 0-4 0a2 2 0 0 0 4 0m-4-7a2 2 0 1 0-4 0a2 2 0 0 0 4 0m8 0a2 2 0 1 0-4 0a2 2 0 0 0 4 0M6 12h4m4 0h4m-3-5l-2 3M9 7l2 3m0 4l-2 3m4-3l2 3"/></svg>';
const newDoc =
    '<svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24"><path fill="white" d="M16.08 6.63c-.07-.1-.15-.19-.23-.27h-.01a2.85 2.85 0 0 0-1.11-.69l-1.38-.45c-.1-.04-.2-.11-.26-.2a.5.5 0 0 1-.1-.31a.5.5 0 0 1 .1-.31c.06-.09.15-.16.26-.2l1.38-.45c.42-.14.79-.38 1.1-.69c.29-.3.52-.67.67-1.07v-.03l.45-1.38c.04-.1.11-.2.2-.26a.5.5 0 0 1 .31-.1c.11 0 .22.04.31.1s.16.15.2.26l.45 1.38c.14.42.38.8.69 1.11c.31.32.69.55 1.11.69l1.38.45h.03c.1.04.19.11.26.2s.1.2.1.31a.5.5 0 0 1-.1.31c-.06.09-.15.16-.26.2l-1.38.45c-.42.14-.8.38-1.11.69c-.32.31-.55.69-.69 1.11l-.46 1.38v.03c-.04.09-.11.17-.19.23a.5.5 0 0 1-.31.1a.5.5 0 0 1-.31-.1a.52.52 0 0 1-.2-.26l-.45-1.38c-.1-.31-.25-.6-.45-.85m7.7 3.8l-.77-.24c-.24-.08-.45-.21-.62-.38c-.17-.18-.3-.39-.38-.62l-.25-.76a.33.33 0 0 0-.11-.15a.27.27 0 0 0-.34 0c-.05.04-.09.09-.11.15l-.25.76c-.07.23-.2.44-.37.61s-.38.3-.61.38l-.77.25c-.06.02-.11.06-.15.11a.27.27 0 0 0 0 .34c.04.05.09.09.15.11l.77.25c.23.07.45.21.62.38s.3.39.38.62l.25.76c.02.06.06.11.11.15a.27.27 0 0 0 .34 0c.05-.04.09-.09.11-.15l.25-.76c.08-.24.21-.45.38-.62c.18-.17.39-.3.62-.38l.77-.25c.06-.02.11-.06.15-.11s.05-.11.05-.17s-.01-.12-.05-.17s-.106-.08-.17-.11m-4.24 2.28l.26.8c.05.14.12.25.2.37v6.08c0 1.24-1.01 2.25-2.25 2.25H6.25C5.01 22.21 4 21.2 4 19.96V4.46c0-1.24 1.01-2.25 2.25-2.25h8.26c-.07.04-.15.08-.22.11l-1.42.46c-.4.15-.75.4-.99.75a2 2 0 0 0-.38 1.18c0 .43.13.84.37 1.18c.078.112.178.202.275.289l.045.041H7.75c-.41 0-.75.34-.75.75s.34.75.75.75h7.24l.035.058a1 1 0 0 1 .085.162l.46 1.41c.14.4.4.74.75.99c.35.24.76.37 1.18.37c0 .37.11.73.33 1.04s.52.53.91.67zm-11.79 5h8.5c.41 0 .75-.34.75-.75s-.34-.75-.75-.75h-8.5c-.41 0-.75.34-.75.75s.34.75.75.75m0-5h8.5c.41 0 .75-.34.75-.75s-.34-.75-.75-.75h-8.5c-.41 0-.75.34-.75.75s.34.75.75.75"/></svg>';
