/*
有三种 card:
1. inbox 里面，点击是播放、添加到播放列表、移除
2. 播放列表里面，点击是播放、AI 生成、移除
3. 频道页里面，点击是播放、添加到播放列表

播放列表的卡片有背景表示播放进度
*/
import 'package:anycast/models/episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/pages/channel.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/detail.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

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
      () => Column(
        children: [
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
                          image: CachedNetworkImageProvider(episode.imageUrl!),
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
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'PingFangSC-Regular,PingFang SC',
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 94,
                              child: Text(
                                episode.channelTitle!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontFamily: 'PingFangSC-Regular,PingFang SC',
                                  fontWeight: FontWeight.w500,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 124,
                              child: Text(
                                '${formatDuration(episode.duration!)} • ${formatDatetime(episode.pubDate!)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 12,
                                  fontFamily: 'PingFangSC-Regular,PingFang SC',
                                  fontWeight: FontWeight.w400,
                                  height: 0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          htmlToText(episode.description),
                          style: TextStyle(
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
      ),
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
        context.pushTransparentRoute(Channel(
          rssFeedUrl: subscription.rssFeedUrl!,
        ));
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
                height: 80,
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
                    Hero(
                      tag: subscription.imageUrl!,
                      child: Container(
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
                              height: 16,
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
