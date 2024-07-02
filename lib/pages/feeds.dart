import 'dart:io';
import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/pages/podcasts.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/states/import_block.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/card.dart' as card;
import 'package:get/get.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

class Feeds extends StatelessWidget {
  const Feeds({super.key});

  static final controller = Get.put(FeedEpisodeController());
  static final clController = Get.put(CardListController(), tag: 'feeds');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24),
      child: Obx(() {
        var episodes = controller.episodes;
        if (episodes.isEmpty) {
          return ImportBlock();
        }
        return RefreshIndicator(
          onRefresh: fetchNewEpisodes,
          child: ListView.separated(
            padding: const EdgeInsets.only(top: 12),
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              var ep = episodes[index];
              return card.Card(
                episode: ep,
                index: index,
                clController: clController,
                actions: [
                  card.CardBtn(
                    icon: const Iconify(Ic.round_play_arrow),
                    onPressed: () {
                      controller.addToTop(1, ep).then((pe) {
                        controller.removeByGuids([ep.guid!]);
                        Get.find<PlayerController>().playByEpisode(pe);
                      });
                    },
                  ),
                  card.CardBtn(
                    icon: const Iconify(Ic.round_playlist_add),
                    onPressed: () {
                      controller.addToPlaylist(1, ep).then((pe) {
                        controller.removeByGuids([ep.guid!]);
                      });
                    },
                  ),
                  card.CardBtn(
                    icon: const Iconify(Ic.round_clear),
                    onPressed: () {
                      controller.removeByGuids([ep.guid!]);
                    },
                  ),
                ],
              );
            },
          ),
        );
      }),
    );
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
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              alignment: Alignment.center,
              height: 240,
              child: Text(
                'It’s empty here.\n\nLet\'s change that!',
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
            Expanded(
              child: SizedBox(
                width: 220,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 36,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          textStyle: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontFamily: GoogleFonts.comfortaa().fontFamily,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.40,
                          )),
                      onPressed: () {
                        Get.find<HomeTabController>().onItemTapped(2);
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Iconify(Ic.outline_explore,
                              color: Colors.white, size: 24),
                          SizedBox(width: 8),
                          Text('Explore'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(
                          height: 48,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              side: const BorderSide(
                                  color: Colors.white, width: 1),
                              textStyle: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontFamily: GoogleFonts.comfortaa().fontFamily,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () {
                              Get.dialog(const ImportExportBlock());
                            },
                            child: const Row(
                              children: [
                                Iconify(Ic.round_file_download,
                                    color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'Import OMPL',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Iconify(Ic.round_help, color: Colors.white),
                      ],
                    ),
                  ],
                ),
              ),
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
