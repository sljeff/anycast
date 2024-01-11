import 'dart:convert';

import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/subscription.dart';
import 'package:webfeed_plus/webfeed_plus.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class PodcastImportData {
  SubscriptionModel? subscription;
  List<FeedEpisodeModel>? feedEpisodes;

  PodcastImportData(this.subscription, this.feedEpisodes);
}

Future<List<PodcastImportData>> fetchPodcastsByUrls(List<String> rssFeedUrls,
    {bool onlyFistEpisode = true}) async {
  List<PodcastImportData> podcasts = [];

  var futures = rssFeedUrls.map((rssFeedUrl) {
    return http.get(Uri.parse(rssFeedUrl)).then((response) {
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
        'description': htmlToText(channel.description)?.trim(),
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
          'description':
              item.itunes?.summary?.trim() ?? item.description?.trim(),
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
      return PodcastImportData(subscription, feedEpisodes);
    }).catchError((error) {
      print(error);
      return null;
    });
  }).toList();
  var result = await Future.wait(futures, eagerError: false);

  for (PodcastImportData? podcast in result) {
    if (podcast == null) {
      continue;
    }
    podcasts.add(podcast);
  }

  return podcasts;
}

String? htmlToText(String? html) {
  if (html == null) {
    return null;
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
    return document.body?.text;
  } catch (error) {
    print(error);
    return html;
  }
}
