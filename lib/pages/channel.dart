import 'package:anycast/api/share.dart';
import 'package:anycast/states/cardlist.dart';
import 'package:share_plus/share_plus.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/widgets/card.dart' as card;
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:expandable_text/expandable_text.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:palette_generator/palette_generator.dart';

Future<Color> updatePaletteGenerator(String imageUrl) async {
  final PaletteGenerator generator =
      await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(
    imageUrl,
  ));
  final Color dominantColor =
      generator.dominantColor?.color ?? const Color(0xFF111316);

  return dominantColor;
}

class Channel extends StatelessWidget {
  final String rssFeedUrl;

  const Channel({super.key, required this.rssFeedUrl});

  @override
  Widget build(BuildContext context) {
    var clController = Get.put(CardListController(), tag: rssFeedUrl);
    var controller = Get.find<ChannelController>(tag: rssFeedUrl);

    return Obx(
      () {
        if (controller.channel.value.title == null) {
          return const Center(child: CircularProgressIndicator());
        }
        var subscription = controller.channel.value;
        var height = MediaQuery.of(context).size.height;

        return DismissiblePage(
            direction: DismissiblePageDismissDirection.down,
            onDismissed: () {
              Get.back();
              Get.delete<ChannelController>(tag: rssFeedUrl);
              Get.delete<CardListController>(tag: rssFeedUrl);
            },
            child: Stack(
              children: [
                Container(
                  height: height / 2,
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
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: height / 2,
                    color: const Color(0xFF111316),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Get.back();
                          Get.delete<ChannelController>(tag: rssFeedUrl);
                          Get.delete<CardListController>(tag: rssFeedUrl);
                        },
                        child: const Handler(),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Get.back();
                                    Get.delete<ChannelController>(
                                        tag: rssFeedUrl);
                                    Get.delete<CardListController>(
                                        tag: rssFeedUrl);
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
                                      getShortUrl(shareUrl).then((value) {
                                        var finalUrl = shareUrl.toString();
                                        if (value != null) {
                                          finalUrl = value;
                                        }
                                        Share.share(
                                            '${subscription.title}\n$finalUrl');
                                      });
                                    },
                                    child: Container(
                                        width: 40,
                                        height: 40,
                                        padding: const EdgeInsets.all(8),
                                        decoration: ShapeDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20),
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
                            const SizedBox(height: 12),
                            Column(children: [
                              controller.channel.value.imageUrl == null
                                  ? const Icon(
                                      Icons.image,
                                      color: Colors.white,
                                      size: 120,
                                    )
                                  : Container(
                                      width: 120,
                                      height: 120,
                                      decoration: ShapeDecoration(
                                        image: DecorationImage(
                                          image: CachedNetworkImageProvider(
                                            controller.channel.value.imageUrl!,
                                          ),
                                          fit: BoxFit.fill,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                              const SizedBox(height: 12),
                              Text(
                                controller.channel.value.title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontFamily:
                                      GoogleFonts.comfortaa().fontFamily,
                                  fontWeight: FontWeight.w400,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                controller.channel.value.author ?? 'Unknown',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontFamily: 'PingFangSC-Regular,PingFang SC',
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ]),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(
                                    text:
                                        controller.channel.value.rssFeedUrl!));
                                Get.snackbar(
                                  'Copied',
                                  'OK',
                                  snackPosition: SnackPosition.BOTTOM,
                                  duration: const Duration(milliseconds: 500),
                                );
                              },
                              child: Text(
                                urlToDomain(
                                    controller.channel.value.rssFeedUrl!),
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
                              subscription.description ?? 'No description',
                              expandText: "show more",
                              collapseText: "show less",
                              maxLines: 2,
                              linkColor: Colors.blue,
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
                                  var feedsController =
                                      Get.find<FeedEpisodeController>();
                                  feedsController
                                      .addToTop(1, controller.episodes[0])
                                      .then((pe) {
                                    Get.find<PlayerController>()
                                        .playByEpisode(pe);
                                  });
                                },
                                child: Row(
                                  children: [
                                    const Iconify(Ic.round_play_arrow),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Lastest Episode',
                                      style: TextStyle(
                                        color: const Color(0xFF111316),
                                        fontSize: 16,
                                        fontFamily:
                                            GoogleFonts.comfortaa().fontFamily,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      CardList(clController, rssFeedUrl),
                    ],
                  ),
                )
              ],
            ));
      },
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

class CardList extends StatelessWidget {
  final CardListController clController;
  final String rssFeedUrl;

  const CardList(this.clController, this.rssFeedUrl, {super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        var feedsController = Get.find<FeedEpisodeController>();
        var controller = Get.find<ChannelController>(tag: rssFeedUrl);
        var playerController = Get.find<PlayerController>();

        var episodes = controller.episodes;
        if (episodes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Expanded(
            child: controller.isLoading.value
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.only(left: 12, right: 12),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      var ep = episodes[index];

                      return Obx(
                        () {
                          var playlistController =
                              Get.find<PlaylistController>();
                          var inPlaylist = playlistController
                              .isInPlaylists(ep.enclosureUrl!);
                          var playing = playerController.isPlaying.value &&
                              ep.enclosureUrl ==
                                  playerController
                                      .playlistEpisode.value.enclosureUrl;

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
                                icon: inPlaylist
                                    ? const Iconify(Ic.round_playlist_add_check)
                                    : const Iconify(Ic.round_playlist_add),
                                onPressed: () {
                                  feedsController.addToPlaylist(1, ep);
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ));
      },
    );
  }
}
