import 'package:anycast/states/channel.dart';
import 'package:anycast/states/discover.dart';
import 'package:anycast/utils/api.dart';
import 'package:anycast/widgets/channel.dart';
import 'package:anycast/widgets/player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Discover extends StatelessWidget {
  final DiscoverController controller = Get.put(DiscoverController());

  Discover({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: MediaQuery.of(context).size.width - 100,
              height: 50,
              child: TextField(
                onChanged: (value) {
                  controller.searchText.value = value;
                },
                onSubmitted: (value) {
                  controller.searchText.value = value;
                  context.pushTransparentRoute(const SearchPage());
                },
                controller: controller.searchController,
                decoration: InputDecoration(
                  hintText: 'Search title',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: IconButton(
                    onPressed: () {
                      controller.searchController.clear();
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                context.pushTransparentRoute(const SearchPage());
              },
              icon: const Icon(Icons.search),
            ),
          ],
        ),
      ),
      body: const DiscoverBody(),
    );
  }
}

class DiscoverBody extends StatelessWidget {
  const DiscoverBody({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: listCategories(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        var categories = snapshot.data!;
        return DefaultTabController(
          length: categories.length,
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabs: categories.map((c) => Tab(text: c.name)).toList(),
            ),
            Expanded(
              child: TabBarView(
                  children: categories.map((c) {
                return FutureBuilder(
                  future: listChannelsByCategoryId(c.id),
                  builder: ((context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    var channels = snapshot.data!;
                    return ListView.builder(
                        itemCount: channels.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            onTap: () {
                              Get.lazyPut(
                                  () => ChannelController(
                                      channel: channels[index]),
                                  tag: channels[index].rssFeedUrl);
                              context.pushTransparentRoute(Channel(
                                subscription: channels[index],
                              ));
                            },
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: channels[index].imageUrl!,
                                width: 50,
                                height: 50,
                                placeholder: (context, url) => const Icon(
                                  Icons.image,
                                ),
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                  Icons.image_not_supported,
                                ),
                              ),
                            ),
                            title: Text(channels[index].title!),
                            subtitle: Text(
                              channels[index].description!,
                              maxLines: 2,
                            ),
                          );
                        });
                  }),
                );
              }).toList()),
            ),
          ]),
        );
      },
    );
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
        appBar: AppBar(
            centerTitle: true,
            leading: const SizedBox.shrink(),
            title: IconButton(
              onPressed: () {
                Get.back();
              },
              icon: const Icon(Icons.keyboard_arrow_down),
            )),
        body: Obx(
          () => FutureBuilder(
            future: searchChannels(controller.searchText.value),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
              var subscriptions = snapshot.data!;
              if (subscriptions.isEmpty) {
                return const Center(
                  child: Text('No results'),
                );
              }
              return ListView.builder(
                  itemCount: subscriptions.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      onTap: () {
                        Get.lazyPut(
                            () => ChannelController(
                                channel: subscriptions[index]),
                            tag: subscriptions[index].rssFeedUrl);
                        context.pushTransparentRoute(Channel(
                          subscription: subscriptions[index],
                        ));
                      },
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: subscriptions[index].imageUrl!,
                          width: 50,
                          height: 50,
                          placeholder: (context, url) => const Icon(
                            Icons.image,
                          ),
                          errorWidget: (context, url, error) => const Icon(
                            Icons.image_not_supported,
                          ),
                        ),
                      ),
                      title: Text(subscriptions[index].title!),
                      subtitle: Text(
                        subscriptions[index].description!,
                        maxLines: 2,
                      ),
                    );
                  });
            },
          ),
        ),
      ),
    );
  }
}
