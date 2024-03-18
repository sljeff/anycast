import 'package:anycast/states/player.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PlayIcon extends GetView<PlayerController> {
  final double size;

  const PlayIcon({Key? key, this.size = 24}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var isPlaying = controller.isPlaying.value;
      var isLoading = controller.isLoading.value;
      if (isLoading) {
        return Icon(Icons.hourglass_bottom, size: size);
      }
      if (isPlaying) {
        return Icon(Icons.pause, size: size);
      }
      return Icon(Icons.play_arrow, size: size);
    });
  }
}
