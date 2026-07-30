import 'dart:io';

import 'package:anycast/design_system/anycast_theme.dart';
import 'package:anycast/pages/login.dart';
import 'package:anycast/pages/playlists.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/import_export.dart';
import 'package:anycast/widgets/privacy.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ph.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

const targetLangList = [
  {'name': 'English', 'code': 'en'},
  {'name': 'Français', 'code': 'fr'},
  {'name': 'Deutsch', 'code': 'de'},
  {'name': 'Español', 'code': 'es'},
  {'name': 'Italiano', 'code': 'it'},
  {'name': '日本語', 'code': 'ja'},
  {'name': '中文', 'code': 'zh'},
  {'name': 'Portugues', 'code': 'pt'},
  {'name': 'Nederlands', 'code': 'nl'},
  {'name': 'українська', 'code': 'uk'},
  {'name': 'Pусский', 'code': 'ru'},
];

var countryList = [
  {'name': 'Argentina', 'code': 'AR'},
  {'name': 'Australia', 'code': 'AU'},
  {'name': 'Österreich', 'code': 'AT'},
  {'name': 'Bangladesh', 'code': 'BD'},
  {'name': 'België / Belgique', 'code': 'BE'},
  {'name': 'Brasil', 'code': 'BR'},
  {'name': 'Canada', 'code': 'CA'},
  {'name': 'Schweiz', 'code': 'CH'},
  {'name': 'Chile', 'code': 'CL'},
  {'name': '中国', 'code': 'CN'},
  {'name': 'Colombia', 'code': 'CO'},
  {'name': 'Česká republika', 'code': 'CZ'},
  {'name': 'Deutschland', 'code': 'DE'},
  {'name': 'Danmark', 'code': 'DK'},
  {'name': 'مصر', 'code': 'EG'},
  {'name': 'España', 'code': 'ES'},
  {'name': 'Suomi', 'code': 'FI'},
  {'name': 'France', 'code': 'FR'},
  {'name': 'United Kingdom', 'code': 'GB'},
  {'name': 'Ελλάδα', 'code': 'GR'},
  {'name': 'Magyarország', 'code': 'HU'},
  {'name': 'Indonesia', 'code': 'ID'},
  {'name': 'Ireland', 'code': 'IE'},
  {'name': 'Israel', 'code': 'IL'},
  {'name': 'India', 'code': 'IN'},
  {'name': 'Italia', 'code': 'IT'},
  {'name': '日本', 'code': 'JP'},
  {'name': '대한민국', 'code': 'KR'},
  {'name': 'México', 'code': 'MX'},
  {'name': 'Malaysia', 'code': 'MY'},
  {'name': 'Nigeria', 'code': 'NG'},
  {'name': 'Nederland', 'code': 'NL'},
  {'name': 'Norge', 'code': 'NO'},
  {'name': 'New Zealand', 'code': 'NZ'},
  {'name': 'Pakistan', 'code': 'PK'},
  {'name': 'Polska', 'code': 'PL'},
  {'name': 'Philippines', 'code': 'PH'},
  {'name': 'Portugal', 'code': 'PT'},
  {'name': 'România', 'code': 'RO'},
  {'name': 'Россия', 'code': 'RU'},
  {'name': 'Saudi Arabia', 'code': 'SA'},
  {'name': 'Sverige', 'code': 'SE'},
  {'name': 'Singapore', 'code': 'SG'},
  {'name': 'ประเทศไทย', 'code': 'TH'},
  {'name': 'Türkiye', 'code': 'TR'},
  {'name': 'Україна', 'code': 'UA'},
  {'name': 'United States', 'code': 'US'},
  {'name': 'Việt Nam', 'code': 'VN'},
  {'name': 'South Africa', 'code': 'ZA'},
];

class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    countryList.sort((a, b) => a['name']!.compareTo(b['name']!));
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.titleMedium!,
          child: Column(
            children: [
              const Handler(),
              const SizedBox(height: AnycastSpacing.gap),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AnycastSpacing.pageH,
                    0,
                    AnycastSpacing.pageH,
                    AnycastSpacing.pageBottomSafe,
                  ),
                  children: [
                    GestureDetector(
                      onTap: () {
                        showMaterialModalBottomSheet(
                          expand: true,
                          context: context,
                          builder: (context) {
                            return const LoginPage();
                          },
                          closeProgressThreshold: 0.9,
                        );
                      },
                      child: const SettingsGroup(
                        children: [
                          SettingContainer(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(Icons.person),
                                SizedBox(width: AnycastSpacing.md),
                                Text('Account'),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                    SettingsGroup(title: "Transcript & Translation", children: [
                      SettingContainer(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Text('Country'),
                                SizedBox(width: AnycastSpacing.md),
                                Tooltip(
                                  triggerMode: TooltipTriggerMode.tap,
                                  showDuration: Duration(milliseconds: 2000),
                                  message:
                                      "Discover page will show episodes from this country.",
                                  child: Icon(Icons.info_outline),
                                ),
                              ],
                            ),
                            Container(
                              alignment: Alignment.center,
                              width: 160,
                              decoration: ShapeDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AnycastRadius.md,
                                  ),
                                ),
                              ),
                              child: Obx(
                                () {
                                  return CountryCodePicker(
                                    hideSearch: true,
                                    countryList: countryList,
                                    padding: const EdgeInsets.all(0),
                                    showFlag: false,
                                    barrierColor: Colors.transparent,
                                    dialogBackgroundColor:
                                        Theme.of(context).colorScheme.surface,
                                    boxDecoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(
                                        AnycastRadius.card,
                                      ),
                                    ),
                                    closeIcon: const Icon(Icons.close_rounded),
                                    textStyle:
                                        Theme.of(context).textTheme.bodyMedium,
                                    dialogTextStyle:
                                        Theme.of(context).textTheme.bodyLarge,
                                    onChanged: (value) {
                                      controller.setCountryCode(value.code!);
                                    },
                                    initialSelection:
                                        controller.countryCode.value,
                                    showCountryOnly: true,
                                    showOnlyCountryWhenClosed: true,
                                    alignLeft: false,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      SettingContainer(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Enable Transcript Translation'),
                            Obx(() {
                              var controller = Get.find<SettingsController>();
                              return Material(
                                color: Colors.transparent,
                                child: Switch(
                                  value: controller.targetLanguage.value != '',
                                  onChanged: (value) {
                                    if (!value) {
                                      controller.setTargetLanguage('');
                                      return;
                                    }
                                    var code = Platform.localeName;
                                    var languageAndCountry = code.split('_');
                                    var language = 'en';
                                    if (languageAndCountry.length > 1) {
                                      language = code.split('_')[0];
                                    }

                                    controller.setTargetLanguage(language);
                                  },
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      Obx(
                        () {
                          var controller = Get.find<SettingsController>();
                          if (controller.targetLanguage.value == '') {
                            return const SizedBox.shrink();
                          }

                          return const SettingContainer(
                            indent: 1,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(children: [
                                  Text('Target Language'),
                                  SizedBox(width: AnycastSpacing.md),
                                  Tooltip(
                                    triggerMode: TooltipTriggerMode.tap,
                                    showDuration: Duration(milliseconds: 2000),
                                    message:
                                        "Translates the podcast transcript into the target language.",
                                    child: Icon(Icons.info_outline),
                                  ),
                                ]),
                                LanguagePicker(),
                              ],
                            ),
                          );
                        },
                      )
                    ]),
                    SettingsGroup(
                      title: "Podcast",
                      children: [
                        GestureDetector(
                          onTap: () {
                            Get.dialog(const ImportExportBlock());
                          },
                          child: const SettingContainer(
                            child: Text('Import / Export'),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Get.dialog(const HistoryBlock());
                          },
                          child: const SettingContainer(
                            child: Text('History'),
                          ),
                        ),
                      ],
                    ),
                    SettingsGroup(
                      title: "Other",
                      children: [
                        SettingContainer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Text('Auto Refresh Interval'),
                                  SizedBox(width: AnycastSpacing.md),
                                  Tooltip(
                                    triggerMode: TooltipTriggerMode.tap,
                                    showDuration: Duration(milliseconds: 2000),
                                    message:
                                        "Automatically fetch new episodes every X minutes.",
                                    child: Icon(Icons.info_outline),
                                  ),
                                ],
                              ),
                              TextButton(
                                  child: Obx(() => Text(
                                        '${controller.autoRefreshInterval.value ~/ 60} min',
                                      )),
                                  onPressed: () {
                                    var minutes = [1, 3, 5, 10, 30];
                                    var interval =
                                        controller.autoRefreshInterval.value;
                                    var initialIndex =
                                        minutes.indexOf(interval ~/ 60);

                                    Get.bottomSheet(
                                      SettingsBottomContainer(
                                          picker: CupertinoPicker(
                                        scrollController:
                                            FixedExtentScrollController(
                                          initialItem: initialIndex,
                                        ),
                                        itemExtent: 36,
                                        onSelectedItemChanged: (index) {
                                          controller.setAutoRefreshInterval(
                                              minutes[index] * 60);
                                        },
                                        children: const [
                                          Center(child: Text('1 min')),
                                          Center(child: Text('3 min')),
                                          Center(child: Text('5 min')),
                                          Center(child: Text('10 min')),
                                          Center(child: Text('30 min')),
                                        ],
                                      )),
                                      backgroundColor:
                                          Theme.of(context).colorScheme.surface,
                                    );
                                  })
                            ],
                          ),
                        ),
                        SettingContainer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(children: [
                                Text('Max Episodes in Inbox'),
                                SizedBox(width: AnycastSpacing.md),
                                Tooltip(
                                  triggerMode: TooltipTriggerMode.tap,
                                  showDuration: Duration(milliseconds: 2000),
                                  message:
                                      "Limits the number of episodes in the inbox. Auto deleted if exceeded.",
                                  child: Icon(Icons.info_outline),
                                ),
                              ]),
                              TextButton(
                                child: Obx(() => Text(controller
                                    .maxFeedEpisodes.value
                                    .toString())),
                                onPressed: () {
                                  Get.bottomSheet(
                                    SettingsBottomContainer(
                                        picker: CupertinoPicker(
                                      scrollController:
                                          FixedExtentScrollController(
                                        initialItem:
                                            controller.maxFeedEpisodes.value ~/
                                                100,
                                      ),
                                      itemExtent: 36,
                                      onSelectedItemChanged: (index) {
                                        controller.setMaxFeedEpisodes(
                                            [50, 100, 200, 300][index]);
                                      },
                                      children: const [
                                        Center(child: Text('50')),
                                        Center(child: Text('100')),
                                        Center(child: Text('200')),
                                        Center(child: Text('300')),
                                      ],
                                    )),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.surface,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        SettingContainer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(children: [
                                Text('Max Episodes in History'),
                                SizedBox(width: AnycastSpacing.md),
                                Tooltip(
                                  triggerMode: TooltipTriggerMode.tap,
                                  showDuration: Duration(milliseconds: 2000),
                                  message:
                                      "Limits the number of episodes in the history. Auto deleted if exceeded.",
                                  child: Icon(Icons.info_outline),
                                ),
                              ]),
                              TextButton(
                                child: Obx(() => Text(controller
                                    .maxHistoryEpisodes.value
                                    .toString())),
                                onPressed: () {
                                  Get.bottomSheet(
                                    SettingsBottomContainer(
                                        picker: CupertinoPicker(
                                      scrollController:
                                          FixedExtentScrollController(
                                        initialItem: controller
                                                .maxHistoryEpisodes.value ~/
                                            100,
                                      ),
                                      itemExtent: 36,
                                      onSelectedItemChanged: (index) {
                                        controller.setMaxHistoryEpisodes(
                                            [50, 100, 200, 300][index]);
                                      },
                                      children: const [
                                        Center(child: Text('50')),
                                        Center(child: Text('100')),
                                        Center(child: Text('200')),
                                        Center(child: Text('300')),
                                      ],
                                    )),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.surface,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SettingsGroup(
                      title: "Contact",
                      children: [
                        SettingContainer(
                          child: GestureDetector(
                            onTap: () async {
                              var uri = Uri(
                                scheme: 'mailto',
                                path: 'kindjeffcom@gmail.com',
                                query: encodeQueryParameters(
                                  {"subject": "Anycast Feedback"},
                                ),
                              );
                              await launchUrl(uri);
                            },
                            child: Text(
                              'kindjeff.com@gmail.com',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: AnycastColor.gold10,
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Privacy(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingContainer extends StatelessWidget {
  final int indent;
  final Widget child;

  const SettingContainer({super.key, required this.child, this.indent = 0});

  @override
  Widget build(BuildContext context) {
    var c = Container(
      constraints: const BoxConstraints(minHeight: 52),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(
        horizontal: AnycastSpacing.pageHeader,
        vertical: AnycastSpacing.row,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
      ),
      child: child,
    );

    if (indent == 0) {
      return c;
    } else {
      return Row(
        children: [
          Iconify(
            Ph.arrow_elbow_down_right_bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          Expanded(child: c),
        ],
      );
    }
  }
}

class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const SettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    var c = children;

    if (title != null) {
      c = [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AnycastSpacing.pageHeader,
            vertical: AnycastSpacing.gap,
          ),
          alignment: Alignment.bottomLeft,
          child: Text(
            title!,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
          ),
        ),
        const Divider(height: 1),
        ...c,
      ];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AnycastSpacing.sectionGap),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AnycastRadius.card),
      ),
      child: Column(
        children: c,
      ),
    );
  }
}

class LanguagePicker extends GetView<SettingsController> {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => CountryCodePicker(
        showFlag: false,
        hideSearch: true,
        barrierColor: Colors.transparent,
        dialogBackgroundColor: Theme.of(context).colorScheme.surface,
        boxDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AnycastRadius.card),
        ),
        closeIcon: const Icon(Icons.close_rounded),
        textStyle: Theme.of(context).textTheme.bodyMedium,
        dialogTextStyle: Theme.of(context).textTheme.bodyLarge,
        onChanged: (value) {
          controller.setTargetLanguage(value.code!);
        },
        initialSelection: controller.targetLanguage.value,
        showCountryOnly: true,
        showOnlyCountryWhenClosed: true,
        alignLeft: false,
        countryList: targetLangList,
      ),
    );
  }
}

class SettingsBottomContainer extends StatelessWidget {
  final Widget picker;

  const SettingsBottomContainer({super.key, required this.picker});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      alignment: Alignment.center,
      child: Column(
        children: [
          const SizedBox(height: AnycastSpacing.gap),
          const Handler(),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 60,
                  width: 100,
                  child: picker,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
