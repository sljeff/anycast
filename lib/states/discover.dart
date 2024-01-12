import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DiscoverController extends GetxController {
  var searchController = TextEditingController();
  final searchText = ''.obs;
  final isLoading = false.obs;
}
