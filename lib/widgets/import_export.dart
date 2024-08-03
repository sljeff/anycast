import 'dart:convert';
import 'dart:io';

import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anycast/pages/feeds.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
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
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Import/Export',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          IconButton(
            onPressed: () {
              showModalBottomSheet(
                useSafeArea: true,
                isScrollControlled: true,
                context: context,
                builder: (context) {
                  return const ImportInstructions();
                },
              );
            },
            icon: const Iconify(Ic.round_help, color: Colors.white70),
          )
        ],
      ),
      content: SizedBox(
        width: 300,
        height: 200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      FilePicker.platform
                          .pickFiles(type: FileType.any)
                          .then((value) {
                        if (value != null) {
                          Get.dialog(
                              const Center(child: CircularProgressIndicator()));
                          parseOPML(value.files.single.path).then((value) {
                            var urls = value.map((e) => e.url).toList();
                            importPodcastsByUrls(urls).then((value) {
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
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 48,
                      ),
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
                    child: Text(
                      'Export',
                      style: TextStyle(
                        color: const Color(0xFF10B981),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 2.40,
                        fontFamily: GoogleFonts.comfortaa().fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // input rss feed url
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Expanded(
                  child: TextField(
                    minLines: 1,
                    maxLines: 3,
                    keyboardType: TextInputType.url,
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
                      fontSize: 12,
                      fontFamily: GoogleFonts.comfortaa().fontFamily,
                      fontWeight: FontWeight.w400,
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
                        if (value.isEmpty) {
                          Get.back();
                          // alert error
                          Get.dialog(Center(
                              child: AlertDialog(
                            title: Text(
                              'Error',
                              style: GoogleFonts.comfortaa(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: Colors.red,
                              ),
                            ),
                            content: Text(
                              'Invalid RSS Feed URL',
                              style: GoogleFonts.comfortaa(
                                fontSize: 14,
                                color: Colors.red,
                              ),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () {
                                    Get.back();
                                  },
                                  child: const Text('OK')),
                            ],
                          )));
                          return;
                        }
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

class ImportInstructions extends StatelessWidget {
  const ImportInstructions({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.6,
      expand: false,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Handler(),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  'Import OPML from',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontFamily: GoogleFonts.comfortaa().fontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: controller,
                children: const [
                  ExpansionInstruction(
                      title: 'Castro',
                      description: '1. Open Castro.\n'
                          '2. Tap the Settings icon on the top left.\n'
                          '3. Scroll down to "User Data" and tap it.\n'
                          '4. Click "Export Subscriptions"\n'
                          '5. Share to "Anycast+"'),
                  ExpansionInstruction(
                      title: 'Overcast',
                      description: '1. Open Overcast.\n'
                          '2. Tap the Settings icon on the top left.\n'
                          '3. Scroll down to "Export OPML" and tap it.\n'
                          '4. Share to "Anycast+"'),
                  ExpansionInstruction(
                      title: "Pocket Casts",
                      description: '1. Open Pocket Casts -> Profile\n'
                          '2. Tap Settings icon on the top right\n'
                          '3. Scroll down to "Export Podcasts"\n'
                          '4. Click "Export Podcasts"\n'
                          '5. Share to "Anycast+"'),
                  ExpansionInstruction(
                      title: '小宇宙',
                      description: '1. 打开小宇宙 -> 订阅\n'
                          '2. 点击右上角 "我的订阅"\n'
                          '3. 点击右上角的分享按钮\n'
                          '4. 选中所有想要导入的频道\n'
                          '5. 点击 "导出 OPML"\n'
                          '6. 分享到 "Anycast+"'),
                  ExpansionInstruction(
                      title: 'Other Apps using OPML',
                      description: '1. Find your OPML file\n'
                          '2. Share to "Anycast+"'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExpansionInstruction extends StatelessWidget {
  final String title;
  final String description;

  const ExpansionInstruction(
      {super.key, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      collapsedIconColor: Colors.white,
      iconColor: Colors.green,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      title: Text(
        title,
        style: GoogleFonts.comfortaa(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Colors.white,
        ),
      ),
      children: [
        Container(
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.only(left: 32),
          child: Text(
            description,
            style: GoogleFonts.comfortaa(
              fontSize: 12,
              color: Colors.white,
            ),
          ),
        ),
      ],
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
