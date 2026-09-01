import 'dart:convert';
import 'dart:io';

import 'package:anycast/design_system/anycast_theme.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/import_indicator.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/import_indicator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anycast/pages/feeds.dart';
import 'package:get/get.dart';
import 'package:opml/opml.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class ImportExportBlock extends StatefulWidget {
  const ImportExportBlock({super.key});

  @override
  State<ImportExportBlock> createState() => _ImportExportBlockState();
}

class _ImportExportBlockState extends State<ImportExportBlock> {
  final textController = TextEditingController();

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titleTextStyle: Theme.of(context).textTheme.headlineMedium,
      contentTextStyle: Theme.of(context).textTheme.bodyLarge,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Import/Export',
            style: Theme.of(context).textTheme.headlineMedium,
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
            icon: Icon(
              Icons.help_outline_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: AnycastSpacing.pageHeader,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      FilePicker.platform
                          .pickFiles(type: FileType.any)
                          .then((value) {
                        if (value != null) {
                          Get.dialog(const ImportIndicator());
                          parseOPML(value.files.single.path).then((value) {
                            var urls = value.map((e) => e.url).toList();
                            importPodcastsByUrls(
                              urls,
                              onProgress: (p0, p1) {
                                Get.find<ImportIndicatorController>()
                                    .progress
                                    .value = p0 / p1;
                              },
                            ).then((value) {
                              Get.find<FeedEpisodeController>().addMany(value
                                  .where((e) =>
                                      e.feedEpisodes != null &&
                                      e.feedEpisodes!.isNotEmpty)
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
                      backgroundColor:
                          Theme.of(context).colorScheme.inverseSurface,
                      foregroundColor:
                          Theme.of(context).colorScheme.onInverseSurface,
                      padding: const EdgeInsets.symmetric(
                        vertical: AnycastSpacing.gap,
                        horizontal: AnycastSpacing.xxl,
                      ),
                    ),
                    child: Text(
                      'Import',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onInverseSurface,
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
                      SharePlus.instance.share(
                        ShareParams(
                          files: [
                            XFile(
                              f.path,
                              mimeType: 'text/xml',
                            )
                          ],
                        ),
                      );
                    },
                    child: Text(
                      'Export',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            // input rss feed url
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AnycastSpacing.pageHeader,
              ),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Expanded(
                  child: TextField(
                    minLines: 1,
                    maxLines: 3,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'RSS Feed URL',
                    ),
                    controller: textController,
                    style: Theme.of(context).textTheme.bodyMedium,
                    onSubmitted: (url) {
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
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red,
                                  ),
                            ),
                            content: Text(
                              'Invalid RSS Feed URL',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.red),
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
        padding: const EdgeInsets.symmetric(
          horizontal: AnycastSpacing.pageHeader,
          vertical: AnycastSpacing.pageH,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Handler(),
            const SizedBox(height: AnycastSpacing.large),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  'Import OPML from',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: AnycastSpacing.md),
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
                          '5. Share to "Anycast"'),
                  ExpansionInstruction(
                      title: 'Overcast',
                      description: '1. Open Overcast.\n'
                          '2. Tap the Settings icon on the top left.\n'
                          '3. Scroll down to "Export OPML" and tap it.\n'
                          '4. Share to "Anycast"'),
                  ExpansionInstruction(
                      title: "Pocket Casts",
                      description: '1. Open Pocket Casts -> Profile\n'
                          '2. Tap Settings icon on the top right\n'
                          '3. Scroll down to "Export Podcasts"\n'
                          '4. Click "Export Podcasts"\n'
                          '5. Share to "Anycast"'),
                  ExpansionInstruction(
                      title: '小宇宙',
                      description: '1. 打开小宇宙 -> 订阅\n'
                          '2. 点击右上角 "我的订阅"\n'
                          '3. 点击右上角的分享按钮\n'
                          '4. 选中所有想要导入的频道\n'
                          '5. 点击 "导出 OPML"\n'
                          '6. 分享到 "Anycast"'),
                  ExpansionInstruction(
                      title: 'Other Apps using OPML',
                      description: '1. Find your OPML file\n'
                          '2. Share to "Anycast"'),
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
      collapsedIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      iconColor: Theme.of(context).colorScheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      children: [
        Container(
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.only(left: AnycastSpacing.large),
          child: Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
