import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:anycast/api/share.dart';
import 'package:anycast/design_system/anycast_theme.dart';
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
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:lottie/lottie.dart';
import 'package:marquee/marquee.dart';
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
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          controller.pageIndex.value = 1;
        }
      },
      child: Theme(
        data: AnycastTheme.dark,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Obx(
              () => _PlayerBackground(
                imageUrl: controller.playlistEpisode.value.imageUrl,
              ),
            ),
            SafeArea(
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
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerBackground extends StatelessWidget {
  const _PlayerBackground({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    const stops = [0.0, .25, .5, .745, 1.0];
    if (imageUrl == null || imageUrl!.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AnycastColor.playerGradientColors,
            stops: stops,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: Transform.scale(
            scale: 1.15,
            child: CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  const ColoredBox(color: AnycastColor.playerWarm),
              errorWidget: (context, url, error) =>
                  const ColoredBox(color: AnycastColor.playerWarm),
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: .50)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: AnycastColor.playerGradientOverlayColors,
              stops: stops,
            ),
          ),
        ),
      ],
    );
  }
}

class PageTab extends GetView<PlayerController> {
  const PageTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(AnycastSpacing.xs),
      decoration: ShapeDecoration(
        color: AnycastColor.sandAlpha3(Brightness.dark),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            width: 1,
            color: AnycastColor.sandAlpha4(Brightness.dark),
          ),
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
      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
            color: AnycastColor.playerText,
          ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AnycastSpacing.pageHeader,
          vertical: AnycastSpacing.pageH,
        ),
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
          const SizedBox(height: AnycastSpacing.pageH),
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
    var size = Get.width - AnycastSpacing.pageHeader * 2;
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
            color: AnycastColor.playerText,
          ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AnycastSpacing.pageHeader,
        ),
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
                        host: 'anycast.website',
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
                        SharePlus.instance.share(
                          ShareParams(text: '${episode.title}\n\n$finalUrl'),
                        );
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
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Iconify(
                        Ic.round_ios_share,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.5),
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
      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
            color: AnycastColor.playerText,
            decoration: TextDecoration.none,
          ),
      child: Container(
        margin: const EdgeInsets.all(AnycastSpacing.pageHeader),
        padding: const EdgeInsets.symmetric(
          horizontal: AnycastSpacing.gap,
        ),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            side: const BorderSide(
              width: 1,
              color: AnycastColor.sandDark4,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          var height = constraints.maxHeight;
          return Column(
            children: [
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(
                  vertical: AnycastSpacing.gap,
                ),
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
                  const SizedBox(width: AnycastSpacing.gap),
                  Obx(
                    () => Expanded(
                      child: Text(controller.playlistEpisode.value.title ?? "",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: AnycastColor.playerText,
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
    var rightWidth = MediaQuery.of(context).size.width -
        AnycastSpacing.pageHeader * 2 -
        64 -
        AnycastSpacing.sm;
    return Obx(() {
      var episode = controller.playlistEpisode.value;
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
      var titleStyle = Theme.of(context).textTheme.headlineMedium!.copyWith(
            color: AnycastColor.playerText,
          );
      Widget titleWidget = Text(
        title,
        style: titleStyle,
      );
      // if text width > rightWidth, use marquee
      if (title.length * 22 > rightWidth) {
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
        const SizedBox(width: AnycastSpacing.sm),
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
              const SizedBox(height: AnycastSpacing.sm),
              GestureDetector(
                onTap: () {
                  jumpToChannel(episode, context, subscription);
                },
                child: SizedBox(
                  height: 24,
                  child: Text(
                    channelTitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AnycastColor.playerSecondary,
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
        final state = playbackProgressVisualState(
          hasEpisode:
              controller.playlistEpisode.value.enclosureUrl?.isNotEmpty == true,
          isLoading: controller.isLoading.value,
          duration: duration,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.message != null) ...[
              Text(
                state.message!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AnycastColor.playerSecondary,
                    ),
              ),
              const SizedBox(height: AnycastSpacing.xs),
            ],
            IgnorePointer(
              ignoring: !state.allowsSeek,
              child: Opacity(
                opacity: state.allowsSeek ? 1 : .48,
                child: ProgressBar(
                  progress: position,
                  buffered: bufferedPosition,
                  total: duration,
                  onSeek: state.allowsSeek
                      ? (duration) {
                          controller.seek(duration);
                        }
                      : null,
                  timeLabelLocation: state.allowsSeek
                      ? TimeLabelLocation.above
                      : TimeLabelLocation.none,
                  timeLabelType: TimeLabelType.remainingTime,
                  timeLabelPadding: AnycastSpacing.xs,
                  timeLabelTextStyle:
                      Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: AnycastColor.playerSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  thumbColor: AnycastColor.playerText,
                  thumbGlowColor: Colors.black.withValues(alpha: 0.2),
                  thumbCanPaintOutsideBar: false,
                  thumbRadius: AnycastSpacing.md,
                  thumbGlowRadius: AnycastSpacing.chip,
                  barHeight: AnycastSpacing.playerProgress,
                  barCapShape: BarCapShape.round,
                  baseBarColor: AnycastColor.sandAlpha3(Brightness.dark),
                  bufferedBarColor: AnycastColor.sandAlpha4(Brightness.dark),
                  progressBarColor: AnycastColor.playerText,
                ),
              ),
            ),
          ],
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
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AnycastColor.playerText,
                          ),
                    ),
                    const SizedBox(height: AnycastSpacing.md),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const ShapeDecoration(
                        color: AnycastColor.goldDark9,
                        shape: OvalBorder(),
                      ),
                      child: const Tooltip(
                        showDuration: Duration(seconds: 10),
                        message: 'AI transcript may take about 2 ~ 5 minutes',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Icon(
                          Icons.question_mark_rounded,
                          size: 12,
                          color: AnycastColor.sand12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AnycastSpacing.large),
                TextButton(
                  onPressed: () {
                    controller.add(url);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: AnycastColor.goldDark9,
                    foregroundColor: AnycastColor.sand12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AnycastSpacing.xxl,
                      vertical: AnycastSpacing.pageHeader,
                    ),
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
        var style = Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AnycastColor.playerText,
              fontWeight: FontWeight.w600,
            );
        return Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Lottie.asset('assets/lottie/robot_loading.json'),
                const SizedBox(height: AnycastSpacing.pageHeader),
                Text("Generating with AI ...", style: style),
                const SizedBox(height: AnycastSpacing.md),
                Text("It may take 2 ~ 5 minutes ...", style: style),
                const SizedBox(height: AnycastSpacing.pageHeader),
                Text(
                  "Feel free to explore or come back later.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AnycastColor.playerText,
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
              foregroundColor: AnycastColor.sand12,
              backgroundColor: AnycastColor.goldDark9,
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
                    return LyricsWithShare(
                      mainLyric: subtitle.toLrc(),
                      translationLyric: translation.toLrc(),
                      height: height,
                    );
                  });
                } else if (translationStatus == 'processing') {
                  return Column(
                    children: [
                      LyricsWithShare(
                        mainLyric: subtitle.toLrc(),
                        height: height - 48,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const RefreshProgressIndicator(),
                          Text(
                            "Translating subtitles...",
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AnycastColor.playerText,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ],
                  );
                } else {
                  return LyricsWithShare(
                    mainLyric: subtitle.toLrc(),
                    height: height,
                  );
                }
              },
            );
          },
        ),
      );
    });
  }
}

class LyricsWithShare extends StatefulWidget {
  const LyricsWithShare({
    super.key,
    required this.mainLyric,
    this.translationLyric,
    required this.height,
  });

  final String mainLyric;
  final String? translationLyric;
  final double height;

  @override
  State<LyricsWithShare> createState() => _LyricsWithShareState();
}

class _LyricsWithShareState extends State<LyricsWithShare>
    with AutomaticKeepAliveClientMixin {
  late LyricController _lyricController;
  final PlayerController _playerController = Get.find<PlayerController>();
  late Worker _progressWorker;

  @override
  bool get wantKeepAlive => true;

  // 使用预设样式并自定义
  static final _lyricStyle = LyricStyles.default1.copyWith(
    textStyle: GoogleFonts.mPlusRounded1c().copyWith(
      color: Colors.grey[200],
      fontSize: 14,
    ),
    activeStyle: GoogleFonts.mPlusRounded1c().copyWith(
      color: AnycastColor.goldDark9,
      fontSize: 16,
      fontWeight: FontWeight.w200,
    ),
    translationStyle: GoogleFonts.mPlusRounded1c().copyWith(
      color: AnycastColor.goldDark9,
      fontSize: 14,
    ),
    translationActiveColor: Colors.grey[300],
    lineGap: 12, // 减小行间距
    translationLineGap: 6, // 减小翻译行间距
    textAlign: TextAlign.left,
    anchorPosition: 0.5,
    contentPadding: const EdgeInsets.only(
        top: 100, left: 20, right: 20, bottom: 20), // 覆盖默认的 top: 500
    // 选择模式配置：拖拽后自动恢复
    selectLineResumeMode: SelectionAutoResumeMode.neverResume,
    selectLineResumeDuration: const Duration(milliseconds: 300),
    activeLineResumeDuration: const Duration(milliseconds: 3000),
  );

  @override
  void initState() {
    super.initState();
    _lyricController = LyricController();
    _loadLyrics();

    // 立即同步当前播放进度
    _lyricController.setProgress(_playerController.positionData.value.position);

    // 设置点击歌词行回调 - 用于切换播放/暂停
    _lyricController.setOnTapLineCallback((Duration position) {
      _playerController.togglePlay();

      var overlayEntry = OverlayEntry(
        builder: (context) => Center(
          child:
              PlayPauseAnimation(isPlaying: !_playerController.isPlaying.value),
        ),
      );
      Overlay.of(context).insert(overlayEntry);
      Future.delayed(const Duration(milliseconds: 500), () {
        overlayEntry.remove();
      });
    });

    // 监听播放进度变化
    _progressWorker = ever(_playerController.positionData, (positionData) {
      _lyricController.setProgress(positionData.position);
    });
  }

  void _loadLyrics() {
    _lyricController.loadLyric(
      widget.mainLyric,
      translationLyric: widget.translationLyric,
    );
  }

  @override
  void didUpdateWidget(covariant LyricsWithShare oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mainLyric != widget.mainLyric ||
        oldWidget.translationLyric != widget.translationLyric) {
      _loadLyrics();
    }
  }

  @override
  void dispose() {
    _progressWorker.dispose();
    _lyricController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 需要
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: widget.height,
          child: LyricView(
            controller: _lyricController,
            style: _lyricStyle,
          ),
        ),
        // 滚动时显示的时间横条和播放按钮
        SelectListenableBuilder(
          controller: _lyricController,
          builder: (SelectionState state, Widget? child) {
            return Positioned(
              top: state.centerY,
              left: AnycastSpacing.gap,
              right: AnycastSpacing.gap,
              child: FractionalTranslation(
                translation: const Offset(0, -0.5),
                child: Row(
                  children: [
                    // 左侧时间显示
                    Text(
                      "${state.duration.inMinutes.toString().padLeft(2, '0')}:${(state.duration.inSeconds % 60).toString().padLeft(2, '0')}",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AnycastColor.playerText,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        shadows: const [
                          Shadow(
                            color: Colors.black54,
                            offset: Offset(1, 1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 中间白线
                    Expanded(
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 右侧播放按钮
                    GestureDetector(
                      onTap: () {
                        _lyricController.stopSelection();
                        _playerController.seek(state.duration);
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AnycastColor.sandAlpha8(Brightness.dark),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: AnycastColor.goldDark9,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
                  child: const Iconify(
                    aiChat,
                    color: AnycastColor.goldDark9,
                    size: 24,
                  ),
                  onTap: () {
                    showMaterialModalBottomSheet(
                      context: context,
                      builder: (context) => ChatPage(
                          episode: _playerController.playlistEpisode.value),
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
                  exportSubtitles(
                    widget.mainLyric,
                    widget.translationLyric,
                  );
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
Future<void> exportSubtitles(String mainLyric, String? translationLyric) async {
  var playerController = Get.find<PlayerController>();
  var title = playerController.playlistEpisode.value.title ?? 'Subtitle';
  var channelTitle = playerController.playlistEpisode.value.channelTitle ?? '';
  var subject = '$title - $channelTitle';
  if (channelTitle.isEmpty) {
    subject = title;
  }

  var buffer = StringBuffer('# $subject\n\n---\n\n');
  buffer.writeln(mainLyric);
  if (translationLyric != null && translationLyric.isNotEmpty) {
    buffer.writeln('\n--- Translation ---\n');
    buffer.writeln(translationLyric);
  }

  var tempFile = await getTemporaryDirectory();
  var file = File('${tempFile.path}/$subject.txt');

  await file.writeAsString(buffer.toString());

  SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, name: subject)],
      subject: subject,
    ),
  );
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
                color: AnycastColor.sandAlpha4(Brightness.dark),
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
              color: isSelect
                  ? AnycastColor.playerText
                  : AnycastColor.playerSecondary,
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
    return Obx(() {
      final controlsEnabled = !controller.isLoading.value &&
          controller.playlistEpisode.value.enclosureUrl?.isNotEmpty == true;
      final buttonStyle = IconButton.styleFrom(
        foregroundColor: AnycastColor.playerText,
        disabledForegroundColor: AnycastColor.playerText.withValues(alpha: .38),
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
      );
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            style: buttonStyle,
            onPressed: controlsEnabled
                ? () {
                    myAudioHandler.seekByRelative(const Duration(seconds: -10));
                  }
                : null,
            icon: const Icon(
              Icons.replay_10,
              size: 48,
            ),
          ),
          SizedBox(
            height: 72,
            width: 72,
            child: IconButton(
              style: buttonStyle,
              onPressed: controlsEnabled
                  ? () {
                      if (controller.isPlaying.value) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    }
                  : null,
              icon: const PlayIcon(size: 48),
            ),
          ),
          IconButton(
            style: buttonStyle,
            onPressed: controlsEnabled
                ? () {
                    myAudioHandler.seekByRelative(const Duration(seconds: 30));
                  }
                : null,
            icon: const Icon(
              Icons.forward_30,
              size: 48,
            ),
          ),
        ],
      );
    });
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
    final sectionLabelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AnycastColor.playerSecondary,
          fontWeight: FontWeight.w600,
        );
    SliderThemeData sliderThemeData = SliderTheme.of(context).copyWith(
      activeTrackColor: AnycastColor.goldDark9,
      inactiveTrackColor: AnycastColor.sandAlpha4(Brightness.dark),
      trackHeight: AnycastSpacing.compactProgress,
      trackShape: const RoundedRectSliderTrackShape(),
      thumbColor: AnycastColor.playerText,
      thumbShape: const CustomSliderThumbCircle(thumbRadius: 20),
      overlayColor: Colors.transparent,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
      showValueIndicator: ShowValueIndicator.never,
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 4),
      activeTickMarkColor: AnycastColor.playerBackground,
      inactiveTickMarkColor: AnycastColor.playerSecondary,
      valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
      valueIndicatorColor: AnycastColor.playerBackground,
      valueIndicatorTextStyle:
          Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AnycastColor.playerBackground,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final sliderSurface = AnycastColor.sandAlpha3(Brightness.dark);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'SPEED',
                style: sectionLabelStyle,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AnycastSpacing.md),
            child: Obx(
              () => Material(
                shape: const StadiumBorder(),
                color: sliderSurface,
                child: Padding(
                  padding: const EdgeInsets.all(AnycastSpacing.xs),
                  child: SliderTheme(
                    data: sliderThemeData,
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
        const SizedBox(height: AnycastSpacing.pageH),
        Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'COUNTDOWN',
                style: sectionLabelStyle,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AnycastSpacing.md),
            child: Obx(
              () => Material(
                color: sliderSurface,
                shape: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(AnycastSpacing.xs),
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
        const SizedBox(height: AnycastSpacing.pageH),
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
                  style: sectionLabelStyle,
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
                          activeThumbColor: AnycastColor.playerBackground,
                          inactiveThumbColor: AnycastColor.playerSecondary,
                          inactiveTrackColor:
                              AnycastColor.sandAlpha5(Brightness.dark),
                          trackOutlineColor: WidgetStateColor.resolveWith(
                            (states) =>
                                AnycastColor.sandAlpha3(Brightness.dark),
                          ),
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
                  style: sectionLabelStyle,
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
                          activeThumbColor: AnycastColor.playerBackground,
                          inactiveThumbColor: AnycastColor.playerSecondary,
                          inactiveTrackColor:
                              AnycastColor.sandAlpha5(Brightness.dark),
                          trackOutlineColor: WidgetStateColor.resolveWith(
                            (states) =>
                                AnycastColor.sandAlpha3(Brightness.dark),
                          ),
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
              child: Icon(
                Icons.info,
                color: AnycastColor.playerSecondary,
              ),
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
