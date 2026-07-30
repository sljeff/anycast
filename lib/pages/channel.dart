import 'dart:math';

import 'package:anycast/design_system/anycast_theme.dart';
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
      onPopInvokedWithResult: (didPop, result) {
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
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AnycastSpacing.pageHeader,
                  ),
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
                            const SizedBox(width: AnycastSpacing.pageH),
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
                        color: Theme.of(context).colorScheme.outlineVariant,
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
                        horizontal: AnycastSpacing.pageH,
                        vertical: AnycastSpacing.sm,
                      ),
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
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        children: [
          Text(
            text,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: choosed
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          choosed
              ? Container(
                  width: 48,
                  height: 4,
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: theme.colorScheme.onSurface,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final initLeft = (Get.width - 48) / 2 - 60;

    return Stack(children: [
      Obx(
        () {
          final headerColor = Color.alphaBlend(
            controller.backgroundColor.value.withValues(
              alpha: isDark ? .30 : .18,
            ),
            theme.scaffoldBackgroundColor,
          );
          return Container(
            height: max(minExtent, maxExtent - shrinkOffset),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  headerColor,
                  theme.scaffoldBackgroundColor,
                ],
              ),
            ),
          );
        },
      ),
      SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AnycastSpacing.pageHeader,
          ),
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
    final theme = Theme.of(context);

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
                  color: theme.colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Iconify(
                  Ic.round_arrow_back,
                  size: 24,
                  color: theme.colorScheme.onSurface,
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
                      host: 'anycast.website',
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
                  SharePlus.instance.share(
                    ShareParams(text: '${subscription.title}\n$finalUrl'),
                  );
                  Get.back();
                },
                child: Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(8),
                    decoration: ShapeDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Iconify(
                      Ic.round_ios_share,
                      size: 24,
                      color: theme.colorScheme.onSurface,
                    )),
              ),
            ]),
          ],
        ),
        Column(children: [
          const SizedBox(height: AnycastSpacing.pageH),
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
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface,
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
                      const SizedBox(height: AnycastSpacing.gap),
                      Text(
                        controller.channel.value.author ?? 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: AnycastSpacing.gap),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                              text: controller.channel.value.rssFeedUrl!));
                          Get.snackbar(
                            'Copied',
                            'Copied RSS URL to clipboard',
                            snackPosition: SnackPosition.BOTTOM,
                            duration: const Duration(milliseconds: 1000),
                          );
                        },
                        child: Text(
                          urlToDomain(controller.channel.value.rssFeedUrl!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: AnycastSpacing.gap),
                      ExpandableText(
                        (subscription.description ?? 'No description').trim(),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.none,
                            ) ??
                            TextStyle(
                                color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: AnycastSpacing.gap),
                      SizedBox(
                        width: 184,
                        height: 40,
                        // borderRadius 36
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.all(8),
                            backgroundColor: theme.colorScheme.inverseSurface,
                            foregroundColor: theme.colorScheme.onInverseSurface,
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
                                  Iconify(
                                    Ic.round_play_arrow,
                                    color: theme.colorScheme.onInverseSurface,
                                  ),
                                  const SizedBox(width: AnycastSpacing.xs),
                                  Text(
                                    'Latest Episode',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: theme.colorScheme.onInverseSurface,
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
      final theme = Theme.of(context);
      var controller = Get.find<ChannelController>(tag: rssFeedUrl);
      var subscribed = controller.subscribed.value;
      var loading = controller.isLoading.value;
      if (controller.channel.value.title == null) {
        loading = true;
      }

      var textColor = theme.colorScheme.onSurface;
      var backgroundColor = theme.colorScheme.surfaceContainerHigh;
      Widget icon = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(color: textColor),
      );
      String text = 'Loading...';

      if (!loading) {
        if (subscribed) {
          text = 'Unsubscribe';
          textColor = theme.colorScheme.onPrimaryContainer;
          backgroundColor = theme.colorScheme.primaryContainer;
          icon = Iconify(Ic.round_clear, color: textColor, size: 24);
        } else {
          textColor = theme.colorScheme.onInverseSurface;
          backgroundColor = theme.colorScheme.inverseSurface;
          icon = Iconify(
            Ic.round_add_circle_outline,
            color: textColor,
            size: 24,
          );
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
            const SizedBox(width: AnycastSpacing.sm),
            Text(
              text,
              style: theme.textTheme.labelLarge?.copyWith(
                decoration: TextDecoration.none,
                color: textColor,
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
    final theme = Theme.of(context);
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
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search episodes',
          hintStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: theme.colorScheme.onSurfaceVariant,
            size: 24,
          ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainer,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );

    Widget cancel = const SizedBox.shrink();
    if (controller.text.isNotEmpty) {
      cancel = Row(
        children: [
          const SizedBox(width: AnycastSpacing.pageH),
          GestureDetector(
            onTap: () {
              controller.clear();
              FocusScope.of(context).requestFocus(FocusNode());
            },
            child: Text(
              'Clear',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
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
      onPopInvokedWithResult: (didPop, result) {
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
              const SizedBox(height: AnycastSpacing.gap),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AnycastSpacing.pageH,
                  ),
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
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      );
                    }

                    return ListView.separated(
                      separatorBuilder: (context, index) {
                        return const SizedBox(height: AnycastSpacing.gap);
                      },
                      padding: const EdgeInsets.only(
                        bottom: AnycastSpacing.pageBottomSafe,
                      ),
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
