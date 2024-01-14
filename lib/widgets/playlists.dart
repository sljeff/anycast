import 'package:anycast/states/player.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/widgets/detail.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:get/get.dart';

class Playlists extends StatelessWidget {
  final PlaylistController controller = Get.put(PlaylistController());

  Playlists({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        var playlists = controller.playlists;
        var episodesControllers = controller.episodesControllers;

        return DefaultTabController(
          length: playlists.length,
          child: Scaffold(
              appBar: AppBar(
                title: const Text('Playlists'),
                bottom: TabBar(
                    tabs: playlists.map((playlist) {
                  return Tab(text: playlist.title);
                }).toList()),
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
        var playerController = Get.find<PlayerController>();
        var isPlaying = playerController.isPlaying.value &&
            playerController.player.value.currentPlaylistId ==
                controller.playlistId;
        return ListView.builder(
          itemCount: controller.episodes.length,
          itemBuilder: (context, index) {
            var episode = controller.episodes[index];
            return ExpansionTile(
              controlAffinity: ListTileControlAffinity.leading,
              leading: episode.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                              context: context,
                              builder: (context) => DetailWidget(episode));
                        },
                        child: CachedNetworkImage(
                          imageUrl: episode.imageUrl!,
                          width: 48,
                          height: 48,
                          placeholder: (context, url) => const Icon(
                            Icons.image,
                          ),
                          errorWidget: (context, url, error) => const Icon(
                            Icons.image_not_supported,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.image),
                    ),
              title: Text(episode.title!, style: const TextStyle(fontSize: 14)),
              subtitle: Row(
                children: [
                  Text(
                    episode.channelTitle!,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                        color: Colors.brown),
                  ),
                  const Text(
                    " • ",
                    style: TextStyle(fontSize: 9),
                  ),
                  Text(
                    formatRemainingTime(
                      Duration(milliseconds: episode.duration!),
                      Duration(milliseconds: episode.playedDuration ?? 0),
                    ),
                    style: const TextStyle(fontSize: 9),
                  ),
                  const Text(
                    " • ",
                    style: TextStyle(fontSize: 9),
                  ),
                  Text(
                    formatDatetime(episode.pubDate!),
                    style: const TextStyle(fontSize: 9),
                  ),
                ],
              ),
              children: [
                ButtonBar(
                  alignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                        onPressed: () {
                          if (index != 0) {
                            playerController.pause().then((value) => {
                                  controller.moveToTop(episode).then((value) {
                                    playerController.playByEpisode(episode);
                                  })
                                });
                          } else {
                            if (isPlaying) {
                              playerController.pause();
                              return;
                            }
                            playerController.playByEpisode(episode);
                          }
                        },
                        icon: index != 0
                            ? const Icon(Icons.play_arrow)
                            : const PlayIcon()),
                    IconButton(
                        onPressed: () {
                          if (index != 0) {
                            controller.remove(episode.guid!);
                            return;
                          }
                          playerController.pause();
                          controller.removeTop();
                          // if playing, play next
                          if (isPlaying) {
                            playerController
                                .playByEpisode(controller.episodes[0]);
                          }
                        },
                        icon: Icon(Icons.delete)),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
