import 'dart:convert';
import 'dart:isolate';

import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/utils/http_client.dart';
import 'package:get/get.dart';
import 'package:webfeed_plus/webfeed_plus.dart';
import 'package:html/parser.dart' as html_parser;

class PodcastImportData {
  SubscriptionModel? subscription;
  List<FeedEpisodeModel>? feedEpisodes;

  PodcastImportData(this.subscription, this.feedEpisodes);
}

Future<List<PodcastImportData>> importPodcastsByUrls(List<String> rssFeedUrls) {
  // filter exsiting subscriptions
  var existingSubscriptions = Get.find<SubscriptionController>().subscriptions;
  var s = Set.from(existingSubscriptions.map((e) => e.rssFeedUrl));
  rssFeedUrls = rssFeedUrls.where((element) => !s.contains(element)).toList();

  return fetchPodcastsByUrls(rssFeedUrls);
}

Future<List<PodcastImportData>> fetchPodcastsByUrls(
  List<String> rssFeedUrls, {
  bool onlyFistEpisode = true,
}) async {
  // use isolate
  final ReceivePort receivePort = ReceivePort();
  await Isolate.spawn(_fetchPodcastsByUrls, [
    rssFeedUrls,
    onlyFistEpisode,
    receivePort.sendPort,
  ]);

  return (await receivePort.first) as List<PodcastImportData>;
}

void _fetchPodcastsByUrls(List<dynamic> args) async {
  var rssFeedUrls = args[0] as List<String>;
  var onlyFistEpisode = args[1] as bool;
  var sendPort = args[2] as SendPort;

  List<PodcastImportData> podcasts = [];

  var responses = await fetchConcurrentWithRetry(rssFeedUrls);
  var result = responses.entries.map((entry) {
    var rssFeedUrl = entry.key;
    var response = entry.value;
    if (response == null) {
      return null;
    }
    var body = utf8.decode(response.bodyBytes);
    RssFeed channel;
    try {
      channel = RssFeed.parse(body);
    } catch (error) {
      print(error);
      return null;
    }
    var subscription = SubscriptionModel.fromMap(Map<String, dynamic>.from({
      'rssFeedUrl': rssFeedUrl,
      'title': channel.title?.trim(),
      'description': htmlToText(channel.description).trim(),
      'imageUrl': channel.image?.url ?? (channel.itunes?.image?.href ?? ''),
      'link': channel.link,
      'categories': channel.categories?.map((e) => e.value).join(','),
      'author': channel.itunes?.author,
      'email': channel.itunes?.owner?.email,
    }));
    channel.items!.sort((a, b) {
      return b.pubDate!.compareTo(a.pubDate!);
    });
    List<FeedEpisodeModel> feedEpisodes = [];
    var length = onlyFistEpisode ? 1 : channel.items!.length;
    for (var i = 0; i < length; i++) {
      var item = channel.items![i];
      var feedEpisode = FeedEpisodeModel.fromMap(Map<String, dynamic>.from({
        'title': item.title?.trim(),
        'description': item.itunes?.summary?.trim() ?? item.description?.trim(),
        'guid': item.guid,
        'duration': item.itunes?.duration?.inMilliseconds,
        'enclosureUrl': item.enclosure?.url,
        'pubDate': item.pubDate?.millisecondsSinceEpoch,
        'imageUrl': item.itunes?.image?.href ?? subscription.imageUrl,
        'channelTitle': subscription.title,
        'rssFeedUrl': subscription.rssFeedUrl,
      }));
      feedEpisodes.add(feedEpisode);
    }
    subscription.lastUpdated = feedEpisodes[0].pubDate;
    return PodcastImportData(subscription, feedEpisodes);
  }).toList();

  for (PodcastImportData? podcast in result) {
    if (podcast == null) {
      continue;
    }
    podcasts.add(podcast);
  }

  Isolate.exit(sendPort, podcasts);
}

String htmlToText(String? html) {
  if (html == null) {
    return '';
  }
  html = html.trim();

  if (!html.startsWith('<')) {
    return html;
  }

  try {
    var document = html_parser.parse(html);
    if (document.body == null) {
      return html;
    }
    return document.body!.text;
  } catch (error) {
    print(error);
    return html;
  }
}
