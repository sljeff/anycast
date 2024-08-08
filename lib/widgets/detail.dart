import 'package:anycast/api/share.dart';
import 'package:anycast/models/episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/pages/channel.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/widgets/card.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:share_plus/share_plus.dart';

class Detail extends StatelessWidget {
  final Episode episode;
  final List<CardBtn> actions;

  const Detail({
    super.key,
    required this.episode,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    List<CardBtn> detailActions = [];
    for (var action in actions) {
      detailActions.add(CardBtn(
        icon: action.icon,
        onPressed: () {
          action.onPressed();
          Navigator.pop(context);
        },
      ));
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.6,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                },
                child: const Handler(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: ShapeDecoration(
                                image: DecorationImage(
                                  image: CachedNetworkImageProvider(
                                    episode.imageUrl ??
                                        'https://placeholder.co/400/000000/FFF.png?text=No+Image',
                                  ),
                                  fit: BoxFit.fill,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    episode.title ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontFamily:
                                          'PingFangSC-Regular,PingFang SC',
                                      fontWeight: FontWeight.w500,
                                      height: 0,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            var s = SubscriptionModel.empty();
                                            s.rssFeedUrl = episode.rssFeedUrl;
                                            s.title = episode.channelTitle;
                                            s.rssFeedUrl = episode.rssFeedUrl;
                                            Get.lazyPut(
                                                () => ChannelController(
                                                    channel: s),
                                                tag: s.rssFeedUrl);
                                            showMaterialModalBottomSheet(
                                              context: context,
                                              builder: (context) => Channel(
                                                rssFeedUrl: s.rssFeedUrl!,
                                              ),
                                              expand: true,
                                              closeProgressThreshold: 0.9,
                                            );
                                          },
                                          child: Text(
                                            episode.channelTitle!,
                                            style: const TextStyle(
                                              color: Color(0xFF6EE7B7),
                                              fontSize: 12,
                                              fontFamily:
                                                  'PingFangSC-Regular,PingFang SC',
                                              fontWeight: FontWeight.w500,
                                              decoration:
                                                  TextDecoration.underline,
                                              decorationColor:
                                                  Color(0xFF6EE7B7),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        formatDate(episode.pubDate!),
                                        style: GoogleFonts.comfortaa(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w300,
                                          color: Colors.white.withOpacity(0.5),
                                        ),
                                      )
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () async {
                                var shareUrl = Uri(
                                  scheme: 'https',
                                  host: 'share.anycast.website',
                                  path: 'player',
                                  queryParameters: {
                                    'rssfeedurl': episode.rssFeedUrl!,
                                    'enclosureurl': episode.enclosureUrl!,
                                  },
                                );

                                Get.dialog(const Center(
                                  child: CircularProgressIndicator(
                                    strokeCap: StrokeCap.round,
                                  ),
                                ));
                                await getShortUrl(shareUrl).then((value) {
                                  var finalUrl = shareUrl.toString();
                                  if (value != null) {
                                    finalUrl = value;
                                  }
                                  Share.share('${episode.title}\n\n$finalUrl');
                                });

                                Get.back();
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: ShapeDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: const FractionallySizedBox(
                                  widthFactor: 0.6,
                                  heightFactor: 0.6,
                                  child: Iconify(
                                    Ic.round_ios_share,
                                    size: 24,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: renderHtml(context, episode.description ?? ''),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: detailActions,
              ),
            ],
          ),
        );
      },
    );
  }
}
