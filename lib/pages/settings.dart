import 'dart:io';

import 'package:anycast/pages/login.dart';
import 'package:anycast/pages/playlists.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/import_export.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
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

const countryList = [
  {'name': 'United States', 'code': 'US'},
  {'name': '中国', 'code': 'CN'},
  {'name': 'India', 'code': 'IN'},
  {'name': 'Japan', 'code': 'JP'},
  {'name': 'Deutschland', 'code': 'DE'},
  {'name': 'United Kingdom', 'code': 'GB'},
  {'name': 'France', 'code': 'FR'},
  {'name': 'Brasil', 'code': 'BR'},
  {'name': 'Italia', 'code': 'IT'},
  {'name': 'Россия', 'code': 'RU'},
  {'name': 'Canada', 'code': 'CA'},
  {'name': '대한민국', 'code': 'KR'},
  {'name': 'España', 'code': 'ES'},
  {'name': 'Australia', 'code': 'AU'},
  {'name': 'México', 'code': 'MX'},
  {'name': 'Indonesia', 'code': 'ID'},
  {'name': 'Nederland', 'code': 'NL'},
  {'name': 'Türkiye', 'code': 'TR'},
  {'name': 'Saudi Arabia', 'code': 'SA'},
  {'name': 'Schweiz', 'code': 'CH'},
  {'name': 'Argentina', 'code': 'AR'},
  {'name': 'Sverige', 'code': 'SE'},
  {'name': 'Polska', 'code': 'PL'},
  {'name': 'België / Belgique', 'code': 'BE'},
  {'name': 'Norge', 'code': 'NO'},
  {'name': 'Österreich', 'code': 'AT'},
  {'name': 'Danmark', 'code': 'DK'},
  {'name': 'ประเทศไทย', 'code': 'TH'},
  {'name': 'Suomi', 'code': 'FI'},
  {'name': 'Portugal', 'code': 'PT'},
  {'name': 'Ελλάδα', 'code': 'GR'},
  {'name': 'Israel', 'code': 'IL'},
  {'name': 'Ireland', 'code': 'IE'},
  {'name': 'Česká republika', 'code': 'CZ'},
  {'name': 'Singapore', 'code': 'SG'},
  {'name': 'New Zealand', 'code': 'NZ'},
  {'name': 'Việt Nam', 'code': 'VN'},
  {'name': 'South Africa', 'code': 'ZA'},
  {'name': 'Malaysia', 'code': 'MY'},
  {'name': 'Chile', 'code': 'CL'},
  {'name': 'Philippines', 'code': 'PH'},
  {'name': 'Colombia', 'code': 'CO'},
  {'name': 'Egypt', 'code': 'EG'},
  {'name': 'România', 'code': 'RO'},
  {'name': 'Україна', 'code': 'UA'},
  {'name': 'Pakistan', 'code': 'PK'},
  {'name': 'Magyarország', 'code': 'HU'},
  {'name': 'مصر', 'code': 'EG'},
  {'name': 'Bangladesh', 'code': 'BD'},
  {'name': 'Nigeria', 'code': 'NG'}
];

class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111316),
      child: SafeArea(
        child: DefaultTextStyle(
          style: TextStyle(
            color: Colors.white,
            decoration: TextDecoration.none,
            fontFamily: GoogleFonts.comfortaa().fontFamily,
            fontWeight: FontWeight.w400,
            fontSize: 14,
          ),
          child: Column(
            children: [
              const Handler(),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    SettingsGroup(
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
                                    SizedBox(width: 8),
                                    Text('Account'),
                                  ],
                                ),
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                    SettingsGroup(title: "Transcript & Translation", children: [
                      SettingContainer(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Text('Country'),
                                SizedBox(width: 8),
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
                              decoration: const ShapeDecoration(
                                color: Color(0xFF111316),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                ),
                              ),
                              child: Obx(
                                () {
                                  return CountryCodePicker(
                                    countryList: countryList,
                                    padding: const EdgeInsets.all(0),
                                    showFlag: false,
                                    barrierColor: Colors.transparent,
                                    dialogBackgroundColor: Colors.black,
                                    boxDecoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    closeIcon: const Icon(Icons.close,
                                        color: Colors.white),
                                    textStyle: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontFamily:
                                          GoogleFonts.comfortaa().fontFamily,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    dialogTextStyle: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontFamily:
                                          GoogleFonts.comfortaa().fontFamily,
                                      fontWeight: FontWeight.w400,
                                    ),
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
                                  thumbColor:
                                      WidgetStateProperty.all(Colors.grey),
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
                                  SizedBox(width: 8),
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
                                  SizedBox(width: 8),
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
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color(0xFF111316)),
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
                                      backgroundColor: Colors.black,
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
                                SizedBox(width: 8),
                                Tooltip(
                                  triggerMode: TooltipTriggerMode.tap,
                                  showDuration: Duration(milliseconds: 2000),
                                  message:
                                      "Limits the number of episodes in the inbox. Auto deleted if exceeded.",
                                  child: Icon(Icons.info_outline),
                                ),
                              ]),
                              TextButton(
                                style: TextButton.styleFrom(
                                    backgroundColor: const Color(0xFF111316)),
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
                                    backgroundColor: Colors.black,
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
                                SizedBox(width: 8),
                                Tooltip(
                                  triggerMode: TooltipTriggerMode.tap,
                                  showDuration: Duration(milliseconds: 2000),
                                  message:
                                      "Limits the number of episodes in the history. Auto deleted if exceeded.",
                                  child: Icon(Icons.info_outline),
                                ),
                              ]),
                              TextButton(
                                style: TextButton.styleFrom(
                                    backgroundColor: const Color(0xFF111316)),
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
                                    backgroundColor: Colors.black,
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
                            onTap: () => launchUrl(
                              Uri(
                                scheme: 'mailto',
                                path: 'kindjeff.com@gmail.com',
                              ),
                              mode: LaunchMode.inAppBrowserView,
                            ),
                            child: const Text(
                              'kindjeff.com@gmail.com',
                              style: TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Center(
                      child: Column(children: [
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            launchUrl(
                              Uri(
                                  scheme: 'https',
                                  host: 'privacy.anycast.website'),
                              mode: LaunchMode.inAppBrowserView,
                            );
                          },
                          child: Text(
                            'Privacy Policy',
                            style: GoogleFonts.comfortaa(
                              color: Colors.blueAccent,
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            launchUrl(
                              Uri(
                                scheme: 'https',
                                host: 'www.apple.com',
                                path:
                                    '/legal/internet-services/itunes/dev/stdeula/',
                              ),
                              mode: LaunchMode.inAppBrowserView,
                            );
                          },
                          child: Text(
                            'Terms of Use (EULA)',
                            style: GoogleFonts.comfortaa(
                              color: Colors.blueAccent,
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ]),
                    ),
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
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(8),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Color(0xFF232830),
      ),
      child: child,
    );

    if (indent == 0) {
      return c;
    } else {
      return Row(
        children: [
          const Iconify(Ph.arrow_elbow_down_right_bold, color: Colors.white),
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          alignment: Alignment.bottomLeft,
          child: Text(
            title!,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontFamily: GoogleFonts.comfortaa()
                  .copyWith(fontWeight: FontWeight.bold)
                  .fontFamily,
            ),
          ),
        ),
        const Divider(
          color: Colors.white70,
          height: 1,
        ),
        ...c,
      ];
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF232830),
        borderRadius: BorderRadius.circular(12),
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
        barrierColor: Colors.transparent,
        dialogBackgroundColor: Colors.black,
        boxDecoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        closeIcon: const Icon(Icons.close, color: Colors.white),
        textStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontFamily: GoogleFonts.comfortaa().fontFamily,
          fontWeight: FontWeight.w400,
        ),
        dialogTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontFamily: GoogleFonts.comfortaa().fontFamily,
          fontWeight: FontWeight.w400,
        ),
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
          const SizedBox(height: 12),
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
