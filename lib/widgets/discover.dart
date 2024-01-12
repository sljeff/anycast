import 'dart:convert';

import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/discover.dart';
import 'package:anycast/widgets/channel.dart';
import 'package:anycast/widgets/player.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

class Discover extends StatelessWidget {
  final DiscoverController controller = Get.put(DiscoverController());

  Discover({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Discover'),
      ),
      body: Column(
        children: [
          // search bar, onclick jump to search page
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) {
                      controller.searchText.value = value;
                    },
                    controller: controller.searchController,
                    decoration: InputDecoration(
                      hintText: 'Search',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    context.pushTransparentRoute(SearchPage());
                  },
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          DiscoverBody(),
        ],
      ),
    );
  }
}

class DiscoverBody extends StatelessWidget {
  const DiscoverBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

class SearchPage extends GetView<DiscoverController> {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DismissiblePage(
      direction: DismissiblePageDismissDirection.down,
      onDismissed: () {
        Get.back();
      },
      child: Scaffold(
        floatingActionButton: PlayerWidget(),
        body: Obx(
          () => FutureBuilder(
            future: get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
              var subscriptions = snapshot.data!;
              return ListView.builder(
                  itemCount: subscriptions.length,
                  itemBuilder: (context, index) {
                    return ExpansionTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      leading: GestureDetector(
                        onTap: () {
                          context.pushTransparentRoute(DismissiblePage(
                            direction: DismissiblePageDismissDirection.down,
                            onDismissed: () {
                              Get.back();
                            },
                            child: Channel(
                              subscription: subscriptions[index],
                            ),
                          ));
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            subscriptions[index].imageUrl!,
                            width: 50,
                            height: 50,
                          ),
                        ),
                      ),
                      title: Text(subscriptions[index].title!),
                      subtitle: Text(
                        subscriptions[index].description!,
                        maxLines: 2,
                      ),
                      children: [
                        ButtonBar(
                          alignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () {},
                              icon: Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    );
                  });
            },
          ),
        ),
      ),
    );
  }

  Future<List<SubscriptionModel>> get() async {
    var searchText = controller.searchText.value;
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
    var headers = {
      'x-rapidapi-key': '4188f37e0dmsh6f57cb3e9804782p1f968ejsnec06e0a349b6',
      'x-rapidapi-host': 'podcast-api1.p.rapidapi.com',
    };

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
}
