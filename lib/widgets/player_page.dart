import 'package:anycast/states/player.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:get/get.dart';
import 'package:marquee/marquee.dart';

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
            Titles(),
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
    if (controller.playlistEpisode != null &&
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
            myAudioHandler.seek(duration);
          },
          timeLabelLocation: TimeLabelLocation.above,
          timeLabelType: TimeLabelType.totalTime,
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
                  child: SingleChildScrollView(
                      child: renderHtml(
                          context, controller.playlistEpisode!.description!)),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  child: Center(child: Icon(Icons.abc)),
                ),
                Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    child: Obx(() {
                      var episode = controller.playlistEpisode!;
                      return Hero(
                        tag: 'play_image',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: episode.imageUrl ?? '',
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
                  child: Center(child: Icon(Icons.abc)),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  child: Center(child: Icon(Icons.abc)),
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
            child: Obx(() {
              return controller.isPlaying.value
                  ? IconButton(
                      onPressed: () {
                        Get.find<PlayerController>().pause();
                      },
                      icon: const Icon(
                        Icons.pause,
                        size: 48,
                      ),
                    )
                  : IconButton(
                      onPressed: () {
                        Get.find<PlayerController>().play();
                      },
                      icon: const Icon(Icons.play_arrow, size: 48),
                    );
            }),
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

class Titles extends StatelessWidget {
  Titles({super.key});

  final MyAudioHandler myAudioHandler = MyAudioHandler();
  final PlayerController controller = Get.find();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        var episode = controller.playlistEpisode!;
        if (episode.id == null) {
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
              SizedBox(
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
            ],
          ),
        );
      },
    );
  }
}
