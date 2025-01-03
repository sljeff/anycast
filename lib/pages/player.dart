import 'dart:async';
import 'dart:io';

import 'package:anycast/api/share.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/models/translation.dart';
import 'package:anycast/pages/chat.dart';
import 'package:anycast/states/channel.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:anycast/states/translation.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/pages/channel.dart';
import 'package:anycast/widgets/animation.dart';
import 'package:anycast/widgets/card.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/play_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter_lyric/lyrics_reader_model.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:lottie/lottie.dart';
import 'package:marquee/marquee.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const aiChat =
    '<svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24"><g fill="none" stroke="white" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" color="white"><path d="M14.17 20.89c4.184-.277 7.516-3.657 7.79-7.9c.053-.83.053-1.69 0-2.52c-.274-4.242-3.606-7.62-7.79-7.899a33 33 0 0 0-4.34 0c-4.184.278-7.516 3.657-7.79 7.9a20 20 0 0 0 0 2.52c.1 1.545.783 2.976 1.588 4.184c.467.845.159 1.9-.328 2.823c-.35.665-.526.997-.385 1.237c.14.24.455.248 1.084.263c1.245.03 2.084-.322 2.75-.813c.377-.279.566-.418.696-.434s.387.09.899.3c.46.19.995.307 1.485.34c1.425.094 2.914.094 4.342 0"/><path d="m7.5 15l1.842-5.526a.694.694 0 0 1 1.316 0L12.5 15m3-6v6m-7-2h3"/></g></svg>';

class PlayerPage extends GetView<PlayerController> {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          controller.pageIndex.value = 1;
        }
      },
      child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                controller.backgroundColor.value,
                const Color(0xFF111316),
                const Color(0xFF111316),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Handler(),
                Expanded(
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
          )),
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
          PageTabButton(icon: Ic.round_settings, index: 0),
          PageTabButton(icon: Ic.round_podcasts, index: 1),
          PageTabButton(icon: tablerTopology, index: 2),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(children: [
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Obx(
                  () => renderHtml(context,
                      controller.playlistEpisode.value.description ?? ""),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Settings(),
        ]),
      ),
    );
  }
}

class PlayerMain extends GetView<PlayerController> {
  const PlayerMain({super.key});

  @override
  Widget build(BuildContext context) {
    var size = Get.width - 48;
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.white),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Stack(
              children: [
                Obx(() {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      width: size,
                      height: size,
                      imageUrl: controller.playlistEpisode.value.imageUrl ??
                          'https://placehold.co/400/000000/FFF.png?text=No+Episode',
                    ),
                  );
                }),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () async {
                      var episode = controller.playlistEpisode.value;
                      var shareUrl = Uri(
                        scheme: 'https',
                        host: 'share.anycast.website',
                        path: 'player',
                        queryParameters: {
                          'rssfeedurl': episode.rssFeedUrl,
                          'enclosureurl': episode.enclosureUrl,
                        },
                      );

                      Get.dialog(const Center(
                        child: CircularProgressIndicator(
                          strokeCap: StrokeCap.round,
                        ),
                      ));
                      await getShortUrl(shareUrl).then((value) {
                        var finalUrl = shareUrl.toString();
                        if (value != null) {
                          finalUrl = value;
                        }
                        Share.share('${episode.title}\n\n$finalUrl');
                      });

                      Get.back();
                    },
                    child: Container(
                      alignment: Alignment.center,
                      width: 36,
                      height: 36,
                      padding: const EdgeInsets.all(8),
                      clipBehavior: Clip.antiAlias,
                      decoration: ShapeDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Iconify(
                        Ic.round_ios_share,
                        size: 18,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const TitleBar(),
            const MyProgressBar(),
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
    return DefaultTextStyle(
      style: const TextStyle(
        color: Colors.white,
        decoration: TextDecoration.none,
      ),
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            side: const BorderSide(width: 1, color: Color(0xFF232830)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          var height = constraints.maxHeight;
          return Column(
            children: [
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Row(children: [
                  Obx(
                    () => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: controller.channel.value.imageUrl ??
                            'https://placehold.co/400/000000/FFF.png?text=NoChannel',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Obx(
                    () => Expanded(
                      child: Text(controller.playlistEpisode.value.title ?? "",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.comfortaa(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          )),
                    ),
                  ),
                ]),
              ),
              Divider(height: 1, color: Colors.grey[800]),
              Subtitles(height: height - 62),
            ],
          );
        }),
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
      var episode = controller.playlistEpisode.value;
      var backgroundColor = controller.backgroundColor.value;
      var subscription = controller.channel.value;
      var imgUrl = subscription.imageUrl ?? '';
      var title = controller.playlistEpisode.value.title ?? '';
      var channelTitle = subscription.title ?? '';

      Widget img = const Icon(
        Icons.image,
        size: 64,
      );
      if (imgUrl != '') {
        img = GestureDetector(
          onTap: () {
            jumpToChannel(episode, context, subscription);
          },
          child: CachedNetworkImage(
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
          ),
        );
      }

      // marquee or text
      var titleStyle = const TextStyle(
        fontSize: 24,
        color: Colors.white,
        fontFamily: 'PingFang SC',
        fontWeight: FontWeight.w600,
      );
      Widget titleWidget = Text(
        title,
        style: titleStyle,
      );
      // if text width > rightWidth, use marquee
      if (title.length * 24 > rightWidth) {
        titleWidget = Marquee(
          text: title,
          pauseAfterRound: const Duration(seconds: 1),
          style: titleStyle,
          blankSpace: 40,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                height: 34,
                child: titleWidget,
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {
                  jumpToChannel(episode, context, subscription);
                },
                child: SizedBox(
                  height: 24,
                  child: Text(
                    channelTitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: getTextSafeColor(backgroundColor),
                      fontFamily: 'PingFang SC',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ]);
    });
  }
}

void jumpToChannel(PlaylistEpisodeModel episode, BuildContext context,
    SubscriptionModel channel) {
  Get.lazyPut(() => ChannelController(channel: channel),
      tag: channel.rssFeedUrl);
  showMaterialModalBottomSheet(
    context: context,
    builder: (context) => Channel(rssFeedUrl: channel.rssFeedUrl!),
    expand: true,
    closeProgressThreshold: 0.9,
  );
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
        if (controller.playlistEpisode.value.enclosureUrl != null &&
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
          timeLabelPadding: 4,
          timeLabelTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontFamily: GoogleFonts.comfortaa().fontFamily,
            fontWeight: FontWeight.w700,
          ),
          thumbColor: Colors.white,
          thumbGlowColor: Colors.black.withOpacity(0.2),
          thumbCanPaintOutsideBar: false,
          thumbRadius: 16,
          thumbGlowRadius: 20,
          barHeight: 40,
          barCapShape: BarCapShape.round,
          baseBarColor: const Color(0xFF232830),
          bufferedBarColor: Colors.white.withOpacity(0.05),
          progressBarColor: Colors.white,
        );
      },
    );
  }
}

class Subtitles extends GetView<SubtitleController> {
  final double height;

  const Subtitles({
    super.key,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var playerController = Get.find<PlayerController>();
      if (playerController.playlistEpisode.value.enclosureUrl == null) {
        return const SizedBox();
      }
      var url = playerController.playlistEpisode.value.enclosureUrl!;

      var status = controller.subtitleUrls[url];
      if (status == null) {
        // a button to fetch subtitles
        return Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Generate transcript with AI (Beta)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: GoogleFonts.comfortaa().fontFamily,
                        fontWeight: FontWeight.w400,
                        height: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const ShapeDecoration(
                        color: Color(0xFF059669),
                        shape: OvalBorder(),
                      ),
                      child: const Tooltip(
                        showDuration: Duration(seconds: 10),
                        message: 'AI transcript may take about 2 ~ 5 minutes',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Icon(
                          Icons.question_mark_rounded,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                TextButton(
                  onPressed: () {
                    controller.add(url);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Iconify(newDoc),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      }

      if (status == 'processing') {
        // a progress indicator
        var style = TextStyle(
          color: Colors.white,
          fontFamily: GoogleFonts.comfortaa().fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        );
        return Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Lottie.asset('assets/lottie/robot_loading.json'),
                const SizedBox(height: 24),
                Text("Generating with AI ...", style: style),
                const SizedBox(height: 8),
                Text("It may take 2 ~ 5 minutes ...", style: style),
                const SizedBox(height: 24),
                Text(
                  "Feel free to explore or come back later.",
                  style: GoogleFonts.comfortaa().copyWith(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      if (status == 'failed') {
        // a button to retry
        return Center(
          child: TextButton(
            onPressed: () {
              controller.add(url);
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
          future: helper.db.then((db) async {
            var subtitle = await SubtitleModel.get(db, url);
            if (subtitle.subtitle == null ||
                subtitle.subtitle!.trim().isEmpty ||
                subtitle.subtitle == 'null') {
              SubtitleModel.delete(db, url);
              controller.subtitleUrls[url] = 'processing';
              return null;
            }
            return subtitle;
          }),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox.shrink();
            }
            var subtitle = snapshot.data!;

            var model = LyricsModelBuilder.create()
                .bindLyricToMain(subtitle.toLrc())
                .getModel();
            return Obx(
              () {
                var translationStatus =
                    Get.find<TranslationController>().translationUrls[url];
                if (translationStatus == 'succeeded') {
                  var language =
                      Get.find<SettingsController>().targetLanguage.value;
                  return FutureBuilder(future: helper.db.then((db) {
                    return TranslationModel.get(db, url, language);
                  }), builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    var translation = snapshot.data!;
                    model = LyricsModelBuilder.create()
                        .bindLyricToMain(subtitle.toLrc())
                        .bindLyricToExt(translation.toLrc())
                        .getModel();
                    return LyricsWithShare(model: model, height: height);
                  });
                } else if (translationStatus == 'processing') {
                  return Column(
                    children: [
                      LyricsWithShare(model: model, height: height - 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const RefreshProgressIndicator(),
                          Text(
                            "Translating subtitles...",
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: GoogleFonts.comfortaa().fontFamily,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                } else {
                  return LyricsWithShare(model: model, height: height);
                }
              },
            );
          },
        ),
      );
    });
  }
}

class LyricsWithShare extends GetView<PlayerController> {
  const LyricsWithShare({
    super.key,
    required this.model,
    required this.height,
  });

  final LyricsReaderModel model;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Lyrics(
          model: model,
          height: height,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.only(right: 0),
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: GestureDetector(
                  child: const Iconify(aiChat, color: Colors.green, size: 24),
                  onTap: () {
                    showMaterialModalBottomSheet(
                      context: context,
                      builder: (context) =>
                          Chat(episode: controller.playlistEpisode.value),
                      expand: true,
                      closeProgressThreshold: 0.9,
                    );
                  },
                ),
              ),
              PopupMenuButton(
                color: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                itemBuilder: (context) => [
                  PopupMenuItem(
                      height: 20,
                      value: 'export',
                      child: Row(children: [
                        const Iconify(
                          Ic.baseline_offline_share,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text("Export subtitles",
                            style: GoogleFonts.comfortaa()
                                .copyWith(color: Colors.white)),
                      ])),
                ],
                onSelected: (value) {
                  exportSubtitles(model);
                },
                child: const Icon(Icons.more_vert_rounded, color: Colors.grey),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// lrc format
Future<void> exportSubtitles(LyricsReaderModel model) async {
  var playerController = Get.find<PlayerController>();
  var title = playerController.playlistEpisode.value.title ?? 'Subtitle';
  var channelTitle = playerController.playlistEpisode.value.channelTitle ?? '';
  var subject = '$title - $channelTitle';
  if (channelTitle.isEmpty) {
    subject = title;
  }

  var buffer = StringBuffer('# $subject\n\n---\n\n');
  for (var t in model.lyrics) {
    if (t.mainText == null || t.mainText!.isEmpty) {
      continue;
    }
    var startTime = (t.startTime ?? 0) / 1000.0;
    var s = formatLrcTime(startTime);

    buffer.writeln('[$s]${t.mainText}');
    if (t.extText?.isNotEmpty == true) {
      buffer.writeln('[$s]${t.extText}');
    }
    buffer.writeln('\n');
  }

  var tempFile = await getTemporaryDirectory();
  var file = File('${tempFile.path}/$subject.txt');

  await file.writeAsString(buffer.toString());

  Share.shareXFiles([
    XFile(file.path, name: subject),
  ], subject: subject);

  // await Share.share(buffer.toString(), subject: subject);
}

class Lyrics extends GetView<PlayerController> {
  const Lyrics({
    super.key,
    required this.model,
    required this.height,
  });

  final LyricsReaderModel model;
  final double height;
  static final lyricUI = MyUINetease(highlight: false);

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => LyricsReader(
        onTap: () {
          controller.togglePlay();

          var overlayEntry = OverlayEntry(
            builder: (context) => Center(
              child: PlayPauseAnimation(isPlaying: !controller.isPlaying.value),
            ),
          );
          Overlay.of(context).insert(overlayEntry);
          Future.delayed(const Duration(milliseconds: 500), () {
            overlayEntry.remove();
          });
        },
        position: controller.positionData.value.position.inMilliseconds,
        model: model,
        lyricUi: lyricUI,
        size: Size(double.infinity, height),
        playing: controller.isPlaying.value,
        emptyBuilder: () => Center(
          child: Text(
            'No Transcript',
            style: TextStyle(
              color: Colors.white.withOpacity(0.64),
            ),
          ),
        ),
        selectLineBuilder: (progress, confirm) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                formatTime(Duration(milliseconds: progress)),
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: GoogleFonts.comfortaa().fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  shadows: const [
                    Shadow(
                      color: Colors.black,
                      offset: Offset(1, 1),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white),
                  height: 2,
                  width: double.infinity,
                ),
              ),
              IconButton(
                  onPressed: () {
                    confirm.call();
                    controller.seek(Duration(milliseconds: progress));
                  },
                  tooltip: 'Seek',
                  iconSize: 24,
                  style: ButtonStyle(
                    shape: const WidgetStatePropertyAll(
                      CircleBorder(),
                    ),
                    backgroundColor: WidgetStatePropertyAll(
                      Colors.white.withOpacity(0.8),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded,
                      color: Color(0xFF10B981)))
            ],
          );
        },
      ),
    );
  }
}

class PageTabButton extends GetView<PlayerController> {
  final String icon;
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
          padding: const EdgeInsets.all(12),
          child: GestureDetector(
            child: Iconify(
              icon,
              color: isSelect ? Colors.black : Colors.white,
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
    return Row(
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
          height: 72,
          width: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF10B981),
          ),
          child: IconButton(
            onPressed: () {
              if (controller.isPlaying.value) {
                controller.pause();
              } else {
                controller.play();
              }
            },
            icon: const PlayIcon(
              size: 48,
              color: Colors.white,
            ),
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
      activeTrackColor: const Color(0xFF6B7280),
      inactiveTrackColor: const Color(0xFF6B7280).withOpacity(0.3),
      trackHeight: 0,
      trackShape: const RoundedRectSliderTrackShape(),
      thumbColor: Colors.white,
      thumbShape: const CustomSliderThumbCircle(thumbRadius: 20),
      overlayColor: Colors.transparent,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
      showValueIndicator: ShowValueIndicator.never,
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 4),
      activeTickMarkColor: Colors.white,
      inactiveTickMarkColor: const Color(0xFF232830),
      valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
      valueIndicatorColor: const Color(0xFF111316),
      valueIndicatorTextStyle: TextStyle(
        color: const Color(0xFF111316),
        fontSize: 14,
        fontFamily: GoogleFonts.comfortaa().fontFamily,
        fontWeight: FontWeight.w400,
      ),
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'SPEED',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: GoogleFonts.comfortaa().fontFamily,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Obx(
              () => Material(
                shape: const StadiumBorder(),
                color: const Color(0xFF232830),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SliderTheme(
                    data: sliderThemeData.copyWith(
                      activeTrackColor: Colors.grey,
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
        const SizedBox(height: 16),
        Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'COUNTDOWN',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: GoogleFonts.comfortaa().fontFamily,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Obx(
              () => Material(
                color: const Color(0xFF232830),
                shape: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SliderTheme(
                    data: sliderThemeData,
                    child: Slider(
                      value: controller.countdownValue,
                      onChanged: (value) {
                        controller
                            .setCountdown(Duration(minutes: value.toInt()));
                      },
                      onChangeEnd: (value) {
                        if (value == 0) {
                          controller.stopCountdown();
                        } else {
                          controller
                              .setCountdown(Duration(minutes: value.toInt()));
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
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SKIP SILENCE',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: GoogleFonts.comfortaa().fontFamily,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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
                          activeColor: Colors.white,
                          inactiveThumbColor: Colors.grey,
                          inactiveTrackColor:
                              const Color(0xFF232830).withOpacity(0.7),
                          trackOutlineColor: WidgetStateColor.resolveWith(
                              (states) =>
                                  const Color(0xFF232830).withOpacity(0.3)),
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
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONTINUOUS PLAY',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: GoogleFonts.comfortaa().fontFamily,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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
                          activeColor: Colors.white,
                          inactiveThumbColor: Colors.grey,
                          inactiveTrackColor:
                              const Color(0xFF232830).withOpacity(0.7),
                          trackOutlineColor: WidgetStateColor.resolveWith(
                              (states) =>
                                  const Color(0xFF232830).withOpacity(0.3)),
                          value: controller.continuousPlaying.value,
                          onChanged: (value) {
                            controller.setContinuousPlaying(value);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Tooltip(
              message: 'Auto play next episode after the current one ends.',
              showDuration: Duration(milliseconds: 2000),
              triggerMode: TooltipTriggerMode.tap,
              child: Icon(Icons.info, color: Colors.grey),
            ),
          ],
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

class MyUINetease extends LyricUI {
  double defaultSize;
  double defaultExtSize;
  double otherMainSize;
  double bias;
  double lineGap;
  double inlineGap;
  LyricAlign lyricAlign;
  LyricBaseLine lyricBaseLine;
  bool highlight;
  HighlightDirection highlightDirection;

  MyUINetease(
      {this.defaultSize = 16,
      this.defaultExtSize = 14,
      this.otherMainSize = 14,
      this.bias = 0.5,
      this.lineGap = 25,
      this.inlineGap = 15,
      this.lyricAlign = LyricAlign.LEFT,
      this.lyricBaseLine = LyricBaseLine.CENTER,
      this.highlight = true,
      this.highlightDirection = HighlightDirection.LTR});

  MyUINetease.clone(MyUINetease uiNetease)
      : this(
          defaultSize: uiNetease.defaultSize,
          defaultExtSize: uiNetease.defaultExtSize,
          otherMainSize: uiNetease.otherMainSize,
          bias: uiNetease.bias,
          lineGap: uiNetease.lineGap,
          inlineGap: uiNetease.inlineGap,
          lyricAlign: uiNetease.lyricAlign,
          lyricBaseLine: uiNetease.lyricBaseLine,
          highlight: uiNetease.highlight,
          highlightDirection: uiNetease.highlightDirection,
        );

  @override
  TextStyle getPlayingExtTextStyle() => GoogleFonts.mPlusRounded1c()
      .copyWith(color: Colors.greenAccent, fontSize: defaultExtSize);

  @override
  TextStyle getOtherExtTextStyle() => GoogleFonts.mPlusRounded1c()
      .copyWith(color: Colors.grey[300], fontSize: defaultExtSize);

  @override
  TextStyle getOtherMainTextStyle() => GoogleFonts.mPlusRounded1c()
      .copyWith(color: Colors.grey[200], fontSize: otherMainSize);

  @override
  TextStyle getPlayingMainTextStyle() => GoogleFonts.mPlusRounded1c().copyWith(
        color: Colors.greenAccent,
        fontSize: defaultSize,
        fontWeight: FontWeight.w200,
      );

  @override
  double getInlineSpace() => inlineGap;

  @override
  double getLineSpace() => lineGap;

  @override
  double getPlayingLineBias() => bias;

  @override
  LyricAlign getLyricHorizontalAlign() => lyricAlign;

  @override
  LyricBaseLine getBiasBaseLine() => lyricBaseLine;

  @override
  bool enableHighlight() => highlight;

  @override
  HighlightDirection getHighlightDirection() => highlightDirection;
}
