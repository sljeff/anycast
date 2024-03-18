import 'package:anycast/states/channel.dart';
import 'package:anycast/pages/channel.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:anycast/states/subscription.dart';
import 'package:get/get.dart';

class Subscriptions extends StatelessWidget {
  final SubscriptionController controller = Get.put(SubscriptionController());

  Subscriptions({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.subscriptions.isEmpty) {
        return const Center(
          child: Text('No subscriptions'),
        );
      }
      return ListView.builder(
        itemCount: controller.subscriptions.length,
        itemBuilder: (context, index) {
          return ListTile(
            onTap: () {
              Get.lazyPut(
                  () => ChannelController(
                      channel: controller.subscriptions[index]),
                  tag: controller.subscriptions[index].rssFeedUrl);
              context.pushTransparentRoute(Channel(
                rssFeedUrl: controller.subscriptions[index].rssFeedUrl!,
              ));
            },
            leading: Hero(
              tag: controller.subscriptions[index].imageUrl!,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: controller.subscriptions[index].imageUrl!,
                  width: 50,
                  height: 50,
                  placeholder: (context, url) => const Icon(
                    Icons.image,
                  ),
                  errorWidget: (context, url, error) => const Icon(
                    Icons.image_not_supported,
                  ),
                ),
              ),
            ),
            title: Text(controller.subscriptions[index].title!),
            subtitle: Text(
              controller.subscriptions[index].description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      );
    });
  }
}
