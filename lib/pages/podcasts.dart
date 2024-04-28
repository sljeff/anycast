import 'dart:convert';
import 'dart:io';

import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/keepalive.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/appbar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anycast/pages/feeds.dart';
import 'package:get/get.dart';
import 'package:opml/opml.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class PodcastsPage extends StatelessWidget {
  const PodcastsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        extendBodyBehindAppBar: false,
        appBar: MyAppBar(
          title: 'PODCAST',
          icon: Icons.import_export,
          iconOnTap: () {
            Get.dialog(const ImportExportBlock());
          },
        ),
        body: KeepAliveWrapper(key: const Key('feeds'), child: Feeds()));
  }
}

class ImportExportBlock extends StatelessWidget {
  const ImportExportBlock({super.key});

  @override
  Widget build(BuildContext context) {
    var textController = TextEditingController();

    return AlertDialog(
      title: const Text('Import/Export'),
      content: SizedBox(
        width: 300,
        height: 100,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['xml'],
                    ).then((value) {
                      if (value != null) {
                        Get.dialog(
                            const Center(child: CircularProgressIndicator()));
                        parseOMPL(value.files.single.path).then((value) {
                          importPodcastsByUrls(value).then((value) {
                            Get.find<FeedEpisodeController>().addMany(
                                value.map((e) => e.feedEpisodes![0]).toList());
                            Get.find<SubscriptionController>().addMany(
                                value.map((e) => e.subscription!).toList());
                            Get.back();
                            Get.back();
                            var titles = value
                                .map((e) => e.subscription!.title)
                                .toList()
                                .join(', ');
                            if (titles.length > 50) {
                              titles = '${titles.substring(0, 50)}...';
                            }
                            Get.snackbar(
                                'Success', 'Import $titles successfully',
                                snackPosition: SnackPosition.BOTTOM);
                          });
                        });
                      }
                    });
                  },
                  child: const Text('Import'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    var opml = generateOPML(
                        Get.find<SubscriptionController>().subscriptions);
                    Directory appDocDirectory =
                        await getApplicationDocumentsDirectory();
                    var f = File(
                        '${appDocDirectory.path}/anycast_subscriptions.xml');
                    await f.writeAsBytes(
                        const Utf8Encoder().convert(opml.toString()));
                    Share.shareXFiles([
                      XFile(
                        f.path,
                        mimeType: 'text/xml',
                      )
                    ]);
                  },
                  child: const Text('Export'),
                ),
              ],
            ),
            // input rss feed url
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'RSS Feed URL',
                  ),
                  controller: textController,
                ),
              ),
              IconButton(
                onPressed: () {
                  var url = textController.text;
                  if (url.isEmpty) {
                    return;
                  }
                  // show loading
                  Get.dialog(const Center(child: CircularProgressIndicator()));
                  // fetch rss feed
                  importPodcastsByUrls([url]).then((value) {
                    Get.find<FeedEpisodeController>()
                        .addMany(value.map((e) => e.feedEpisodes![0]).toList());
                    Get.find<SubscriptionController>()
                        .addMany(value.map((e) => e.subscription!).toList());
                    Get.back();
                    Get.back();
                    // show success import {title}
                    Get.snackbar('Success',
                        'Import ${value[0].subscription!.title} successfully',
                        snackPosition: SnackPosition.BOTTOM);
                  });
                },
                icon: const Icon(Icons.add),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

String generateOPML(List<SubscriptionModel> subscriptions) {
  var head = OpmlHeadBuilder().title('Anycast Subscriptions').build();
  var body = <OpmlOutline>[];
  for (var subscription in subscriptions) {
    body.add(OpmlOutlineBuilder()
        .title(subscription.title!)
        .text(subscription.description!)
        .type('rss')
        .xmlUrl(subscription.rssFeedUrl!)
        .build());
  }
  return OpmlDocument(head: head, body: body).toXmlString(pretty: true);
}

void writeOPML(String path, String opml) {
  File(path).writeAsString(opml).then((value) {
    Get.snackbar('Success', 'Save to $path successfully',
        snackPosition: SnackPosition.BOTTOM);
  });
}
