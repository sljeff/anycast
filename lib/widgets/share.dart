import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/share.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ShareDialog extends GetView<ShareController> {
  const ShareDialog({super.key});

  @override
  Widget build(BuildContext context) {
    if (controller.sharedFile == null || controller.opmls.isEmpty) {
      return AlertDialog(
        title: Text(
          'Import Podcasts',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        content: Text(
          'Oh no! Seems like there is no valid links in the file.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: Text(
              'OK',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      );
    }
    return AlertDialog(
      titleTextStyle: Theme.of(context).textTheme.headlineMedium,
      contentTextStyle: Theme.of(context).textTheme.bodyLarge,
      title: const Text("Import Podcasts"),
      content: SizedBox(
        width: Get.width * 0.8,
        height: 300,
        child: Obx(
          () {
            // parse opml
            final opmls = controller.opmls;

            return ListView.separated(
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemCount: opmls.length,
              itemBuilder: (context, index) {
                return Card(
                  child: ListTile(
                    title: Text(
                      opmls[index].title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Get.back();
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: () async {
            Get.dialog(const ImportProgressIndicator());
            var result = await importPodcastsByUrls(
              controller.opmls.map((e) => e.url).toList(),
              onProgress: (progress, total) {
                controller.progress.value = progress / total;
              },
            );
            Get.find<FeedEpisodeController>().addMany(result
                .where(
                    (e) => e.feedEpisodes != null && e.feedEpisodes!.isNotEmpty)
                .map((e) => e.feedEpisodes![0])
                .toList());
            Get.find<SubscriptionController>()
                .addMany(result.map((e) => e.subscription!).toList());

            Get.back();
            Get.back();
            controller.progress.value = 0;

            var titles =
                result.map((e) => e.subscription!.title).toList().join(', ');
            if (titles.length > 50) {
              titles = '${titles.substring(0, 50)}...';
            }
            Get.snackbar('Success', 'Import $titles successfully',
                snackPosition: SnackPosition.BOTTOM);
          },
          style: TextButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.inverseSurface,
            foregroundColor: Theme.of(context).colorScheme.onInverseSurface,
          ),
          child: Text(
            'Import',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                ),
          ),
        ),
      ],
    );
  }
}

class ImportProgressIndicator extends GetView<ShareController> {
  const ImportProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Obx(
        () {
          var progress = controller.progress.value;
          return CircularProgressIndicator(
            value: progress,
            color: Theme.of(context).colorScheme.primary,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            strokeWidth: 2,
            strokeCap: StrokeCap.round,
          );
        },
      ),
    );
  }
}
