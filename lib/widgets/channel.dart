import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/widgets/feeds_episodes_list.dart';
import 'package:anycast/widgets/player.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:expandable_text/expandable_text.dart';
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
            leading: SizedBox.shrink(),
            title: IconButton(
              onPressed: () {
                Get.back();
                Get.delete<ChannelController>(tag: subscription.rssFeedUrl);
              },
              icon: Icon(Icons.keyboard_arrow_down),
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
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      width: screenSize.width - 200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subscription.title!,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                          ),
                          Text(subscription.author!),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            onPressed: () {
                              if (controller.subscribed.value) {
                                controller.unsubscribe();
                              } else {
                                controller.subscribe();
                              }
                            },
                            icon: Icon(controller.subscribed.value
                                ? Icons.check
                                : Icons.add),
                          ),
                        ],
                      ),
                    ),
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
              const SizedBox(height: 16),
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
