import 'package:anycast/states/player.dart';
import 'package:anycast/utils/audio_handler.dart';
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
        Navigator.pop(context);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // draggable arrow (left)
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
          SwipeImage(),
          Titles(),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: MyProgressBar(),
          ),
          const SizedBox(height: 8),
          Controls(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class MyProgressBar extends StatelessWidget {
  MyProgressBar({super.key});

  // myAudioHandler
  final MyAudioHandler myAudioHandler = MyAudioHandler();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: myAudioHandler.positionDataStream,
      builder: (BuildContext context, positionData) {
        if (positionData.data == null) {
          return const SizedBox.shrink();
        }
        var duration = positionData.data?.duration ?? Duration.zero;
        var position = positionData.data?.position ?? Duration.zero;
        var bufferedPosition =
            positionData.data?.bufferedPosition ?? Duration.zero;
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

class SwipeImage extends StatelessWidget {
  SwipeImage({super.key});

  final MyAudioHandler myAudioHandler = MyAudioHandler();
  final PlayerController controller = Get.find();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: PageView(
        controller: PageController(viewportFraction: 0.8, initialPage: 1),
        // settings / image / description
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: Colors.red,
          ),
          Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              child: Obx(() {
                var episode = controller.playlistEpisode;
                return Hero(
                  tag: 'play_image',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      episode.value.imageUrl ?? '',
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              })),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: Colors.green,
          ),
        ],
      ),
    );
  }
}

class Controls extends StatelessWidget {
  Controls({super.key});

  final MyAudioHandler myAudioHandler = MyAudioHandler();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: myAudioHandler.playbackStateStream,
        builder: (context, snapshot) {
          var isPlaying = snapshot.data?.playing ?? false;

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
                  child: isPlaying
                      ? IconButton(
                          onPressed: () {
                            myAudioHandler.pause();
                          },
                          icon: const Icon(
                            Icons.pause,
                            size: 48,
                          ),
                        )
                      : IconButton(
                          onPressed: () {
                            myAudioHandler.play();
                          },
                          icon: const Icon(Icons.play_arrow, size: 48),
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
        });
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
        var episode = controller.playlistEpisode;
        if (episode.value.id == null) {
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
                  text: episode.value.title!,
                  blankSpace: 8,
                  style: TextStyle(
                    fontSize: 32,
                    decoration: TextDecoration.none,
                    color: Colors.white,
                  ),
                  // no bottom line
                ),
              ),
              SizedBox(
                child: Text(
                  episode.value.channelTitle!,
                  style: TextStyle(
                    fontSize: 12,
                    decoration: TextDecoration.none,
                    color: Colors.white.withOpacity(0.64),
                  ),
                ),
                height: 20,
              ),
            ],
          ),
        );
      },
    );
  }
}
