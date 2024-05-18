/*
有三种 card:
1. inbox 里面，点击是播放、添加到播放列表、移除
2. 播放列表里面，点击是播放、AI 生成、移除
3. 频道页里面，点击是播放、添加到播放列表

播放列表的卡片有背景表示播放进度
*/
import 'package:anycast/models/episode.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/styles.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/widgets/detail.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Card extends StatelessWidget {
  final Episode episode;
  final List<Widget> actions;
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
              height: 96,
              padding: const EdgeInsets.all(8),
              decoration: ShapeDecoration(
                color: DarkColor.primaryBackground,
                shape: RoundedRectangleBorder(
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
                        builder: (context) => Detail(episode),
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
                          style: DarkColor.defaultTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 80,
                              child: Text(
                                episode.channelTitle!,
                                style: DarkColor.cardTextLight,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: 120,
                              child: Text(
                                '${formatDuration(episode.duration!)} • ${formatDatetime(episode.pubDate!)}',
                                textAlign: TextAlign.right,
                                style: DarkColor.defaultText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: clController.expandedIndex.value == index ? 60 : 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children:
                  clController.expandedIndex.value == index ? actions : [],
            ),
          ),
        ],
      ),
    );
  }
}

class CardList extends StatelessWidget {
  final List<Episode> episodes;
  final CardListController controller;

  const CardList({
    super.key,
    required this.episodes,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => ListView.separated(
        padding: const EdgeInsets.only(top: 12),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemCount: episodes.length,
        itemBuilder: (context, index) {
          return Card(
            episode: episodes[index],
            index: index,
            clController: controller,
            actions: [
              IconButton(
                color: Colors.red,
                icon: const Icon(FluentIcons.play_32_filled),
                onPressed: () {},
              ),
              IconButton(
                color: Colors.red,
                icon: const Icon(FluentIcons.add_32_filled),
                onPressed: () {},
              ),
              IconButton(
                color: Colors.red,
                icon: const Icon(FluentIcons.delete_32_filled),
                onPressed: () {},
              ),
            ],
          );
        },
      ),
    );
  }
}
