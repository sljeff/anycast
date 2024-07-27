import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/share.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class ShareDialog extends GetView<ShareController> {
  const ShareDialog({super.key});

  @override
  Widget build(BuildContext context) {
    if (controller.sharedFile == null || controller.opmls.isEmpty) {
      return const AlertDialog(
        title: Text('Import Podcasts'),
        content: Text('Oh no! Seems like there is no valid links in the file.'),
      );
    }
    return AlertDialog(
      titleTextStyle: GoogleFonts.comfortaa(
        fontSize: 20,
        color: Colors.white,
        decoration: TextDecoration.none,
        fontWeight: FontWeight.w400,
      ),
      contentTextStyle: GoogleFonts.comfortaa(
        fontSize: 18,
        color: Colors.white,
        decoration: TextDecoration.none,
      ),
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
                  color: Colors.black,
                  child: ListTile(
                    title: Text(
                      opmls[index].title,
                      style: GoogleFonts.comfortaa(
                        fontSize: 16,
                        color: Colors.white,
                      ),
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
            Get.find<FeedEpisodeController>()
                .addMany(result.map((e) => e.feedEpisodes![0]).toList());
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
          child: const Text('Import'),
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
            color: Colors.green,
            backgroundColor: Colors.white.withOpacity(0.4),
            strokeWidth: 2,
            strokeCap: StrokeCap.round,
          );
        },
      ),
    );
  }
}
