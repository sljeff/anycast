import 'package:anycast/states/player.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PlayIcon extends GetView<PlayerController> {
  const PlayIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var isPlaying = controller.isPlaying.value;
      var isLoading = controller.isLoading.value;
      if (isLoading) {
        return const Icon(Icons.hourglass_bottom);
      }
      if (isPlaying) {
        return const Icon(Icons.pause);
      }
      return const Icon(Icons.play_arrow);
    });
  }
}
