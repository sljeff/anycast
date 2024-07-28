import 'package:anycast/states/player.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:lottie/lottie.dart';

class PlayIcon extends GetView<PlayerController> {
  final double size;
  final Color color;
  final String enclosureUrl;

  const PlayIcon({
    super.key,
    this.size = 24,
    this.color = Colors.black,
    this.enclosureUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (enclosureUrl != '' &&
          controller.playlistEpisode.value.enclosureUrl != enclosureUrl) {
        return Iconify(Ic.round_play_arrow, size: size, color: color);
      }

      var isPlaying = controller.isPlaying.value;
      var isLoading = controller.isLoading.value;

      if (isLoading) {
        if (color == Colors.white) {
          return Lottie.asset('assets/lottie/loading.json',
              height: size, width: size);
        }
        return Lottie.asset('assets/lottie/loading_black.json',
            height: size, width: size);
      }
      if (isPlaying) {
        return Iconify(Ic.round_pause, size: size, color: color);
      }
      return Iconify(Ic.round_play_arrow, size: size, color: color);
    });
  }
}

class AIIcon extends GetView<SubtitleController> {
  final String enclosureUrl;
  final double size;
  final Color color;

  const AIIcon({
    super.key,
    required this.enclosureUrl,
    this.size = 24,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var status = controller.subtitleUrls[enclosureUrl];

      switch (status) {
        case 'processing':
          return Lottie.asset('assets/lottie/robot_loading.json');
        case 'succeeded':
          return Iconify(Ic.round_check_circle, size: size, color: color);
        case 'failed':
          return Iconify(Ic.round_sms_failed, size: size, color: color);
        default:
          return Iconify(aiTranscript, size: size, color: Colors.black);
      }
    });
  }
}

const aiTranscript =
    '<svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 24 24"><path fill="white" fill-rule="evenodd" d="M 22 6.75 V 21 a 3 3 90 0 1 -3 3 H 10 v -1.5 h 9 a 1.5 1.5 90 0 0 1.5 -1.5 V 6.75 h -3 A 2.25 2.25 90 0 1 15.25 4.5 V 1.5 H 7 a 1.5 1.5 90 0 0 -1.5 1.5 v 13.5 H 4 V 3 a 3 3 90 0 1 3 -3 h 8.25 z M 2.6695 22.23 L 2.2 23.775 H 1 l 2.013 -5.9985 h 1.389 l 2.004 5.9985 h -1.2615 l -0.471 -1.542 H 2.6695 Z m 1.767 -0.882 l -0.735 -2.4255 h -0.051 l -0.735 2.4255 z m 3.6375 -3.573 v 5.9985 h -1.1865 V 17.775 h 1.185 Z M 7.5 15.5 a 1 0.8 90 0 1 0.8 -1 h 6.4 a 1 0.8 90 1 1 0 2 H 8.3 a 1 0.8 90 0 1 -0.8 -1 m 10.4 -5 a 1 0.8 90 1 1 0 2 h -6.4 a 1 0.8 90 1 1 0 -2 z m -1.6 5 a 1 0.8 90 0 1 0.8 -1 h 0.8 a 1 0.8 90 1 1 0 2 h -0.8 a 1 0.8 90 0 1 -0.8 -1 m -7.2 -5 a 1 0.8 90 1 1 0 2 H 8.3 a 1 0.8 90 1 1 0 -2 z"/></svg>';
