import 'dart:io';
import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/import_block.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/feeds_episodes_list.dart';
import 'package:get/get.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';

class Feeds extends StatelessWidget {
  Feeds({Key? key}) : super(key: key);

  final FeedEpisodeController controller = Get.put(FeedEpisodeController());

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.episodes.isEmpty) {
        return ImportBlock();
      }
      return RefreshIndicator(
        onRefresh: fetchNewEpisodes,
        child: FeedsEpisodesListView(controller.episodes, true),
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
                          importPodcastsByUrls(value).then((value) {
                            Get.find<FeedEpisodeController>().addMany(
                                value.map((e) => e.feedEpisodes![0]).toList());
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
                          importPodcastsByUrls([controller.textController.text])
                              .then((value) {
                            Get.find<FeedEpisodeController>().addMany(
                                value.map((e) => e.feedEpisodes![0]).toList());
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

Future<void> fetchNewEpisodes() async {
  var subscriptions = Get.find<SubscriptionController>().subscriptions;
  var urls = subscriptions.map((e) => e.rssFeedUrl!).toList();

  var episodes = await fetchPodcastsByUrls(urls, onlyFistEpisode: false);
  var fetchedMap = <String, PodcastImportData>{};
  for (var episode in episodes) {
    fetchedMap[episode.subscription!.rssFeedUrl!] = episode;
  }

  var updatedSubscriptions = <SubscriptionModel>[];
  var updatedEpisodes = <FeedEpisodeModel>[];
  for (var subscription in subscriptions) {
    var fetched = fetchedMap[subscription.rssFeedUrl!];
    if (fetched == null) {
      continue;
    }
    if (subscription.lastUpdated != null &&
        subscription.lastUpdated! >= fetched.subscription!.lastUpdated!) {
      continue;
    }
    updatedSubscriptions.add(fetched.subscription!);
    // if lastUpdated is null, add the first episode
    if (subscription.lastUpdated == null) {
      updatedEpisodes.add(fetched.feedEpisodes![0]);
      continue;
    }
    updatedEpisodes.addAll(fetched.feedEpisodes!.where((element) {
      return element.pubDate! > subscription.lastUpdated!;
    }));
  }

  if (updatedSubscriptions.isNotEmpty) {
    Get.find<SubscriptionController>().addMany(updatedSubscriptions);
  }
  if (updatedEpisodes.isNotEmpty) {
    Get.find<FeedEpisodeController>().addMany(updatedEpisodes);
  }
}
