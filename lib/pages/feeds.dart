import 'dart:io';
import 'package:anycast/design_system/anycast_components.dart';
import 'package:anycast/design_system/anycast_theme.dart';
import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/animation.dart';
import 'package:anycast/widgets/bottom_nav_bar.dart';
import 'package:anycast/widgets/card.dart' as card;
import 'package:anycast/widgets/import_export.dart';
import 'package:get/get.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: AnycastSpacing.pageH),
      child: EasyRefresh(
        onRefresh: () async {
          await fetchNewEpisodes();
          controller.refreshController.finishRefresh();
          controller.refreshController.resetFooter();
        },
        controller: controller.refreshController,
        refreshOnStart: true,
        header: BezierHeader(
          clamping: false,
          triggerOffset: 1,
          spinInCenter: true,
          spinWidget: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AnycastSpacing.pageH),
            child: Column(
              children: [
                const SizedBox(height: AnycastSpacing.md),
                Obx(() {
                  var percent = controller.progress.value;
                  return LinearProgressIndicator(
                    value: percent,
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHigh,
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
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              controller: controller.scrollController,
              child: const ImportBlock(),
            );
          }
          return ListView.separated(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(
              top: AnycastSpacing.gap,
              bottom: AnycastSpacing.pageBottomSafe,
            ),
            separatorBuilder: (context, index) =>
                const SizedBox(height: AnycastSpacing.gap),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              var ep = episodes[index];
              var epBtnKey = GlobalKey();
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
                    key: epBtnKey,
                    icon: const Iconify(Ic.round_playlist_add),
                    onPressed: () {
                      if (epBtnKey.currentContext != null) {
                        // icon in screen, show animation
                        var currentContext = epBtnKey.currentContext!;
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
                      print(ep.enclosureUrl);
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
  const ImportBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return AnycastEmptyState(
      icon: Icons.inbox_rounded,
      title: 'It’s empty here.',
      message: 'Let\'s change that!',
      action: Column(
        children: [
          FilledButton.icon(
            onPressed: () {
              Get.find<HomeTabController>().onItemTapped(2);
            },
            icon: const Icon(Icons.explore_rounded),
            label: const Text('Explore'),
          ),
          const SizedBox(height: AnycastSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Get.dialog(const ImportExportBlock());
                },
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Import OPML'),
              ),
              const SizedBox(width: AnycastSpacing.md),
              IconButton(
                tooltip: 'Import help',
                onPressed: () {
                  showModalBottomSheet(
                    useSafeArea: true,
                    isScrollControlled: true,
                    context: context,
                    builder: (context) {
                      return const ImportInstructions();
                    },
                  );
                },
                icon: const Icon(Icons.help_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<List<OPML>> parseOPML(String? path) async {
  List<OPML> opml = [];

  if (path == null) {
    return opml;
  }

  File file = File(path);
  opml = await file.readAsString().then(
    (value) {
      XmlDocument document = XmlDocument.parse(value);
      List<OPML> o = [];
      document.findAllElements('outline').forEach(
        (element) {
          var v = element.getAttribute('xmlUrl');
          var t = element.getAttribute('title');
          t ??= element.getAttribute('text');
          if (v == null || t == null) {
            return;
          }
          o.add(OPML(t, v));
        },
      );
      return o;
    },
  );

  return opml;
}

Future<void> fetchNewEpisodes() async {
  var subscriptions = Get.find<SubscriptionController>().subscriptions;
  if (subscriptions.isEmpty) {
    return;
  }
  var urls = subscriptions.map((e) => e.rssFeedUrl!).toList();
  var controller = Get.find<FeedEpisodeController>();
  controller.progress.value = 0;
  controller.lastRefresh = DateTime.now();

  await fetchPodcastsByUrls(
    urls,
    onlyFistEpisode: false,
    onProgress: (progress, total) {
      Get.find<FeedEpisodeController>().progress.value = (progress + 8) / total;
    },
    onSave: (episodes) {
      saveNewEpisodes(episodes, subscriptions);
    },
  );
}

void saveNewEpisodes(
    List<PodcastImportData?> episodes, List<SubscriptionModel> subscriptions) {
  var fetchedMap = <String, PodcastImportData>{};
  for (var episode in episodes) {
    if (episode == null) continue;
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
    if (subscription.lastUpdated == null && fetched.feedEpisodes!.isNotEmpty) {
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

class OPML {
  final String title;
  final String url;

  OPML(this.title, this.url);
}
