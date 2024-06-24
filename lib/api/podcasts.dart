import 'dart:convert';

import 'package:anycast/models/subscription.dart';
import 'package:http/http.dart' as http;

const host = 'api.anycast.website';
const country = 'cn';

Future<List<SubscriptionModel>> searchChannels(String searchText) async {
  // url encode
  var url = Uri(
    host: host,
    scheme: 'https',
    path: '/search_channel/v2',
    queryParameters: {
      'keyword': searchText,
      'limit': '20',
    },
  );

  var response = await http.get(url);
  var body = utf8.decode(response.bodyBytes);
  Map<String, dynamic> data = jsonDecode(body);

  List<SubscriptionModel> subscriptions = [];
  for (var item in data['data']['channel_list']) {
    subscriptions.add(SubscriptionModel.fromMap({
      'rssFeedUrl': item['rss_url'],
      'title': item['title'].trim(),
      'description': item['description'].trim(),
      'imageUrl': item['small_cover_url'],
      'link': item['link'],
      'categories': item['keywords'].join(','),
      'author': item['author'].trim(),
      'email': '',
    }));
  }
  return subscriptions;
}

class Category {
  String name;
  String id;
  String imageUrl;
  String nightImageUrl;

  Category(this.name, this.id, this.imageUrl, this.nightImageUrl);
}

Future<List<Category>> listCategories() async {
  var url = Uri(
    host: host,
    scheme: 'https',
    path: '/categories',
  );

  var response = await http.get(url);
  var body = utf8.decode(response.bodyBytes);
  Map<String, dynamic> data = jsonDecode(body);

  var result = <Category>[];
  for (var item in data['data']) {
    result.add(Category(
      item['name'],
      item['id'],
      item['image_url'],
      item['night_image_url'],
    ));
  }
  return result;
}

Future<List<SubscriptionModel>> listChannelsByCategoryId(
    String categoryId) async {
  var url = Uri(
    host: host,
    scheme: 'https',
    path: '/top_channels/v2',
    queryParameters: {
      'category_id': categoryId,
      'country': country,
    },
  );

  var response = await http.get(url);
  var body = utf8.decode(response.bodyBytes);
  Map<String, dynamic> data = jsonDecode(body);

  List<SubscriptionModel> subscriptions = [];
  if (data['data'] == null) {
    return subscriptions;
  }

  for (var item in data['data']['list']) {
    subscriptions.add(SubscriptionModel.fromMap({
      'rssFeedUrl': item['rss_url'],
      'title': item['title'].trim(),
      'description': item['description'].trim(),
      'imageUrl': item['small_cover_url'],
      'link': item['link'],
      'categories': item['keywords'].join(','),
      'author': item['author'].trim(),
      'email': '',
    }));
  }
  return subscriptions;
}
