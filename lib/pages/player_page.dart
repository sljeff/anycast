import 'dart:convert';

import 'package:anycast/api/subtitles.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/pages/channel.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:get/get.dart';
import 'package:marquee/marquee.dart';
import 'package:flutter_lyric/lyrics_reader.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DismissiblePage(
      backgroundColor: Colors.blueGrey,
      direction: DismissiblePageDismissDirection.down,
      onDismissed: () {
        Get.back();
      },
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    Get.back();
                  },
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              ],
            ),
            const SwipeImage(),
            const Titles(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: MyProgressBar(),
            ),
            Controls(),
          ],
        ),
      ),
    );
  }
}

class MyProgressBar extends GetView<PlayerController> {
  MyProgressBar({super.key});

  // myAudioHandler
  final MyAudioHandler myAudioHandler = MyAudioHandler();

  @override
  Widget build(BuildContext context) {
    if (controller.playlistEpisode.value.guid != null &&
        controller.positionData.value.duration == Duration.zero) {
      controller.initProgress();
    }
    return Obx(
      () {
        var duration = controller.positionData.value.duration;
        var position = controller.positionData.value.position;
        var bufferedPosition = controller.positionData.value.bufferedPosition;
        return ProgressBar(
          progress: position,
          buffered: bufferedPosition,
          total: duration,
          onSeek: (duration) {
            controller.seek(duration);
          },
          timeLabelLocation: TimeLabelLocation.above,
          timeLabelType: TimeLabelType.remainingTime,
          timeLabelPadding: 6,
          timeLabelTextStyle: TextStyle(
            color: Colors.white.withOpacity(0.64),
            fontSize: 12,
          ),
          thumbColor: Colors.white,
          thumbGlowColor: Colors.black.withOpacity(0.2),
          thumbCanPaintOutsideBar: false,
          thumbRadius: 16,
          thumbGlowRadius: 20,
          barHeight: 48,
          barCapShape: BarCapShape.round,
          baseBarColor: Colors.white.withOpacity(0.24),
          bufferedBarColor: Colors.white.withOpacity(0.2),
          progressBarColor: Colors.white,
        );
      },
    );
  }
}

class SwipeImage extends GetView<PlayerController> {
  const SwipeImage({super.key});

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    var height = size.height * 0.4;
    controller.pageIndex.value = 2;

    var episode = controller.playlistEpisode.value;
    if (episode.guid == null) {
      return const SizedBox.shrink();
    }

    return DefaultTextStyle(
      style: const TextStyle(fontSize: 16, color: Colors.white),
      child: Column(
        children: [
          SizedBox(
            height: height,
            width: height + 16,
            child: PageView(
              onPageChanged: (value) {
                controller.pageIndex.value = value;
              },
              controller: controller.pageController,
              // descrption / settings / image / subtitle / ai summary
              children: [
                Scrollbar(
                  child: Obx(
                    () => SingleChildScrollView(
                        child: renderHtml(context,
                            controller.playlistEpisode.value.description!)),
                  ),
                ),
                const Settings(),
                Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    child: Obx(() {
                      return Hero(
                        tag: 'play_image',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl:
                                controller.playlistEpisode.value.imageUrl ?? '',
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Icon(
                              Icons.image,
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.image_not_supported,
                            ),
                          ),
                        ),
                      );
                    })),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  child: Subtitles(),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  child: const Center(child: Icon(Icons.abc)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white.withOpacity(0.2),
                ),
                child: const ButtonBar(
                  buttonPadding: EdgeInsets.all(0),
                  children: [
                    PageTabButton(
                      icon: Icons.description,
                      index: 0,
                    ),
                    PageTabButton(
                      icon: Icons.settings,
                      index: 1,
                    ),
                    PageTabButton(
                      icon: Icons.image,
                      index: 2,
                    ),
                    PageTabButton(
                      icon: Icons.subtitles,
                      index: 3,
                    ),
                    PageTabButton(
                      icon: Icons.auto_awesome,
                      index: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class Subtitles extends GetView<SubtitleController> {
  Subtitles({
    super.key,
  });

  final lyricUI = UINetease();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var playerController = Get.find<PlayerController>();
      var url = playerController.playlistEpisode.value.enclosureUrl!;

      var status = controller.subtitleUrls[url];
      if (status == null) {
        // a button to fetch subtitles
        return Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () {
                  getSubtitles(url).then((value) {
                    var subtitle = '';
                    if (value.status == 'succeeded') {
                      subtitle = jsonEncode(value.subtitles);
                    }
                    controller.add(url, value.status!, subtitle);
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue,
                ),
                child: const Text('Generate with AI'),
              ),
              const SizedBox(width: 8),
              const Tooltip(
                  showDuration: Duration(seconds: 10),
                  message:
                      'The AI will generate a summary and subtitles for this episode. '
                      'It may take a few minutes.',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Icon(Icons.info_outline)),
            ],
          ),
        );
      }

      if (status == 'processing') {
        // a progress indicator
        var style = TextStyle(
          color: Colors.white.withOpacity(0.64),
        );
        return Center(
          child: Column(
            children: [
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text("Generating with AI...", style: style),
              const SizedBox(height: 8),
              Text("It may take a few minutes...", style: style),
              const SizedBox(height: 8),
              Text("Feel free to explore or come back later.", style: style),
            ],
          ),
        );
      }

      if (status == 'failed') {
        // a button to retry
        return Center(
          child: TextButton(
            onPressed: () {
              getSubtitles(url).then((value) {
                var subtitle = '';
                if (value.status == 'succeeded') {
                  subtitle = jsonEncode(value.subtitles);
                }
                controller.add(url, value.status!, subtitle);
              });
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.blue,
            ),
            child: const Text('Retry'),
          ),
        );
      }

      var helper = DatabaseHelper();
      return SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: FutureBuilder(
            future: helper.db.then((db) {
              return SubtitleModel.get(db!, url);
            }),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox.shrink();
              }
              var subtitle = snapshot.data!;

              var model = LyricsModelBuilder.create()
                  .bindLyricToMain(
                    subtitle.toLrc(),
                  )
                  .getModel();
              return Obx(
                () => LyricsReader(
                  position: playerController
                      .positionData.value.position.inMilliseconds,
                  model: model,
                  lyricUi: lyricUI,
                  size: Size(
                      double.infinity, MediaQuery.of(context).size.height / 2),
                  playing: playerController.isPlaying.value,
                  emptyBuilder: () => Center(
                    child: Text(
                      'No subtitles',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.64),
                      ),
                    ),
                  ),
                  selectLineBuilder: (progress, confirm) {
                    return Row(
                      children: [
                        IconButton(
                            onPressed: () {
                              confirm.call();
                              playerController
                                  .seek(Duration(milliseconds: progress));
                            },
                            icon: const Icon(Icons.play_arrow, color: Colors.black)),
                        Expanded(
                          child: Container(
                            decoration: const BoxDecoration(color: Colors.black),
                            height: 1,
                            width: double.infinity,
                          ),
                        ),
                        Text(
                          formatTime(Duration(milliseconds: progress)),
                          style: const TextStyle(color: Colors.black),
                        )
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
    });
  }
}

class PageTabButton extends GetView<PlayerController> {
  final IconData icon;
  final int index;

  const PageTabButton({super.key, required this.icon, required this.index});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        var isSelect = controller.pageIndex.value == index;
        return Container(
          decoration: isSelect
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white.withOpacity(0.2),
                )
              : null,
          child: IconButton(
            onPressed: () {
              controller.pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            icon: Icon(icon),
            isSelected: isSelect,
          ),
        );
      },
    );
  }
}

class Controls extends GetView<PlayerController> {
  Controls({super.key});

  final MyAudioHandler myAudioHandler = MyAudioHandler();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: () {
              myAudioHandler.seekByRelative(const Duration(seconds: -10));
            },
            icon: const Icon(
              Icons.replay_10,
              size: 48,
              color: Colors.white,
            ),
          ),
          Container(
            height: 64,
            width: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: IconButton(
              onPressed: () {
                if (controller.isPlaying.value) {
                  controller.pause();
                } else {
                  controller.play();
                }
              },
              icon: const PlayIcon(size: 48),
            ),
          ),
          IconButton(
            onPressed: () {
              myAudioHandler.seekByRelative(const Duration(seconds: 30));
            },
            icon: const Icon(
              Icons.forward_30,
              color: Colors.white,
              size: 48,
            ),
          ),
        ],
      ),
    );
  }
}

class Titles extends GetView<PlayerController> {
  const Titles({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        var episode = controller.playlistEpisode.value;
        if (episode.guid == null) {
          // placeholder
          return const SizedBox(
            height: 70,
          );
        }

        return Container(
          height: 70,
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: Column(
            children: [
              SizedBox(
                height: 50,
                child: Marquee(
                  text: episode.title!,
                  blankSpace: 8,
                  style: const TextStyle(
                    fontSize: 32,
                    decoration: TextDecoration.none,
                    color: Colors.white,
                  ),
                  // no bottom line
                ),
              ),
              GestureDetector(
                onTap: () {
                  var subscriptionController =
                      Get.find<SubscriptionController>();
                  var s =
                      subscriptionController.getByTitle(episode.channelTitle!);
                  if (s == null) {
                    s = SubscriptionModel.empty();
                    s.rssFeedUrl = episode.rssFeedUrl;
                  }
                  Get.lazyPut(() => ChannelController(channel: s!),
                      tag: s.rssFeedUrl);
                  context
                      .pushTransparentRoute(Channel(rssFeedUrl: s.rssFeedUrl!));
                },
                child: SizedBox(
                  height: 20,
                  child: Text(
                    episode.channelTitle!,
                    style: TextStyle(
                      fontSize: 12,
                      decoration: TextDecoration.none,
                      color: Colors.white.withOpacity(0.64),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CustomSliderThumbCircle extends SliderComponentShape {
  final double thumbRadius;

  const CustomSliderThumbCircle({required this.thumbRadius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final paint = Paint()
      ..color = sliderTheme.thumbColor! // Thumb background color
      ..style = PaintingStyle.fill;

    // Draw the thumb circle
    canvas.drawCircle(center, thumbRadius, paint);

    // Text style for the value inside the thumb
    TextStyle textStyle = TextStyle(
      color: sliderTheme.valueIndicatorColor, // Text color
      fontSize: thumbRadius * 0.6,
      fontWeight: FontWeight.bold,
    );

    // Create a TextPainter to paint the value text
    final textSpan = TextSpan(
      style: textStyle,
      text: labelPainter.text!.toPlainText(),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: textDirection,
    );

    // Layout the text painter and calculate the offset for the text's position
    textPainter.layout();
    final textCenter = Offset(
      center.dx - (textPainter.width / 2),
      center.dy - (textPainter.height / 2),
    );

    // Paint the value text inside the thumb
    textPainter.paint(canvas, textCenter);
  }
}

class Settings extends GetView<SettingsController> {
  const Settings({super.key});

  @override
  Widget build(BuildContext context) {
    SliderThemeData sliderThemeData = SliderTheme.of(context).copyWith(
      activeTrackColor: Colors.blue,
      inactiveTrackColor: Colors.blue.withOpacity(0.3),
      trackHeight: 0,
      trackShape: const RoundedRectSliderTrackShape(),
      thumbColor: Colors.white,
      thumbShape: const CustomSliderThumbCircle(thumbRadius: 20),
      overlayColor: Colors.transparent,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
      showValueIndicator: ShowValueIndicator.never,
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 4),
      activeTickMarkColor: Colors.white,
      inactiveTickMarkColor: Colors.orange.withOpacity(0.5),
      valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
      valueIndicatorColor: Colors.orange,
      valueIndicatorTextStyle: const TextStyle(
        color: Colors.white,
      ),
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'Speed',
                style: TextStyle(
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Obx(
              () => Material(
                shape: const StadiumBorder(),
                color: Colors.blue,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SliderTheme(
                    data: sliderThemeData.copyWith(
                      activeTrackColor: Colors.blue,
                      inactiveTrackColor: Colors.blue,
                      inactiveTickMarkColor: Colors.white,
                    ),
                    child: Slider(
                      value: controller.speed.value,
                      onChanged: (value) {
                        controller.setSpeed(value);
                      },
                      min: 0.5,
                      max: 2.0,
                      divisions: 6,
                      label: controller.speed.value.toStringAsFixed(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
        Column(children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'Countdown',
                style: TextStyle(
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Obx(
              () => Material(
                color: Colors.blue,
                shape: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SliderTheme(
                    data: sliderThemeData,
                    child: Slider(
                      value: controller.countdownDuration.value.inMinutes
                          .toDouble(),
                      onChanged: (value) {
                        controller.onChangeCountdown(
                            Duration(minutes: value.toInt()));
                      },
                      onChangeEnd: (value) {
                        if (value == 0) {
                          controller.stop();
                        } else {
                          controller.start(Duration(minutes: value.toInt()));
                        }
                      },
                      min: 0,
                      max: 60,
                      divisions: 6,
                      label:
                          formatCountdown(controller.countdownDuration.value),
                    ),
                  ),
                ),
              ),
            ),
          )
        ]),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Skip Silence',
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: 80,
                      height: 64,
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: Obx(
                          () => Switch(
                            activeColor: Colors.blue,
                            inactiveThumbColor: Colors.blue,
                            inactiveTrackColor: Colors.white.withOpacity(0.7),
                            trackOutlineColor: WidgetStateColor.resolveWith(
                                (states) => Colors.blue.withOpacity(0.3)),
                            value: controller.skipSilence.value,
                            onChanged: (value) {
                              controller.setSkipSilence(value);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Column(mainAxisAlignment: MainAxisAlignment.start, children: [
                const Row(
                  children: [
                    Text(
                      'Auto sleep timer',
                      style: TextStyle(
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(width: 8),
                    Tooltip(
                      showDuration: Duration(seconds: 10),
                      message:
                          'A countdown will be enabled when a podcast starts '
                          'within the time range you set.',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Icon(Icons.info_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  width: 80,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black,
                    ),
                    onPressed: () {
                      Get.bottomSheet(
                        const AutoSleepPicker(),
                        backgroundColor: Colors.blueGrey,
                      );
                    },
                    child: Obx(
                      () {
                        var off =
                            controller.autoSleepCountdownMinIndex.value == 0 ||
                                controller.autoSleepStartHourIndex.value ==
                                    controller.autoSleepEndHourIndex.value;
                        return Text(
                          off
                              ? 'OFF'
                              : controller.sleepMinsText[
                                  controller.autoSleepCountdownMinIndex.value],
                          style: const TextStyle(
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                  ),
                )
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class AutoSleepPicker extends GetView<SettingsController> {
  const AutoSleepPicker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Obx(
            () {
              const style = TextStyle(
                fontSize: 18,
                color: Colors.amber,
              );
              var startHour =
                  controller.hours[controller.autoSleepStartHourIndex.value];
              var endHour =
                  controller.hours[controller.autoSleepEndHourIndex.value];
              if (controller.autoSleepCountdownMinIndex.value == 0 ||
                  startHour == endHour) {
                return const Text(
                  'OFF',
                  style: style,
                );
              }
              var endHourStr = '$endHour:00';
              if (startHour >= endHour) {
                endHourStr = '$endHour:00 (next day)';
              }

              if (controller.autoSleepCountdownMinIndex.value == 0) {
                return const SizedBox.shrink();
              }
              var countdownMin = controller
                  .sleepMinsText[controller.autoSleepCountdownMinIndex.value];
              return Column(children: [
                Text(
                  '$startHour:00 - $endHourStr',
                  style: style,
                ),
                Text(
                  '$countdownMin countdown',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.amber,
                  ),
                ),
              ]);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                height: 40,
                width: 64,
                child: Obx(
                  () => CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                        initialItem: controller.autoSleepStartHourIndex.value),
                    itemExtent: 24,
                    onSelectedItemChanged: (index) {
                      controller.setAutoSleepStartHourIndex(index);
                    },
                    children: controller.hours.map((e) {
                      return Text(
                        '$e:00',
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                width: 64,
                child: Obx(
                  () => CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                        initialItem: controller.autoSleepEndHourIndex.value),
                    itemExtent: 24,
                    onSelectedItemChanged: (index) {
                      controller.setAutoSleepEndHourIndex(index);
                    },
                    children: controller.hours.map((e) {
                      return Text(
                        '$e:00',
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                width: 70,
                child: Obx(
                  () => CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                        initialItem:
                            controller.autoSleepCountdownMinIndex.value),
                    itemExtent: 24,
                    onSelectedItemChanged: (index) {
                      controller.setAutoSleepCountdownMinIndex(index);
                    },
                    children: controller.sleepMinsText.map((e) {
                      return Text(
                        e,
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 24, left: 24, right: 24),
            child: Text(
              'If you changed this setting, you need to play or replay '
              'the podcast to take effect.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
