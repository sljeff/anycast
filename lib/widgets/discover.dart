import 'package:anycast/states/discover.dart';
import 'package:anycast/utils/api.dart';
import 'package:anycast/widgets/channel.dart';
import 'package:anycast/widgets/player.dart';
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
                  context.pushTransparentRoute(SearchPage());
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
                    icon: Icon(Icons.clear),
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
      body: DiscoverBody(),
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
                          return ExpansionTile(
                            controlAffinity: ListTileControlAffinity.leading,
                            leading: GestureDetector(
                              onTap: () {
                                context.pushTransparentRoute(DismissiblePage(
                                  direction:
                                      DismissiblePageDismissDirection.down,
                                  onDismissed: () {
                                    Get.back();
                                  },
                                  child: Channel(
                                    subscription: channels[index],
                                  ),
                                ));
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  channels[index].imageUrl!,
                                  width: 50,
                                  height: 50,
                                ),
                              ),
                            ),
                            title: Text(channels[index].title!),
                            subtitle: Text(
                              channels[index].description!,
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
            leading: SizedBox.shrink(),
            title: IconButton(
              onPressed: () {
                Get.back();
              },
              icon: Icon(Icons.keyboard_arrow_down),
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
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          subscriptions[index].imageUrl!,
                          width: 50,
                          height: 50,
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
