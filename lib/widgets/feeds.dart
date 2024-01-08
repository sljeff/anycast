import 'dart:convert';
import 'dart:io';
import 'package:anycast/states/import_block.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/widgets/detail.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:webfeed_plus/webfeed_plus.dart';

import 'package:flutter/material.dart';
import 'package:anycast/models/feed_episode.dart';
import 'package:file_picker/file_picker.dart';
import 'package:anycast/models/subscription.dart';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser;

class Feeds extends StatelessWidget {
  Feeds({Key? key}) : super(key: key);

  final FeedEpisodeController controller = Get.put(FeedEpisodeController());

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.episodes.isEmpty) {
        return ImportBlock();
      }
      return ListView.builder(
        itemCount: controller.episodes.length,
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
                      builder: (context) =>
                          DetailWidget(controller.episodes[index]));
                },
                child: Image.network(
                  controller.episodes[index].imageUrl!,
                  fit: BoxFit.cover,
                  width: 48,
                ),
              ),
            ),
            title: Text(
              controller.episodes[index].title!,
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
                      controller.episodes[index].channelTitle!,
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
                      controller.episodes[index].duration != null
                          ? formatDuration(controller.episodes[index].duration!)
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
                      controller.episodes[index].pubDate != null
                          ? formatDatetime(controller.episodes[index].pubDate!)
                          : '',
                      style: const TextStyle(
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
                Text(
                  htmlToText(controller.episodes[index].description!)!,
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
                        controller
                            .addToPlaylist(controller.episodes[index])
                            .then((value) {
                          Get.find<PlayerController>().playByEpisode(value);
                        });
                      },
                      icon: const Icon(Icons.play_arrow)),
                  IconButton(
                      onPressed: () {
                        controller.addToPlaylist(controller.episodes[index]);
                      },
                      icon: const Icon(Icons.playlist_add)),
                  IconButton(
                      onPressed: () {
                        controller
                            .removeByGuids([controller.episodes[index].guid!]);
                      },
                      icon: const Icon(Icons.delete)),
                ],
              ),
            ],
          );
        },
      );
    });
  }
}

class ImportBlock extends StatelessWidget {
  final ImportBlockController controller = Get.put(ImportBlockController());

  ImportBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      }
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('No feeds found. Maybe you can:'),
            const SizedBox(height: 16),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    // select xml file
                    FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['xml'],
                    ).then((value) {
                      if (value != null) {
                        controller.isLoading.value = true;
                        parseOMPL(value.files.single.path).then((value) {
                          fetchPodcastsByUrls(value).then((value) {
                            Get.find<FeedEpisodeController>().addMany(
                                value.map((e) => e.feedEpisode!).toList());
                            Get.find<SubscriptionController>().addMany(
                                value.map((e) => e.subscription!).toList());
                            controller.isLoading.value = false;
                          });
                        });
                      }
                    });
                  },
                  child: const Text('Import OMPL'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Get.find<HomeTabController>().onItemTapped(2);
                  },
                  child: const Text('Search Podcasts'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  height: 50,
                  child: TextField(
                    style: const TextStyle(fontSize: 10),
                    controller: controller.textController,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(1),
                      border: const OutlineInputBorder(),
                      labelText: 'Enter a Podcast URL',
                      suffixIcon: IconButton(
                        onPressed: () {
                          controller.isLoading.value = true;
                          fetchPodcastsByUrls([controller.textController.text])
                              .then((value) {
                            Get.find<FeedEpisodeController>().addMany(
                                value.map((e) => e.feedEpisode!).toList());
                            Get.find<SubscriptionController>().addMany(
                                value.map((e) => e.subscription!).toList());
                            controller.isLoading.value = false;
                          });
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

Future<List<String>> parseOMPL(String? path) async {
  List<String> rssFeedUrls = [];

  if (path == null) {
    return rssFeedUrls;
  }

  File file = File(path);
  rssFeedUrls = await file.readAsString().then(
    (value) {
      XmlDocument document = XmlDocument.parse(value);
      List<String> xmlUrls = [];
      document.findAllElements('outline').forEach(
        (element) {
          xmlUrls.add(element.getAttribute('xmlUrl')!);
        },
      );
      return xmlUrls;
    },
  );

  return rssFeedUrls;
}

class PodcastImportData {
  SubscriptionModel? subscription;
  FeedEpisodeModel? feedEpisode;

  PodcastImportData(this.subscription, this.feedEpisode);
}

Future<List<PodcastImportData>> fetchPodcastsByUrls(
    List<String> rssFeedUrls) async {
  List<PodcastImportData> podcasts = [];

  var futures = rssFeedUrls.map((rssFeedUrl) {
    return http.get(Uri.parse(rssFeedUrl)).then((response) {
      var body = utf8.decode(response.bodyBytes);
      RssFeed channel;
      try {
        channel = RssFeed.parse(body);
      } catch (error) {
        print(error);
        return null;
      }
      var subscription = SubscriptionModel.fromMap(Map<String, dynamic>.from({
        'rssFeedUrl': rssFeedUrl,
        'title': channel.title?.trim(),
        'description': htmlToText(channel.description)?.trim(),
        'imageUrl': channel.image?.url ?? (channel.itunes?.image?.href ?? ''),
        'link': channel.link,
        'categories': channel.categories?.map((e) => e.value).join(','),
        'author': channel.itunes?.author,
        'email': channel.itunes?.owner?.email,
      }));
      var latestPubDate = channel.items?.first.pubDate;
      var latestIndex = 0;
      for (var i = 1; i < channel.items!.length; i++) {
        if (channel.items![i].pubDate!.isAfter(latestPubDate!)) {
          latestPubDate = channel.items![i].pubDate;
          latestIndex = i;
        }
      }
      var latestItem = channel.items![latestIndex];
      var feedEpisode = FeedEpisodeModel.fromMap(Map<String, dynamic>.from({
        'title': latestItem.title?.trim(),
        'description': latestItem.itunes?.summary?.trim() ??
            latestItem.description?.trim(),
        'guid': latestItem.guid,
        'duration': latestItem.itunes?.duration?.inMilliseconds,
        'enclosureUrl': latestItem.enclosure?.url,
        'pubDate': latestItem.pubDate?.millisecondsSinceEpoch,
        'imageUrl': latestItem.itunes?.image?.href ?? subscription.imageUrl,
        'channelTitle': subscription.title,
        'rssFeedUrl': subscription.rssFeedUrl,
      }));
      return PodcastImportData(subscription, feedEpisode);
    }).catchError((error) {
      print(error);
      return null;
    });
  }).toList();
  var result = await Future.wait(futures, eagerError: false);

  for (PodcastImportData? podcast in result) {
    if (podcast == null) {
      continue;
    }
    podcasts.add(podcast);
  }

  return podcasts;
}

String? htmlToText(String? html) {
  if (html == null) {
    return null;
  }
  html = html.trim();

  if (!html.startsWith('<')) {
    return html;
  }

  try {
    var document = html_parser.parse(html);
    if (document.body == null) {
      return html;
    }
    return document.body?.text;
  } catch (error) {
    print(error);
    return html;
  }
}
