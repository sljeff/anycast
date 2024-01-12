import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/detail.dart';
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
              child: Image.network(
                episodes[index].imageUrl!,
                fit: BoxFit.cover,
                width: 48,
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
            ButtonBar(
                alignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                      onPressed: () {
                        var player = Get.find<PlayerController>();
                        var feedsController = Get.find<FeedEpisodeController>();
                        player.pause().then((_) {
                          feedsController
                              .addToTop(1, episodes[index])
                              .then((p) {
                            player.playByEpisode(p);
                          });
                        });
                      },
                      icon: const Icon(Icons.play_arrow)),
                  IconButton(
                      onPressed: () {
                        var feedsController = Get.find<FeedEpisodeController>();
                        feedsController.addToPlaylist(1, episodes[index]);
                      },
                      icon: const Icon(Icons.playlist_add)),
                  deleteButton
                      ? IconButton(
                          onPressed: () {
                            var feedsController =
                                Get.find<FeedEpisodeController>();
                            feedsController
                                .removeByGuids([episodes[index].guid!]);
                          },
                          icon: const Icon(Icons.delete),
                        )
                      : const SizedBox.shrink(),
                ].where((element) {
                  // if type is not IconButton, return false
                  return element.runtimeType == IconButton;
                }).toList()),
          ],
        );
      },
    );
  }
}
