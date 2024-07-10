import 'package:anycast/states/player.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:country_code_picker/country_code_picker.dart';

class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DismissiblePage(
      backgroundColor: const Color(0xFF111316),
      isFullScreen: false,
      direction: DismissiblePageDismissDirection.down,
      onDismissed: () {
        Get.back();
      },
      child: DefaultTextStyle(
        style: TextStyle(
          color: Colors.white,
          decoration: TextDecoration.none,
          fontFamily: GoogleFonts.comfortaa().fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 14,
          height: 1.5,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Handler(),
                ],
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  Get.snackbar('没做', '没做完');
                },
                child: const SettingContainer(
                  child: Text('Profile'),
                ),
              ),
              SettingContainer(
                  child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Row(
                    children: [
                      Text('Max Cached Episodes'),
                      SizedBox(width: 8),
                      Tooltip(
                        triggerMode: TooltipTriggerMode.tap,
                        showDuration: Duration(milliseconds: 3000),
                        message:
                            "Limits the number of episodes stored for offline playback.\nOnly audio that has not been used for more than one day will be deleted.",
                        child: Icon(Icons.info_outline),
                      ),
                    ],
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF111316)),
                    child: Obx(
                        () => Text(controller.maxCacheCount.value.toString())),
                    onPressed: () {
                      Get.bottomSheet(
                        SettingsBottomContainer(
                            picker: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: controller.maxCacheCount.value - 3,
                          ),
                          itemExtent: 36,
                          onSelectedItemChanged: (index) {
                            controller.setMaxCacheCount(index + 3);
                          },
                          children: List<Widget>.generate(
                            99 - 3 + 1,
                            (index) => Center(
                              child: Text(
                                (index + 3).toString(),
                              ),
                            ),
                          ),
                        )),
                        backgroundColor: Colors.black,
                      );
                    },
                  ),
                ],
              )),
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
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      child: Obx(
                        () {
                          return CountryCodePicker(
                            showFlag: false,
                            barrierColor: Colors.transparent,
                            dialogBackgroundColor: Colors.black,
                            boxDecoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            closeIcon:
                                const Icon(Icons.close, color: Colors.white),
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
                              controller.setCountryCode(value.code!);
                            },
                            initialSelection: controller.countryCode.value,
                            favorite: const [
                              'US',
                              'CN',
                              'FR',
                              'DE',
                              'IN',
                              'BR',
                              'RU',
                              'GB'
                            ],
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
              const SettingContainer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Text('Translated Transcript'),
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
              ),
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
                          var interval = controller.autoRefreshInterval.value;
                          var initialIndex = minutes.indexOf(interval ~/ 60);

                          Get.bottomSheet(
                            SettingsBottomContainer(
                                picker: CupertinoPicker(
                              scrollController: FixedExtentScrollController(
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
                      child: Obx(() =>
                          Text(controller.maxFeedEpisodes.value.toString())),
                      onPressed: () {
                        Get.bottomSheet(
                          SettingsBottomContainer(
                              picker: CupertinoPicker(
                            scrollController: FixedExtentScrollController(
                              initialItem:
                                  controller.maxFeedEpisodes.value ~/ 100,
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
                      child: Obx(() =>
                          Text(controller.maxHistoryEpisodes.value.toString())),
                      onPressed: () {
                        Get.bottomSheet(
                          SettingsBottomContainer(
                              picker: CupertinoPicker(
                            scrollController: FixedExtentScrollController(
                              initialItem:
                                  controller.maxHistoryEpisodes.value ~/ 100,
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
        ),
      ),
    );
  }
}

class ProfilePage extends GetView<SettingsController> {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}

class PlanPage extends GetView<SettingsController> {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}

class SettingContainer extends StatelessWidget {
  final Widget child;

  const SettingContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 64,
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF232830),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
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
        countryList: const [
          {'name': 'English', 'code': 'en'},
          {'name': '中文', 'code': 'zh'},
          {'name': 'Portugues', 'code': 'pt'},
          {'name': '日本語', 'code': 'ja'},
          {'name': '한국어', 'code': 'ko'},
          {'name': 'Italian', 'code': 'it'},
          {'name': 'हिन्दी', 'code': 'hi'},
          {'name': 'Deutsch', 'code': 'de'},
          {'name': 'Español', 'code': 'es'},
          {'name': 'Français', 'code': 'fr'},
          {'name': 'Pусский', 'code': 'ru'},
        ],
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
