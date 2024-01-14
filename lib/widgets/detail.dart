import 'package:anycast/models/episode.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/channel.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:get/get.dart';
import 'package:sanitize_html/sanitize_html.dart' show sanitizeHtml;

class DetailWidget extends StatelessWidget {
  final Episode episode;

  const DetailWidget(this.episode, {super.key});

  @override
  Widget build(BuildContext context) {
    var subscriptionController = Get.find<SubscriptionController>();
    return BottomSheet(
        enableDrag: false,
        onClosing: () {},
        builder: (context) => DraggableScrollableSheet(
              initialChildSize: 1,
              minChildSize: 0.6,
              expand: false,
              builder:
                  (BuildContext context, ScrollController scrollController) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12, left: 12, right: 12),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: episode.imageUrl!,
                                    width: 60,
                                    height: 60,
                                    placeholder: (context, url) => const Icon(
                                      Icons.image,
                                    ),
                                    errorWidget: (context, url, error) =>
                                        const Icon(
                                      Icons.image_not_supported,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // link text channelTitle
                                SizedBox(
                                  width: 60,
                                  child: GestureDetector(
                                    onTap: () {
                                      var s = subscriptionController
                                          .getByTitle(episode.channelTitle!);
                                      if (s != null) {
                                        Get.lazyPut(
                                            () => ChannelController(channel: s),
                                            tag: s.rssFeedUrl);
                                        context.pushTransparentRoute(
                                            Channel(subscription: s));
                                      }
                                    },
                                    child: Text(
                                      episode.channelTitle!,
                                      style: const TextStyle(
                                          fontSize: 8, color: Colors.blue),
                                      maxLines: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                                child: Text(
                              episode.title!,
                              style: const TextStyle(fontSize: 16),
                            )),
                          ],
                        ),
                        renderHtml(context, episode.description!),
                      ],
                    ),
                  ),
                );
              },
            ));
  }
}

Widget renderHtml(context, String html) {
  // if starts with <
  if (html.trim().startsWith('<')) {
    var sanitized = sanitizeHtml(html).trim();
    if (sanitized.isEmpty) {
      sanitized = htmlToText(html)!;
    }
    return Html(
      data: sanitized,
    );
  }

  return Text(html, style: const TextStyle(fontSize: 14));
}
