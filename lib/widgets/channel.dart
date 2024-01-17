import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/widgets/feeds_episodes_list.dart';
import 'package:anycast/widgets/player.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:expandable_text/expandable_text.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';

class Channel extends StatelessWidget {
  final SubscriptionModel subscription;

  const Channel({Key? key, required this.subscription}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var screenSize = MediaQuery.of(context).size;

    return DismissiblePage(
      direction: DismissiblePageDismissDirection.down,
      onDismissed: () {
        Get.back();
        Get.delete<ChannelController>(tag: subscription.rssFeedUrl);
      },
      child: Obx(() {
        var controller =
            Get.find<ChannelController>(tag: subscription.rssFeedUrl);
        return Scaffold(
          floatingActionButton: PlayerWidget(),
          appBar: AppBar(
            centerTitle: true,
            leading: const SizedBox.shrink(),
            title: IconButton(
              onPressed: () {
                Get.back();
                Get.delete<ChannelController>(tag: subscription.rssFeedUrl);
              },
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
          body: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Hero(
                      tag: subscription.imageUrl!,
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: subscription.imageUrl!,
                            placeholder: (context, url) => const Icon(
                              Icons.image,
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.image_not_supported,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subscription.title!,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                          ),
                          Text(subscription.author!),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: () {
                        if (controller.subscribed.value) {
                          controller.unsubscribe();
                        } else {
                          controller.subscribe();
                        }
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: controller.subscribed.value
                            ? Colors.grey
                            : Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        controller.subscribed.value
                            ? 'Unsubscribe'
                            : 'Subscribe',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                width: screenSize.width,
                child: ExpandableText(
                  subscription.description!,
                  expandText: "show more",
                  collapseText: "show less",
                  maxLines: 3,
                  linkColor: Colors.blue,
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(
                            text: controller.channel.value.rssFeedUrl!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                          ),
                        );
                      },
                      child: SizedBox(
                        width: screenSize.width - 100,
                        child: Text(
                          controller.channel.value.rssFeedUrl!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        controller.reverseEpisodes();
                      },
                      icon: Transform.rotate(
                        angle: controller.isReversed.value ? 3.14 : 0,
                        child: const Icon(Icons.sort),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                  child: controller.isLoading.value
                      ? const Center(child: CircularProgressIndicator())
                      : FeedsEpisodesListView(controller.episodes, false))
            ],
          ),
        );
      }),
    );
  }
}
