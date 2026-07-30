import 'package:anycast/design_system/anycast_components.dart';
import 'package:anycast/design_system/anycast_theme.dart';
import 'package:anycast/widgets/card.dart';
import 'package:flutter/material.dart';
import 'package:anycast/states/subscription.dart';
import 'package:get/get.dart';

class Subscriptions extends StatelessWidget {
  static final controller = Get.put(SubscriptionController());

  const Subscriptions({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.subscriptions.isEmpty) {
        return const AnycastEmptyState(
          icon: Icons.library_music_rounded,
          title: 'Whoops!',
          message: 'Looks like your podcast galaxy is still unexplored.',
        );
      }
      return ListView.separated(
        separatorBuilder: (context, index) =>
            const SizedBox(height: AnycastSpacing.gap),
        padding: const EdgeInsets.only(
          top: AnycastSpacing.gap,
          bottom: AnycastSpacing.pageBottomSafe,
        ),
        itemCount: controller.subscriptions.length,
        itemBuilder: (context, index) {
          return PodcastCard(subscription: controller.subscriptions[index]);
        },
      );
    });
  }
}
