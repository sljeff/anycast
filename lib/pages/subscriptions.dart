import 'package:anycast/models/subscription.dart';
import 'package:anycast/pages/channel.dart';
import 'package:anycast/states/channel.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:anycast/states/subscription.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class Subscriptions extends StatelessWidget {
  final SubscriptionController controller = Get.put(SubscriptionController());

  Subscriptions({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.subscriptions.isEmpty) {
        return Center(
          child: SizedBox(
            width: 300,
            child: Text(
              'Whoops! \n\nLooks like your podcast galaxy is still unexplored.\n \nStart subscribing and fill it with stars of shows!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontFamily: GoogleFonts.comfortaa().fontFamily,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.40,
              ),
            ),
          ),
        );
      }
      return ListView.separated(
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
        itemCount: controller.subscriptions.length,
        itemBuilder: (context, index) {
          return PodcastCard(subscription: controller.subscriptions[index]);
        },
      );
    });
  }
}

class PodcastCard extends StatelessWidget {
  final SubscriptionModel subscription;

  const PodcastCard({super.key, required this.subscription});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Get.lazyPut(() => ChannelController(channel: subscription),
            tag: subscription.rssFeedUrl);
        context.pushTransparentRoute(Channel(
          rssFeedUrl: subscription.rssFeedUrl!,
        ));
      },
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 12),
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                height: 80,
                padding: const EdgeInsets.all(8),
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      width: 1,
                      color: Colors.grey.shade800,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: subscription.imageUrl!,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: ShapeDecoration(
                          image: DecorationImage(
                            image: CachedNetworkImageProvider(
                              subscription.imageUrl!,
                            ),
                            fit: BoxFit.fill,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: ShapeDecoration(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 16,
                              clipBehavior: Clip.antiAlias,
                              decoration: const BoxDecoration(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      child: Text(
                                        subscription.title!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontFamily: GoogleFonts.comfortaa()
                                              .fontFamily,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subscription.description!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontFamily: 'PingFangSC-Regular,PingFang SC',
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
