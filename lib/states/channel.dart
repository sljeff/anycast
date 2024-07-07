import 'dart:ui';

import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/pages/channel.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';

class ChannelController extends GetxController {
  var channel = SubscriptionModel.empty().obs;
  var episodes = <FeedEpisodeModel>[].obs;
  var isLoading = true.obs;
  var subscribed = false.obs;
  var isReversed = false.obs;
  var backgroundColor = const Color(0xFF111316).obs;

  var helper = DatabaseHelper();
  var subscriptionController = Get.find<SubscriptionController>();

  ChannelController({required SubscriptionModel channel}) {
    this.channel.value = channel;
    subscribed.value = subscriptionController.exists(channel);
  }

  @override
  void onInit() {
    super.onInit();
    load().then((_) {
      isLoading.value = false;
    });
    if (channel.value.title != null) {
      _updateColor();
    }
  }

  void _updateColor() {
    updatePaletteGenerator(CachedNetworkImageProvider(channel.value.imageUrl!))
        .then((color) {
      backgroundColor.value = color;
    });
  }

  Future<void> load() async {
    var podcastData = await channel.value.listAllEpisodes();
    episodes.value = podcastData.feedEpisodes!;
    if (channel.value.title == null) {
      channel.value = podcastData.subscription!;
      _updateColor();
    }
  }

  void subscribe() {
    subscribed.value = true;
    // add newest episode to feed
    if (episodes.isNotEmpty) {
      var newestEpisode = episodes.first;
      if (isReversed.value) {
        newestEpisode = episodes.last;
      }
      Get.find<FeedEpisodeController>().addMany([newestEpisode]);
      channel.value.lastUpdated = newestEpisode.pubDate;
    }
    subscriptionController.addMany([channel.value]);
  }

  void unsubscribe() {
    subscribed.value = false;
    subscriptionController.remove(channel.value);
  }

  void reverseEpisodes() {
    isReversed.value = !isReversed.value;
    episodes.value = episodes.reversed.toList();
  }
}
