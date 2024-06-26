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
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:get/get.dart';
import 'package:marquee/marquee.dart';
import 'package:flutter_lyric/lyrics_reader.dart';

class PlayerPage extends GetView<PlayerController> {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    controller.pageIndex.value = 1;
    return DismissiblePage(
      backgroundColor: const Color(0xFF111316),
      direction: DismissiblePageDismissDirection.down,
      onDismissed: () {
        Get.back();
      },
      child: Stack(
        children: [
          Container(
            height: MediaQuery.of(context).size.height / 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  controller.backgroundColor.value,
                  const Color(0xFF111316),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: MediaQuery.of(context).size.height / 2,
              color: const Color(0xFF111316),
            ),
          ),
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Handler(),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.8,
                  child: PageView(
                    controller: controller.pageController,
                    children: const [
                      PlayerSettings(),
                      PlayerMain(),
                      PlayerAI(),
                    ],
                    onPageChanged: (index) {
                      controller.pageIndex.value = index;
                    },
                  ),
                ),
                const PageTab(),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class PageTab extends GetView<PlayerController> {
  const PageTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: const Color(0x19232830),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B5563)),
          borderRadius: BorderRadius.circular(36),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageTabButton(icon: Icons.settings, index: 0),
          PageTabButton(icon: Icons.photo, index: 1),
          PageTabButton(icon: Icons.air, index: 2),
        ],
      ),
    );
  }
}

class PlayerSettings extends GetView<PlayerController> {
  const PlayerSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.white),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(top: 16, bottom: 16),
              height: 200,
              child: Scrollbar(
                child: Obx(
                  () => SingleChildScrollView(
                      child: renderHtml(context,
                          controller.playlistEpisode.value.description!)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 280, child: Settings()),
        ]),
      ),
    );
  }
}

class PlayerMain extends GetView<PlayerController> {
  const PlayerMain({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.white),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Obx(() {
              return Hero(
                tag: 'play_image',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: controller.playlistEpisode.value.imageUrl ?? '',
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Icon(
                      Icons.image,
                      size: 328,
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.image_not_supported,
                      size: 328,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            const TitleBar(),
            const SizedBox(height: 16),
            const MyProgressBar(),
            const SizedBox(height: 16),
            const Controls(),
          ],
        ),
      ),
    );
  }
}

class PlayerAI extends GetView<PlayerController> {
  const PlayerAI({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTextStyle(
      style: TextStyle(color: Colors.white),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Subtitles(),
      ),
    );
  }
}

class TitleBar extends GetView<PlayerController> {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    var rightWidth = MediaQuery.of(context).size.width - 24 * 2 - 64 - 6;
    return Obx(() {
      var rssFeedUrl = '';
      if (controller.playlistEpisode.value.guid != null) {
        rssFeedUrl = controller.playlistEpisode.value.rssFeedUrl!;
      }
      var f = DatabaseHelper().db.then((db) async {
        if (rssFeedUrl == '') {
          return null;
        }
        return await SubscriptionModel.getOrFetch(db!, rssFeedUrl);
      });
      return FutureBuilder(
        future: f,
        builder: (context, snapshot) {
          var imgUrl = '';
          var title = 'Waiting...';
          var channelTitle = 'Waiting...';
          var backgroundColor = controller.backgroundColor.value;
          if (snapshot.hasData && snapshot.data != null) {
            var subscription = snapshot.data as SubscriptionModel;
            imgUrl = subscription.imageUrl!;
            title = controller.playlistEpisode.value.title!;
            channelTitle = subscription.title!;
          }

          Widget img = const Icon(
            Icons.image,
            size: 64,
          );
          if (imgUrl != '') {
            img = CachedNetworkImage(
              imageUrl: imgUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => const Icon(
                Icons.image,
              ),
              errorWidget: (context, url, error) => const Icon(
                Icons.image_not_supported,
              ),
              height: 64,
              width: 64,
            );
          }

          return Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: img,
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: rightWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 32,
                    child: Marquee(
                      text: title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      blankSpace: 8,
                    ),
                  ),
                  Text(
                    channelTitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: backgroundColor,
                    ),
                  ),
                ],
              ),
            ),
          ]);
        },
      );
    });
  }
}

class MyProgressBar extends GetView<PlayerController> {
  const MyProgressBar({super.key});

  // myAudioHandler
  static final MyAudioHandler myAudioHandler = MyAudioHandler();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        var duration = controller.positionData.value.duration;
        var position = controller.positionData.value.position;
        var bufferedPosition = controller.positionData.value.bufferedPosition;
        if (controller.playlistEpisode.value.guid != null &&
            controller.positionData.value.duration == Duration.zero) {
          controller.initProgress();
        }
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

class Subtitles extends GetView<SubtitleController> {
  const Subtitles({
    super.key,
  });

  static final lyricUI = UINetease();

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
      return SingleChildScrollView(
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
                position:
                    playerController.positionData.value.position.inMilliseconds,
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
                          icon: const Icon(Icons.play_arrow,
                              color: Colors.black)),
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
        var dec = isSelect
            ? ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(36),
                ),
              )
            : ShapeDecoration(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(36),
                ),
              );

        return Container(
          width: 48,
          height: 48,
          decoration: dec,
          child: GestureDetector(
            child: Container(
              width: 24,
              height: 24,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(),
              child: Icon(
                icon,
                color: isSelect ? Colors.black : Colors.white,
              ),
            ),
            onTap: () {
              controller.pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        );
      },
    );
  }
}

class Controls extends GetView<PlayerController> {
  const Controls({super.key});

  static final MyAudioHandler myAudioHandler = MyAudioHandler();

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
