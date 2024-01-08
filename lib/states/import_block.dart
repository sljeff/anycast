import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ImportBlockController extends GetxController {
  TextEditingController textController = TextEditingController();
  final isLoading = false.obs;

  @override
  void onClose() {
    textController.dispose();
    super.onClose();
  }
}
