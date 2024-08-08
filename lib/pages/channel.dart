import 'dart:math';

import 'package:anycast/api/share.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:anycast/widgets/animation.dart';
import 'package:anycast/widgets/bottom_nav_bar.dart';
import 'package:anycast/widgets/expandable_text.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:share_plus/share_plus.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/widgets/card.dart' as card;
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';

class Channel extends StatelessWidget {
  final String rssFeedUrl;

  const Channel({super.key, required this.rssFeedUrl});

  @override
  Widget build(BuildContext context) {
    var clController = Get.put(CardListController(), tag: rssFeedUrl);
    var controller = Get.find<ChannelController>(tag: rssFeedUrl);

    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          Future.delayed(const Duration(milliseconds: 500), () {
            Get.delete<ChannelController>(tag: rssFeedUrl);
            Get.delete<CardListController>(tag: rssFeedUrl);
          });
        }
      },
      child: Obx(
        () {
          if (controller.channel.value.title == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Scaffold(
            bottomNavigationBar: const PlayerBar(bottomSafe: true),
            backgroundColor: const Color(0xFF111316),
            body: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: ChannelHeaderDelegate(
                    rssFeedUrl: rssFeedUrl,
                  ),
                ),
                SliverToBoxAdapter(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      SearchBar(rssFeedUrl: rssFeedUrl),
                      Obx(() {
                        var isReversed = controller.isReversed.value;

                        return Row(
                          children: [
                            OrderChooser(
                              text: "Newest",
                              choosed: !isReversed,
                              onPressed: () {
                                controller.isReversed.value = false;
                              },
                            ),
                            const SizedBox(width: 16),
                            OrderChooser(
                              text: "Oldest",
                              choosed: isReversed,
                              onPressed: () {
                                controller.isReversed.value = true;
                              },
                            ),
                          ],
                        );
                      }),
                      // const Divider(color: Color(0xFF232830), thickness: 1),
                      Container(
                        color: const Color(0xFF232830),
                        height: 1,
                      ),
                    ],
                  ),
                )),
                SliverList(
                    delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 6),
                      child: Obx(
                        () {
                          var feedsController =
                              Get.find<FeedEpisodeController>();
                          var controller =
                              Get.find<ChannelController>(tag: rssFeedUrl);
                          var playerController = Get.find<PlayerController>();

                          if (controller.episodes.isEmpty) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          var ep = controller.showEpisodes[index];

                          var playlistController =
                              Get.find<PlaylistController>();
                          var inPlaylist = playlistController
                              .isInPlaylists(ep.enclosureUrl!);
                          var playing = playerController.isPlaying.value &&
                              ep.enclosureUrl ==
                                  playerController
                                      .playlistEpisode.value.enclosureUrl;
                          var epBtnKey = GlobalKey();

                          return card.Card(
                            episode: ep,
                            index: index,
                            clController: clController,
                            actions: [
                              card.CardBtn(
                                icon: PlayIcon(enclosureUrl: ep.enclosureUrl!),
                                onPressed: () {
                                  if (playing) {
                                    playerController.pause();
                                  } else {
                                    feedsController.addToTop(1, ep).then((pe) {
                                      Get.find<PlayerController>()
                                          .playByEpisode(pe);
                                    });
                                  }
                                },
                              ),
                              card.CardBtn(
                                key: epBtnKey,
                                icon: inPlaylist
                                    ? const Iconify(Ic.round_playlist_add_check)
                                    : const Iconify(Ic.round_playlist_add),
                                onPressed: () {
                                  if (inPlaylist) {
                                    return;
                                  }
                                  if (epBtnKey.currentContext != null) {
                                    // icon in screen, show animation
                                    var currentContext =
                                        epBtnKey.currentContext!;
                                    var r = currentContext.findRenderObject()
                                        as RenderBox;
                                    var startOffset = r.localToGlobal(
                                        r.size.center(Offset.zero));
                                    var endOffset =
                                        BottomNavBar.getPlaylistPosition();
                                    OverlayEntry? entry;
                                    entry = OverlayEntry(
                                      builder: (context) =>
                                          AnimatedPlaylistIndicator(
                                        startPosition: startOffset,
                                        endPosition: endOffset,
                                        onAnimationComplete: () {
                                          entry?.remove();
                                        },
                                      ),
                                    );
                                    Overlay.of(context).insert(entry);
                                  }
                                  feedsController.addToPlaylist(1, ep);
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                  childCount: controller.episodes.length,
                )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class OrderChooser extends StatelessWidget {
  final String text;
  final bool choosed;
  final VoidCallback onPressed;

  const OrderChooser({
    super.key,
    required this.text,
    required this.onPressed,
    required this.choosed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        children: [
          Text(
            text,
            style: GoogleFonts.comfortaa(
              color: choosed ? Colors.white : const Color(0xFF6B7280),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
          choosed
              ? Container(
                  width: 48,
                  height: 4,
                  clipBehavior: Clip.antiAlias,
                  decoration: const ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                    ),
                  ),
                )
              : const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class ChannelHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String rssFeedUrl;

  const ChannelHeaderDelegate({required this.rssFeedUrl});

  @override
  double get minExtent =>
      MediaQuery.of(Get.context!).padding.top + 6 + 16 + 40 + 16 + 60 + 10;

  @override
  double get maxExtent => MediaQuery.of(Get.context!).padding.top + 460;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    var controller = Get.find<ChannelController>(tag: rssFeedUrl);
    final initLeft = (Get.width - 48) / 2 - 60;

    return Stack(children: [
      Obx(
        () => Container(
          height: max(minExtent, maxExtent - shrinkOffset),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                controller.backgroundColor.value,
                const Color(0xFF111316),
              ],
            ),
          ),
        ),
      ),
      SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Stack(
            children: [
              _buildMain(context, shrinkOffset, overlapsContent),
              Positioned(
                top: 6 + 16 + 40 + 16,
                left: max(initLeft - shrinkOffset, 16),
                child: Container(
                  width: max(120 - shrinkOffset, 60),
                  height: max(120 - shrinkOffset, 60),
                  decoration: ShapeDecoration(
                    image: DecorationImage(
                      image: CachedNetworkImageProvider(
                        controller.channel.value.imageUrl ??
                            "https://placeholder.co/120.png?text=Waiting",
                      ),
                      fit: BoxFit.fill,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _buildMain(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    var controller = Get.find<ChannelController>(tag: rssFeedUrl);
    var subscription = controller.channel.value;

    return Column(
      children: [
        const Handler(),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                Get.back();
                Get.delete<ChannelController>(tag: rssFeedUrl);
                Get.delete<CardListController>(tag: rssFeedUrl);
              },
              child: Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(8),
                decoration: ShapeDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Iconify(
                  Ic.round_arrow_back,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            ),
            Row(children: [
              SubscriptionButton(rssFeedUrl),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () async {
                  var shareUrl = Uri(
                      scheme: 'https',
                      host: 'share.anycast.website',
                      path: 'channel',
                      queryParameters: {
                        'rssfeedurl': rssFeedUrl,
                      });
                  Get.dialog(const Center(child: CircularProgressIndicator()));
                  var value = await getShortUrl(shareUrl);
                  var finalUrl = shareUrl.toString();
                  if (value != null) {
                    finalUrl = value;
                  }
                  Share.share('${subscription.title}\n$finalUrl');
                  Get.back();
                },
                child: Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(8),
                    decoration: ShapeDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Iconify(
                      Ic.round_ios_share,
                      size: 24,
                      color: Colors.white,
                    )),
              ),
            ]),
          ],
        ),
        Column(children: [
          const SizedBox(height: 16),
          SizedBox(
            width: max(120 - shrinkOffset, 0),
            height: max(120 - shrinkOffset, 0),
          ),
          SizedBox(height: (max(12 - shrinkOffset, 0))),
          Container(
            height: 58,
            alignment: Alignment.center,
            padding: EdgeInsets.only(left: min(60 + 24, shrinkOffset)),
            child: Text(
              controller.channel.value.title!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontFamily: GoogleFonts.comfortaa().fontFamily,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          shrinkOffset >= (maxExtent / 4)
              ? const SizedBox()
              : Opacity(
                  opacity: max(1 - shrinkOffset / (maxExtent / 4), 0),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        controller.channel.value.author ?? 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'PingFangSC-Regular,PingFang SC',
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                              text: controller.channel.value.rssFeedUrl!));
                          Get.snackbar(
                            'Copied',
                            'Copied RSS URL to clipboard',
                            snackPosition: SnackPosition.BOTTOM,
                            duration: const Duration(milliseconds: 1000),
                            backgroundColor: Colors.black,
                          );
                        },
                        child: Text(
                          urlToDomain(controller.channel.value.rssFeedUrl!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF6EE7B7),
                            fontSize: 16,
                            fontFamily: 'PingFangSC-Regular,PingFang SC',
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ExpandableText(
                        (subscription.description ?? 'No description').trim(),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontWeight: FontWeight.w400,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 184,
                        height: 40,
                        // borderRadius 36
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.all(8),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(36),
                            ),
                          ),
                          onPressed: () {
                            if (controller.isLoading.value) {
                              return;
                            }
                            var feedsController =
                                Get.find<FeedEpisodeController>();
                            feedsController
                                .addToTop(1, controller.episodes[0])
                                .then((pe) {
                              Get.find<PlayerController>().playByEpisode(pe);
                            });
                          },
                          child: Obx(
                            () {
                              if (controller.isLoading.value) {
                                return const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator());
                              }
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Iconify(Ic.round_play_arrow),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Latest Episode',
                                    style: TextStyle(
                                      color: const Color(0xFF111316),
                                      fontSize: 16,
                                      fontFamily:
                                          GoogleFonts.comfortaa().fontFamily,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      )
                    ],
                  ),
                ),
        ]),
      ],
    );
  }
}

class SubscriptionButton extends StatelessWidget {
  final String rssFeedUrl;

  const SubscriptionButton(this.rssFeedUrl, {super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var controller = Get.find<ChannelController>(tag: rssFeedUrl);
      var subscribed = controller.subscribed.value;
      var loading = controller.isLoading.value;
      if (controller.channel.value.title == null) {
        loading = true;
      }

      Widget icon = const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator());
      String text = 'Loading...';
      Color textColor = Colors.white;
      Color backgroundColor = Colors.white.withOpacity(0.1);

      if (!loading) {
        if (subscribed) {
          text = 'Unsubscribe';
          textColor = Colors.black;
          backgroundColor = Colors.white;
          icon = const Iconify(Ic.round_clear, color: Colors.black, size: 24);
        } else {
          icon = const Iconify(Ic.round_add_circle_outline,
              color: Colors.white, size: 24);
          text = 'Subscribe';
        }
      }

      var btn = Container(
        height: 40,
        padding: const EdgeInsets.all(8),
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(36),
          ),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                decoration: TextDecoration.none,
                color: textColor,
                fontSize: 16,
                fontFamily: GoogleFonts.comfortaa().fontFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

      return GestureDetector(
        onTap: () {
          if (loading) {
            return;
          }
          if (subscribed) {
            controller.unsubscribe();
          } else {
            controller.subscribe();
          }
        },
        child: btn,
      );
    });
  }
}

class SearchBar extends StatefulWidget {
  final String rssFeedUrl;

  const SearchBar({super.key, required this.rssFeedUrl});

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    var searchBar = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        onTapOutside: (event) {
          FocusScope.of(context).unfocus();
        },
        onChanged: (value) {
          setState(() {
            controller.text = value;
          });
        },
        onSubmitted: (value) {
          showMaterialModalBottomSheet(
            expand: true,
            closeProgressThreshold: 0.9,
            context: context,
            builder: (context) =>
                ChannelSearch(rssFeedUrl: widget.rssFeedUrl, searchText: value),
          );
        },
        controller: controller,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          hintText: 'Search episodes',
          hintStyle: TextStyle(
            color: const Color(0xFF4B5563),
            fontSize: 16,
            fontFamily: GoogleFonts.comfortaa().fontFamily,
            fontWeight: FontWeight.w400,
            height: 0,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFF4B5563),
            size: 24,
          ),
          filled: true,
          fillColor: const Color(0xFF232830),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF232830),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF232830),
            ),
          ),
        ),
      ),
    );

    Widget cancel = const SizedBox.shrink();
    if (controller.text.isNotEmpty) {
      cancel = Row(
        children: [
          const SizedBox(
            width: 16,
          ),
          GestureDetector(
            onTap: () {
              controller.clear();
              FocusScope.of(context).requestFocus(FocusNode());
            },
            child: Text(
              'Clear',
              style: TextStyle(
                color: const Color(0xFF34D399),
                fontSize: 16,
                fontFamily: GoogleFonts.comfortaa().fontFamily,
                fontWeight: FontWeight.w400,
                height: 0,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: searchBar),
        cancel,
      ],
    );
  }
}

class ChannelSearch extends StatelessWidget {
  final String rssFeedUrl;
  final String searchText;

  const ChannelSearch(
      {super.key, required this.rssFeedUrl, required this.searchText});

  @override
  Widget build(BuildContext context) {
    var clController = Get.put(CardListController(), tag: 'search-$rssFeedUrl');
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          Get.delete<CardListController>(tag: 'search-$rssFeedUrl');
        }
      },
      child: Scaffold(
        bottomNavigationBar: const PlayerBar(bottomSafe: true),
        body: SafeArea(
          child: Column(
            children: [
              const Handler(),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Obx(() {
                    var controller =
                        Get.find<ChannelController>(tag: rssFeedUrl);
                    var episodes = controller.episodes
                        .where((e) => e.title!
                            .toLowerCase()
                            .contains(searchText.toLowerCase()))
                        .toList();

                    if (episodes.isEmpty) {
                      return Center(
                        child: Text(
                          'No results',
                          style: GoogleFonts.comfortaa(
                            fontSize: 20,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      separatorBuilder: (context, index) {
                        return const SizedBox(height: 12);
                      },
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: episodes.length,
                      itemBuilder: (context, index) {
                        return Obx(() {
                          var feedsController =
                              Get.find<FeedEpisodeController>();
                          var controller =
                              Get.find<ChannelController>(tag: rssFeedUrl);
                          var playerController = Get.find<PlayerController>();

                          if (controller.episodes.isEmpty) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          var ep = episodes[index];

                          var playlistController =
                              Get.find<PlaylistController>();
                          var inPlaylist = playlistController
                              .isInPlaylists(ep.enclosureUrl!);
                          var playing = playerController.isPlaying.value &&
                              ep.enclosureUrl ==
                                  playerController
                                      .playlistEpisode.value.enclosureUrl;
                          var epBtnKey = GlobalKey();

                          return card.Card(
                            episode: ep,
                            index: index,
                            actions: [
                              card.CardBtn(
                                icon: PlayIcon(enclosureUrl: ep.enclosureUrl!),
                                onPressed: () {
                                  if (playing) {
                                    playerController.pause();
                                  } else {
                                    feedsController.addToTop(1, ep).then((pe) {
                                      Get.find<PlayerController>()
                                          .playByEpisode(pe);
                                    });
                                  }
                                },
                              ),
                              card.CardBtn(
                                key: epBtnKey,
                                icon: inPlaylist
                                    ? const Iconify(Ic.round_playlist_add_check)
                                    : const Iconify(Ic.round_playlist_add),
                                onPressed: () {
                                  if (inPlaylist) {
                                    return;
                                  }
                                  if (epBtnKey.currentContext != null) {
                                    // icon in screen, show animation
                                    var currentContext =
                                        epBtnKey.currentContext!;
                                    var r = currentContext.findRenderObject()
                                        as RenderBox;
                                    var startOffset = r.localToGlobal(
                                        r.size.center(Offset.zero));
                                    var endOffset =
                                        BottomNavBar.getPlaylistPosition();
                                    OverlayEntry? entry;
                                    entry = OverlayEntry(
                                      builder: (context) =>
                                          AnimatedPlaylistIndicator(
                                        startPosition: startOffset,
                                        endPosition: endOffset,
                                        onAnimationComplete: () {
                                          entry?.remove();
                                        },
                                      ),
                                    );
                                    Overlay.of(context).insert(entry);
                                  }
                                  feedsController.addToPlaylist(1, ep);
                                },
                              ),
                            ],
                            clController: clController,
                          );
                        });
                      },
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
