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
      final state = anycastCollectionVisualState(
        isLoading: controller.isLoading.value,
        hasError: controller.loadError.value != null,
        isEmpty: controller.subscriptions.isEmpty,
      );
      switch (state) {
        case AnycastCollectionVisualState.loading:
          return const AnycastLoadingState(
            label: 'Loading subscriptions…',
          );
        case AnycastCollectionVisualState.error:
          return AnycastEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn’t load subscriptions',
            message: 'Check the local library and try again.',
            action: TextButton.icon(
              onPressed: controller.load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          );
        case AnycastCollectionVisualState.empty:
          return const AnycastEmptyState(
            icon: Icons.library_music_rounded,
            title: 'No subscriptions yet',
            message: 'Follow a podcast to keep it close at hand.',
          );
        case AnycastCollectionVisualState.content:
          break;
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
