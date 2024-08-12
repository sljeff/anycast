import 'package:get/get.dart';

class ImportIndicatorController extends GetxController {
  Rx<double> progress = 0.0.obs;

  void updateProgress(double value) {
    progress.value = value;
  }
}
