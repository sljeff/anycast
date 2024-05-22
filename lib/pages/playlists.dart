import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/widgets/appbar.dart';
import 'package:anycast/widgets/card.dart' as card;
import 'package:anycast/widgets/play_icon.dart';
import 'package:flutter/material.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';

class Playlists extends GetView<PlaylistController> {
  const Playlists({super.key});

  @override
  Widget build(BuildContext context) {
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
                icon: Icons.history_rounded,
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

        return ListView.separated(
          padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemCount: controller.episodes.length,
          itemBuilder: (context, index) {
            var episode = controller.episodes[index];
            return card.Card(
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
                    switch (stController.subtitleUrls[episode.enclosureUrl!]) {
                      case null:
                        getSubtitles(episode.enclosureUrl!).then((value) {
                          var subtitle = '';
                          if (value.status == 'succeeded') {
                            subtitle = jsonEncode(value.subtitles);
                          }
                          stController.add(
                              episode.enclosureUrl!, value.status!, subtitle);
                        });
                        Get.snackbar(
                          'Processing',
                          'Subtitle downloading...',
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
                          'You can view subtitles in the player page.',
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
            );
          },
        );
      },
    );
  }
}
