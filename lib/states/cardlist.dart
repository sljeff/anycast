import 'package:get/get.dart';

class CardListController extends GetxController {
  var expandedIndex = (-1).obs;

  void expand(int index) {
    if (expandedIndex.value == index) {
      expandedIndex.value = -1;
    } else {
      expandedIndex.value = index;
    }
  }

  void close() {
    expandedIndex.value = -1;
  }
}
