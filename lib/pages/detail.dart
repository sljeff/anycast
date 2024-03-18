import 'package:anycast/models/episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/pages/channel.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
                          mainAxisAlignment: MainAxisAlignment.start,
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
                            const SizedBox(width: 16),
                            Expanded(
                                child: Column(
                              children: [
                                Container(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    episode.title!,
                                    style: const TextStyle(fontSize: 16),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  alignment: Alignment.centerLeft,
                                  child: GestureDetector(
                                    onTap: () {
                                      var s = subscriptionController
                                          .getByTitle(episode.channelTitle!);
                                      if (s == null) {
                                        s = SubscriptionModel.empty();
                                        s.rssFeedUrl = episode.rssFeedUrl;
                                      }
                                      Get.lazyPut(
                                          () => ChannelController(channel: s!),
                                          tag: s.rssFeedUrl);
                                      context.pushTransparentRoute(
                                          Channel(rssFeedUrl: s.rssFeedUrl!));
                                    },
                                    child: Text(
                                      episode.channelTitle!,
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.blue),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            )),
                            const SizedBox(width: 16),
                          ],
                        ),
                        const SizedBox(width: 16),
                        renderHtml(context, episode.description!),
                      ],
                    ),
                  ),
                );
              },
            ));
  }
}
