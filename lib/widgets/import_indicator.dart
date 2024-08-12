import 'package:anycast/states/import_indicator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ImportIndicator extends GetView<ImportIndicatorController> {
  const ImportIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Center(
          child: CircularProgressIndicator(
        value: controller.progress.toDouble(),
        backgroundColor: Colors.grey,
        strokeCap: StrokeCap.round,
      )),
    );
  }
}
