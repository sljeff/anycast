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
    var barWidth = MediaQuery.of(context).size.width - 48;

    var rightText =
        '${formatDuration(episode.duration!)} • ${formatDatetime(episode.pubDate!)}';
    var playedWidth = 0.0;
    if (episode is PlaylistEpisodeModel) {
      var pe = episode as PlaylistEpisodeModel;
      if (pe.playedDuration != null && pe.playedDuration! > 0) {
        rightText = formatRemainingTime(
          Duration(milliseconds: pe.duration!),
          Duration(milliseconds: pe.playedDuration!),
        );
        playedWidth = (pe.playedDuration! / pe.duration!) * barWidth;
      }
    }

    return Obx(
      () {
        Widget back = Container(
          width: playedWidth,
          height: 100,
          color: Colors.white.withOpacity(0.1),
        );

        var playerController = Get.find<PlayerController>();
        if (episode is PlaylistEpisodeModel &&
            playerController.playlistEpisode.value.enclosureUrl ==
                episode.enclosureUrl) {
          back = Obx(() {
            var positionData = playerController.positionData.value;
            playedWidth = positionData.position.inMilliseconds /
                positionData.duration.inMilliseconds *
                barWidth;
            return Container(
              width: playedWidth,
              height: 98,
              color: Colors.white.withOpacity(0.1),
            );
          });
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
                                  image: CachedNetworkImageProvider(
                                      episode.imageUrl!),
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
                                        maxWidth: 130,
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
                                      color: Colors.blue.withOpacity(0.7),
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
                                  color: Colors.green.withOpacity(0.7),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children:
                    clController.expandedIndex.value == index ? actions : [],
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
    return GestureDetector(
      onTap: () {
        onPressed();
      },
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        width: 48,
        height: 48,
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(36),
          ),
        ),
        child: FractionallySizedBox(
          widthFactor: 0.5,
          heightFactor: 0.5,
          child: icon,
        ),
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
                            subscription.imageUrl!,
                          ),
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
