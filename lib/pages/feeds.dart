import 'dart:io';
import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/pages/podcasts.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/states/import_block.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/animation.dart';
import 'package:anycast/widgets/bottom_nav_bar.dart';
import 'package:anycast/widgets/card.dart' as card;
import 'package:get/get.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:easy_refresh/easy_refresh.dart';

class Feeds extends GetView<FeedEpisodeController> {
  const Feeds({super.key});

  static final clController = Get.put(CardListController(), tag: 'feeds');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24),
      child: EasyRefresh(
        onRefresh: () async {
          await fetchNewEpisodes();
          controller.refreshController.finishRefresh();
          controller.refreshController.resetFooter();
        },
        controller: controller.refreshController,
        refreshOnStart: true,
        header: BezierHeader(
          clamping: true,
          triggerOffset: 1,
          spinInCenter: true,
          spinWidget: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Obx(() {
                  var percent = controller.progress.value;
                  return LinearProgressIndicator(
                    value: percent,
                    color: Colors.green,
                    backgroundColor: Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(1),
                    minHeight: 1,
                  );
                }),
              ],
            ),
          ),
        ),
        child: Obx(() {
          var episodes = controller.episodes;
          if (episodes.isEmpty) {
            return ImportBlock();
          }
          return ListView.separated(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 12),
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              var ep = episodes[index];
              var key = GlobalKey();
              return card.Card(
                episode: ep,
                index: index,
                clController: clController,
                actions: [
                  card.CardBtn(
                    icon: const Iconify(Ic.round_play_arrow),
                    onPressed: () {
                      controller.addToTop(1, ep).then((pe) {
                        controller.removeByEnclosureUrls([ep.enclosureUrl!]);
                        Get.find<PlayerController>().playByEpisode(pe);
                      });
                    },
                  ),
                  card.CardBtn(
                    key: key,
                    icon: const Iconify(Ic.round_playlist_add),
                    onPressed: () {
                      if (key.currentContext != null) {
                        // icon in screen, show animation
                        var currentContext = key.currentContext!;
                        var r = currentContext.findRenderObject() as RenderBox;
                        var startOffset =
                            r.localToGlobal(r.size.center(Offset.zero));
                        var endOffset = BottomNavBar.getPlaylistPosition();
                        OverlayEntry? entry;
                        entry = OverlayEntry(
                          builder: (context) => AnimatedPlaylistIndicator(
                            startPosition: startOffset,
                            endPosition: endOffset,
                            onAnimationComplete: () {
                              entry?.remove();
                            },
                          ),
                        );
                        Overlay.of(context).insert(entry);
                      }

                      controller.addToPlaylist(1, ep).then((pe) {
                        controller.removeByEnclosureUrls([ep.enclosureUrl!]);
                      });
                    },
                  ),
                  card.CardBtn(
                    icon: const Iconify(Ic.round_clear),
                    onPressed: () {
                      controller.removeByEnclosureUrls([ep.enclosureUrl!]);
                    },
                  ),
                ],
              );
            },
          );
        }),
      ),
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
  if (subscriptions.isEmpty) {
    return;
  }
  var urls = subscriptions.map((e) => e.rssFeedUrl!).toList();
  var controller = Get.find<FeedEpisodeController>();
  controller.progress.value = 8 / urls.length;
  controller.lastRefresh = DateTime.now();

  var episodes = await fetchPodcastsByUrls(
    urls,
    onlyFistEpisode: false,
    onProgress: (progress, total) {
      Get.find<FeedEpisodeController>().progress.value = (progress + 8) / total;
    },
  );
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
