import 'dart:ui';

import 'package:anycast/design_system/anycast_components.dart';
import 'package:anycast/design_system/anycast_theme.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/history.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/widgets/appbar.dart';
import 'package:anycast/widgets/card.dart' as card;
import 'package:anycast/widgets/detail.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:get/get.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';

class Playlists extends GetView<PlaylistController> {
  const Playlists({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(HistoryController());

    return Obx(
      () {
        var playlists = controller.playlists;
        var episodesControllers = controller.episodesControllers;

        for (var c in episodesControllers) {
          Get.lazyPut<CardListController>(
            () => CardListController(),
            tag: 'playlits${c.playlistId}',
          );
        }

        return DefaultTabController(
          length: playlists.length,
          child: Scaffold(
              appBar: const MyAppBar(
                title: 'PLAYLIST',
              ),
              body: TabBarView(
                  children: episodesControllers
                      .map((element) => PlaylistEpisodesList(
                          key: Key(element.playlistId.toString()),
                          controller: element))
                      .toList())),
        );
      },
    );
  }
}

class PlaylistEpisodesList extends StatelessWidget {
  final PlaylistEpisodeController controller;

  const PlaylistEpisodesList({required Key key, required this.controller})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        if (controller.episodes.isEmpty) {
          return AnycastEmptyState(
            icon: Icons.queue_music_rounded,
            title: 'All caught up?',
            message: 'Explore new shows!',
            action: FilledButton.icon(
              onPressed: () {
                Get.find<HomeTabController>().onItemTapped(2);
              },
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Explore'),
            ),
          );
        }

        var playerController = Get.find<PlayerController>();
        var isPlaying = playerController.isPlaying.value &&
            playerController.player.value.currentPlaylistId ==
                controller.playlistId;
        var clController = Get.find<CardListController>(
            tag: 'playlits${controller.playlistId}');

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AnycastSpacing.pageH),
          child: ReorderableListView.builder(
            onReorder: controller.move,
            onReorderStart: (index) {
              clController.close();
            },
            footer: const SizedBox(height: AnycastSpacing.gap),
            proxyDecorator:
                (Widget child, int index, Animation<double> animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (BuildContext context, Widget? child) {
                  final double animValue =
                      Curves.easeInOut.transform(animation.value);
                  return Transform.scale(
                    scale: lerpDouble(1, 1.1, animValue),
                    child: child,
                  );
                },
                child: child,
              );
            },
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(
              top: AnycastSpacing.gap,
              bottom: AnycastSpacing.pageBottomSafe,
            ),
            itemCount: controller.episodes.length,
            itemBuilder: (context, index) {
              var episode = controller.episodes[index];
              return Padding(
                key: Key(episode.enclosureUrl!),
                padding: const EdgeInsets.only(bottom: AnycastSpacing.gap),
                child: MyReorderableDelayedDragStartListener(
                  delay: const Duration(milliseconds: 150),
                  index: index,
                  child: card.Card(
                    episode: episode,
                    index: index,
                    clController: clController,
                    actions: [
                      card.CardBtn(
                        icon: PlayIcon(
                          size: 24,
                          enclosureUrl: episode.enclosureUrl!,
                        ),
                        onPressed: () {
                          if (isPlaying && index == 0) {
                            playerController.pause();
                          } else {
                            controller.moveToTop(episode);
                            playerController.playByEpisode(episode);
                          }
                        },
                      ),
                      card.CardBtn(
                        icon: AIIcon(
                          size: 24,
                          enclosureUrl: episode.enclosureUrl!,
                        ),
                        onPressed: () {
                          var stController = Get.find<SubtitleController>();
                          switch (stController
                              .subtitleUrls[episode.enclosureUrl!]) {
                            case null:
                              stController.add(episode.enclosureUrl!);
                            case 'failed':
                              stController.remove(episode.enclosureUrl!);
                              Get.snackbar(
                                'Error',
                                'Transcript generation failed, please try again later.',
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            case 'succeeded':
                              Get.snackbar(
                                'Success',
                                'You can check the transcript when playing.',
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            case 'processing':
                              Get.snackbar(
                                'Generating',
                                'Generating transcript may take 2 ~ 5 minutes...',
                                snackPosition: SnackPosition.BOTTOM,
                              );
                          }
                        },
                      ),
                      card.CardBtn(
                        icon: const Iconify(Ic.round_clear),
                        onPressed: () {
                          controller.remove(episode.enclosureUrl!);
                          if (index == 0) {
                            playerController.clear();
                          }
                        },
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class HistoryBlock extends StatelessWidget {
  static final clController = Get.put(CardListController(), tag: 'history');
  static final controller = Get.find<HistoryController>();

  const HistoryBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (controller.episodes.isEmpty) {
        return const AlertDialog(
          title: Text('No history'),
        );
      }

      return Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: AnycastSpacing.pageH),
        child: Container(
          padding: const EdgeInsets.only(
            left: AnycastSpacing.gap,
            right: AnycastSpacing.gap,
            top: AnycastSpacing.gap,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          height: 400,
          width: 300,
          child: Column(
            children: [
              Expanded(
                child: ListView.separated(
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AnycastSpacing.gap),
                  padding: const EdgeInsets.only(
                    left: AnycastSpacing.gap,
                    right: AnycastSpacing.gap,
                    top: AnycastSpacing.gap,
                  ),
                  itemCount: controller.episodes.length,
                  itemBuilder: (context, index) {
                    var episode = controller.episodes[index];
                    return Container(
                      padding: const EdgeInsets.all(AnycastSpacing.gap),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AnycastRadius.md),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                              useSafeArea: true,
                              isScrollControlled: true,
                              context: context,
                              builder: (context) =>
                                  Detail(episode: episode, actions: [
                                    card.CardBtn(
                                        icon:
                                            const Iconify(Ic.round_play_arrow),
                                        onPressed: () {
                                          var ep =
                                              controller.toFeedEpisode(episode);
                                          Get.find<FeedEpisodeController>()
                                              .addToTop(1, ep)
                                              .then((value) {
                                            Get.find<PlayerController>()
                                                .playByEpisode(value);
                                          });
                                        }),
                                    card.CardBtn(
                                        icon: const Iconify(Ic.round_clear),
                                        onPressed: () {
                                          controller
                                              .delete(episode.enclosureUrl!);
                                        }),
                                  ]));
                        },
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: episode.imageUrl ??
                                    "https://placeholder.co/48.png?text=NoImage",
                                width: 48,
                                height: 48,
                              ),
                            ),
                            const SizedBox(width: AnycastSpacing.gap),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    episode.title!,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    episode.channelTitle!,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                onPressed: () {
                                  controller.delete(episode.enclosureUrl!);
                                },
                                padding:
                                    const EdgeInsets.all(AnycastSpacing.sm),
                                style: IconButton.styleFrom(
                                  shape: const CircleBorder(),
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .inverseSurface,
                                ),
                                icon: Iconify(
                                  Ic.clear,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () {
                  controller.deleteAll();
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red[400],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  "Clear All",
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onError,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class MyReorderableDelayedDragStartListener
    extends ReorderableDragStartListener {
  final Duration delay;

  const MyReorderableDelayedDragStartListener({
    this.delay = kLongPressTimeout,
    super.key,
    required super.child,
    required super.index,
    super.enabled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(delay: delay, debugOwner: this);
  }
}
