import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:get/get.dart';

class ChannelController extends GetxController {
  var channel = SubscriptionModel.empty().obs;
  var episodes = <FeedEpisodeModel>[].obs;
  var isLoading = true.obs;
  var subscribed = false.obs;
  var isReversed = false.obs;

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
  }

  Future<void> load() async {
    var podcastData = await channel.value.listAllEpisodes();
    episodes.value = podcastData.feedEpisodes!;
    if (channel.value.title == null) {
      channel.value = podcastData.subscription!;
    }
  }

  void subscribe() {
    subscribed.value = true;
    subscriptionController.addMany([channel.value]);
    // add newest episode to feed
    if (episodes.isNotEmpty) {
      var newestEpisode = episodes.first;
      if (isReversed.value) {
        newestEpisode = episodes.last;
      }
      Get.find<FeedEpisodeController>().addMany([newestEpisode]);
    }
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
