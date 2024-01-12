import 'dart:convert';

import 'package:anycast/models/subscription.dart';
import 'package:http/http.dart' as http;

const headers = {
  'x-rapidapi-key': '4188f37e0dmsh6f57cb3e9804782p1f968ejsnec06e0a349b6',
  'x-rapidapi-host': 'podcast-api1.p.rapidapi.com',
};

const country = 'cn';

Future<List<SubscriptionModel>> searchChannels(String searchText) async {
  // url encode
  var url = Uri(
    host: 'podcast-api1.p.rapidapi.com',
    scheme: 'https',
    path: '/search_channel/v2',
    queryParameters: {
      'keyword': searchText,
      'limit': '20',
    },
  );

  var response = await http.get(url, headers: headers);
  var body = utf8.decode(response.bodyBytes);
  Map<String, dynamic> data = jsonDecode(body);

  List<SubscriptionModel> subscriptions = [];
  for (var item in data['data']['channel_list']) {
    subscriptions.add(SubscriptionModel.fromMap({
      'rssFeedUrl': item['rss_url'],
      'title': item['title'],
      'description': item['description'],
      'imageUrl': item['small_cover_url'],
      'link': item['link'],
      'categories': item['keywords'].join(','),
      'author': item['author'],
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
    host: 'podcast-api1.p.rapidapi.com',
    scheme: 'https',
    path: '/categories',
  );

  var response = await http.get(url, headers: headers);
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
    host: 'api.anycast.website',
    scheme: 'https',
    path: '/top_channels/v2',
    queryParameters: {
      'category_id': categoryId,
      'country': country,
    },
  );

  var response = await http.get(url, headers: headers);
  var body = utf8.decode(response.bodyBytes);
  Map<String, dynamic> data = jsonDecode(body);

  List<SubscriptionModel> subscriptions = [];
  for (var item in data['data']['list']) {
    subscriptions.add(SubscriptionModel.fromMap({
      'rssFeedUrl': item['rss_url'],
      'title': item['title'],
      'description': item['description'],
      'imageUrl': item['small_cover_url'],
      'link': item['link'],
      'categories': item['keywords'].join(','),
      'author': item['author'],
      'email': '',
    }));
  }
  return subscriptions;
}
