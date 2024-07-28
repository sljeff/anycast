import 'dart:convert';
import 'dart:io';

import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anycast/pages/feeds.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:opml/opml.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class ImportExportBlock extends StatelessWidget {
  const ImportExportBlock({super.key});

  @override
  Widget build(BuildContext context) {
    var textController = TextEditingController();

    return AlertDialog(
      titleTextStyle: GoogleFonts.comfortaa(
        fontSize: 20,
      ),
      contentTextStyle: GoogleFonts.comfortaa(
        fontSize: 18,
      ),
      title: const Text('Import/Export'),
      content: SizedBox(
        width: 300,
        height: 120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['xml'],
                      ).then((value) {
                        if (value != null) {
                          Get.dialog(
                              const Center(child: CircularProgressIndicator()));
                          parseOPML(value.files.single.path).then((value) {
                            importPodcastsByUrls(value).then((value) {
                              Get.find<FeedEpisodeController>().addMany(value
                                  .map((e) => e.feedEpisodes![0])
                                  .toList());
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
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                    ),
                    child: Text(
                      'Import',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: 2.40,
                        fontFamily: GoogleFonts.comfortaa().fontFamily,
                      ),
                    ),
                  ),
                  TextButton(
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
                    style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981)),
                    child: Text(
                      'Export',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: 2.40,
                        fontFamily: GoogleFonts.comfortaa().fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // input rss feed url
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'RSS Feed URL',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                    controller: textController,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: GoogleFonts.comfortaa().fontFamily,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                    onChanged: (value) {
                      textController.text = value;
                    },
                    onSubmitted: (url) {
                      textController.text = url;
                      if (url.isEmpty) {
                        return;
                      }
                      // show loading
                      Get.dialog(
                          const Center(child: CircularProgressIndicator()));
                      // fetch rss feed
                      importPodcastsByUrls([url]).then((value) {
                        Get.find<FeedEpisodeController>().addMany(
                            value.map((e) => e.feedEpisodes![0]).toList());
                        Get.find<SubscriptionController>().addMany(
                            value.map((e) => e.subscription!).toList());
                        Get.back();
                        Get.back();
                        // show success import {title}
                        Get.snackbar('Success',
                            'Import ${value[0].subscription!.title} successfully',
                            snackPosition: SnackPosition.BOTTOM);
                      });
                    },
                  ),
                ),
              ]),
            ),
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
