import 'package:anycast/pages/settings.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/api/podcasts.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/utils/keepalive.dart';
import 'package:anycast/widgets/appbar.dart';
import 'package:anycast/widgets/card.dart' as card;
import 'package:anycast/widgets/card.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class Discover extends StatelessWidget {
  const Discover({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MyAppBar(
        title: 'DISCOVER',
        icon: Icons.settings_rounded,
        iconOnTap: () {
          showMaterialModalBottomSheet(
            expand: true,
            context: context,
            builder: (context) {
              return const SettingsPage();
            },
            closeProgressThreshold: 0.9,
          );
        },
      ),
      body: const DiscoverBody(),
    );
  }
}

class DiscoverBody extends StatelessWidget {
  const DiscoverBody({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: listCategories(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        var categories = snapshot.data!;
        return DefaultTabController(
          length: categories.length,
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabs: categories.map((c) => Tab(text: c.name)).toList(),
            ),
            Expanded(
              child: TabBarView(
                  children: categories.map((c) {
                return KeepAliveWrapper(
                  key: Key('discover_${c.id}'),
                  child: Obx(
                    () => FutureBuilder(
                      future: listChannelsByCategoryId(
                        c.id,
                        Get.find<SettingsController>().countryCode.value,
                      ),
                      builder: ((context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        var channels = snapshot.data!;
                        if (channels.isEmpty) {
                          return const Center(
                            child: Text(
                              'Network Error',
                              style: TextStyle(color: Colors.white),
                            ),
                          );
                        }
                        return ListView.separated(
                            padding: const EdgeInsets.only(
                                left: 12, right: 12, top: 12),
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemCount: channels.length,
                            itemBuilder: (context, index) {
                              return PodcastCard(
                                subscription: channels[index],
                              );
                            });
                      }),
                    ),
                  ),
                );
              }).toList()),
            ),
          ]),
        );
      },
    );
  }
}

class SearchPage extends StatelessWidget {
  final String searchText;

  const SearchPage({super.key, required this.searchText});

  @override
  Widget build(BuildContext context) {
    var clController = Get.put(CardListController());

    return Container(
      color: const Color(0xFF111316),
      child: SafeArea(
        child: Column(
          children: [
            GestureDetector(
              child: const Handler(),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'You are searching for',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: GoogleFonts.comfortaa().fontFamily,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  searchText,
                  style: TextStyle(
                      color: const Color(0xFF6EE7B7),
                      fontSize: 16,
                      fontFamily: GoogleFonts.comfortaa().fontFamily,
                      fontWeight: FontWeight.w400,
                      decoration: TextDecoration.none),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Material(
                      child: TabBar(
                        tabs: const [
                          Tab(text: 'Channels'),
                          Tab(text: 'Episodes'),
                        ],
                        indicatorColor: const Color(0xFF6EE7B7),
                        labelColor: const Color(0xFF6EE7B7),
                        unselectedLabelColor: Colors.white,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontFamily: GoogleFonts.comfortaa().fontFamily,
                          fontWeight: FontWeight.w700,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontSize: 12,
                          fontFamily: GoogleFonts.comfortaa().fontFamily,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          FutureBuilder(
                            future: searchChannels(searchText),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              var subscriptions = snapshot.data!;
                              if (subscriptions.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'No results',
                                    style: TextStyle(
                                      color: Colors.white,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                );
                              }
                              return ListView.separated(
                                  padding: const EdgeInsets.only(
                                      left: 12, right: 12, top: 12),
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 12),
                                  itemCount: subscriptions.length,
                                  itemBuilder: (context, index) {
                                    return card.PodcastCard(
                                      subscription: subscriptions[index],
                                    );
                                  });
                            },
                          ),
                          FutureBuilder(
                            future: searchEpisodes(searchText),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              var episodes = snapshot.data!;
                              if (episodes.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'No results',
                                    style: TextStyle(
                                      color: Colors.white,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                );
                              }
                              return ListView.separated(
                                  padding: const EdgeInsets.only(
                                      left: 12, right: 12, top: 12),
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 12),
                                  itemCount: episodes.length,
                                  itemBuilder: (context, index) {
                                    var ep = episodes[index].episode!;
                                    return Obx(
                                      () {
                                        var playlistController =
                                            Get.find<PlaylistController>();
                                        var playerController =
                                            Get.find<PlayerController>();
                                        var feedsController =
                                            Get.find<FeedEpisodeController>();
                                        var inPlaylist = playlistController
                                            .isInPlaylists(ep.enclosureUrl!);
                                        var playing =
                                            playerController.isPlaying.value &&
                                                ep.enclosureUrl ==
                                                    playerController
                                                        .playlistEpisode
                                                        .value
                                                        .enclosureUrl;

                                        return card.Card(
                                          episode: ep,
                                          index: index,
                                          clController: clController,
                                          actions: [
                                            card.CardBtn(
                                              icon: PlayIcon(
                                                  enclosureUrl:
                                                      ep.enclosureUrl!),
                                              onPressed: () {
                                                if (playing) {
                                                  playerController.pause();
                                                } else {
                                                  feedsController
                                                      .addToTop(1, ep)
                                                      .then((pe) {
                                                    Get.find<PlayerController>()
                                                        .playByEpisode(pe);
                                                  });
                                                }
                                              },
                                            ),
                                            card.CardBtn(
                                              icon: inPlaylist
                                                  ? const Iconify(Ic
                                                      .round_playlist_add_check)
                                                  : const Iconify(
                                                      Ic.round_playlist_add),
                                              onPressed: () {
                                                feedsController.addToPlaylist(
                                                    1, ep);
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
