import 'dart:convert';
import 'dart:ui';

import 'package:anycast/api/subtitles.dart';
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
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:marquee/marquee.dart';

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
              appBar: MyAppBar(
                title: 'PLAYLIST',
                icon: Icons.history_rounded,
                iconOnTap: () {
                  Get.dialog(const HistoryBlock());
                },
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
          return Column(
            children: [
              Container(
                alignment: Alignment.center,
                height: 300,
                child: Text(
                  'All caught up?\n\nExplore new shows!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontFamily: GoogleFonts.comfortaa().fontFamily,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.40,
                  ),
                ),
              ),
              SizedBox(
                width: 262,
                child: TextButton(
                  onPressed: () {
                    Get.find<HomeTabController>().onItemTapped(2);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Iconify(
                        Ic.baseline_explore,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Explore',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontFamily: GoogleFonts.comfortaa().fontFamily,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        var playerController = Get.find<PlayerController>();
        var isPlaying = playerController.isPlaying.value &&
            playerController.player.value.currentPlaylistId ==
                controller.playlistId;
        var clController = Get.find<CardListController>(
            tag: 'playlits${controller.playlistId}');

        return Container(
          padding: const EdgeInsets.only(left: 24, right: 24),
          child: ReorderableListView.builder(
            onReorder: controller.move,
            onReorderStart: (index) {
              clController.close();
            },
            footer: const SizedBox(height: 12),
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
            padding: const EdgeInsets.only(top: 12),
            itemCount: controller.episodes.length,
            itemBuilder: (context, index) {
              var episode = controller.episodes[index];
              return Padding(
                key: Key(episode.enclosureUrl!),
                padding: const EdgeInsets.only(bottom: 12),
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
                            clController.expand(0);
                          }
                        },
                      ),
                      card.CardBtn(
                        icon: AIIcon(
                          size: 24,
                          enclosureUrl: episode.enclosureUrl!,
                          color: Colors.black,
                        ),
                        onPressed: () {
                          var stController = Get.find<SubtitleController>();
                          switch (stController
                              .subtitleUrls[episode.enclosureUrl!]) {
                            case null:
                              getSubtitles(episode.enclosureUrl!).then((value) {
                                var subtitle = '';
                                if (value.status == 'succeeded') {
                                  subtitle = jsonEncode(value.subtitles);
                                }
                                stController.add(episode.enclosureUrl!,
                                    value.status!, subtitle);
                              });
                              Get.snackbar(
                                'Processing',
                                'Subtitle generating, please wait...',
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            case 'failed':
                              stController.remove(episode.enclosureUrl!);
                              Get.snackbar(
                                'Error',
                                'Subtitle download failed, please try again later.',
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            case 'succeeded':
                              Get.snackbar(
                                'Success',
                                'You can check the subtitles when playing.',
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            case 'processing':
                              Get.snackbar(
                                'Generating',
                                'Generating transcript may take a few minutes...',
                                snackPosition: SnackPosition.BOTTOM,
                              );
                          }
                        },
                      ),
                      card.CardBtn(
                        icon: const Iconify(Ic.round_clear),
                        onPressed: () {
                          controller.remove(episode.guid!);
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
            title: Center(
          child: Text(
            'No history',
            style: TextStyle(
              color: Colors.white,
              decoration: TextDecoration.none,
            ),
          ),
        ));
      }

      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 400,
          width: 300,
          child: ListView.separated(
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
            itemCount: controller.episodes.length,
            itemBuilder: (context, index) {
              var episode = controller.episodes[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey,
                    width: 1,
                  ),
                ),
                child: GestureDetector(
                  onTap: () {
                    Get.bottomSheet(Detail(episode: episode, actions: [
                      card.CardBtn(
                          icon: const Iconify(Ic.round_play_arrow),
                          onPressed: () {
                            var ep = controller.toFeedEpisode(episode);
                            Get.find<FeedEpisodeController>()
                                .addToTop(1, ep)
                                .then((value) {
                              Get.find<PlayerController>().playByEpisode(value);
                            });
                          }),
                      card.CardBtn(
                          icon: const Iconify(Ic.round_clear),
                          onPressed: () {
                            controller.delete(episode.enclosureUrl!);
                          }),
                    ]));
                  },
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: episode.imageUrl!,
                          width: 48,
                          height: 48,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 20,
                              child: Marquee(
                                text: episode.title!,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontFamily:
                                      GoogleFonts.comfortaa().fontFamily,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.40,
                                ),
                                blankSpace: 72,
                                startAfter: const Duration(seconds: 1),
                                startPadding: 12,
                              ),
                            ),
                            Text(
                              episode.channelTitle!,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                color: const Color(0xFF10B981),
                                fontSize: 12,
                                fontFamily: GoogleFonts.comfortaa().fontFamily,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.40,
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
                          padding: const EdgeInsets.all(6),
                          style: IconButton.styleFrom(
                            shape: const CircleBorder(),
                            backgroundColor: Colors.white,
                          ),
                          icon: const Iconify(Ic.clear, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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
