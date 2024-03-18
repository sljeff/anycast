import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/pages/detail.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FeedsEpisodesListView extends StatelessWidget {
  final List<FeedEpisodeModel> episodes;
  final bool deleteButton;

  const FeedsEpisodesListView(this.episodes, this.deleteButton, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        return ExpansionTile(
          controlAffinity: ListTileControlAffinity.leading,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: GestureDetector(
              onTap: () {
                // show bottom sheet
                showModalBottomSheet(
                    context: context,
                    builder: (context) => DetailWidget(episodes[index]));
              },
              child: CachedNetworkImage(
                imageUrl: episodes[index].imageUrl!,
                fit: BoxFit.cover,
                width: 48,
                placeholder: (context, url) => const Icon(
                  Icons.image,
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.image_not_supported,
                ),
              ),
            ),
          ),
          title: Text(
            episodes[index].title!,
            style: const TextStyle(
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    episodes[index].channelTitle!.substring(
                          0,
                          episodes[index].channelTitle!.length > 20
                              ? 20
                              : episodes[index].channelTitle!.length,
                        ),
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
                    episodes[index].duration != null
                        ? formatDuration(episodes[index].duration!)
                        : '',
                    style: const TextStyle(
                      fontSize: 9,
                    ),
                  ),
                  const Text(
                    " • ",
                    style: TextStyle(fontSize: 9),
                  ),
                  Text(
                    episodes[index].pubDate != null
                        ? formatDatetime(episodes[index].pubDate!)
                        : '',
                    style: const TextStyle(
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              Text(
                htmlToText(episodes[index].description!)!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                ),
              ),
            ],
          ),
          children: [
            Obx(
              () => FeedsEpisodeButtonBarWidget(
                  episode: episodes[index], deleteButton: deleteButton),
            ),
          ],
        );
      },
    );
  }
}

class FeedsEpisodeButtonBarWidget extends StatelessWidget {
  const FeedsEpisodeButtonBarWidget({
    super.key,
    required this.episode,
    required this.deleteButton,
  });

  final FeedEpisodeModel episode;
  final bool deleteButton;

  @override
  Widget build(BuildContext context) {
    var playerController = Get.find<PlayerController>();
    var playlistController = Get.find<PlaylistController>();
    var isPlaying = playerController.isPlayingEpisode(episode.enclosureUrl!);
    var inPlaylist = playlistController.isInPlaylists(episode.enclosureUrl!);

    var playButton = IconButton(
        onPressed: () {
          if (isPlaying) {
            playerController.pause();
            return;
          }
          var feedsController = Get.find<FeedEpisodeController>();
          playerController.pause().then((_) {
            feedsController.addToTop(1, episode).then((p) {
              playerController.playByEpisode(p);
            });
          });
        },
        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow));
    var addButton = IconButton(
        onPressed: () {
          if (inPlaylist) {
            playlistController.removeByGuid(episode.guid!);
            return;
          }
          var feedsController = Get.find<FeedEpisodeController>();
          feedsController.addToPlaylist(1, episode);
        },
        icon: Icon(inPlaylist ? Icons.playlist_add_check : Icons.add));

    List<IconButton> btns = [playButton, addButton];
    if (deleteButton) {
      btns.add(IconButton(
          onPressed: () {
            var feedsController = Get.find<FeedEpisodeController>();
            feedsController.removeByGuids([episode.guid!]);
          },
          icon: const Icon(Icons.delete)));
    }

    return ButtonBar(
      alignment: MainAxisAlignment.spaceEvenly,
      children: btns,
    );
  }
}
