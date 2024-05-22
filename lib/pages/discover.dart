import 'package:anycast/states/channel.dart';
import 'package:anycast/states/discover.dart';
import 'package:anycast/api/podcasts.dart';
import 'package:anycast/pages/channel.dart';
import 'package:anycast/widgets/appbar.dart';
import 'package:anycast/widgets/card.dart' as card;
import 'package:anycast/widgets/card.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class Discover extends StatelessWidget {
  final DiscoverController controller = Get.put(DiscoverController());

  Discover({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: MyAppBar(
        title: 'DISCOVER',
        icon: Icons.settings_rounded,
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
                    return ListView.separated(
                        padding:
                            const EdgeInsets.only(left: 12, right: 12, top: 12),
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemCount: channels.length,
                        itemBuilder: (context, index) {
                          return PodcastCard(
                            subscription: channels[index],
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
      backgroundColor: const Color(0xFF111316),
      isFullScreen: false,
      direction: DismissiblePageDismissDirection.down,
      onDismissed: () {
        Get.back();
      },
      child: Column(
        children: [
          GestureDetector(
            child: const Handler(),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'You are searching for',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: GoogleFonts.comfortaa().fontFamily,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                controller.searchText.value,
                style: TextStyle(
                    color: const Color(0xFF6EE7B7),
                    fontSize: 16,
                    fontFamily: GoogleFonts.comfortaa().fontFamily,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Obx(
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
                  return ListView.separated(
                      padding:
                          const EdgeInsets.only(left: 12, right: 12, top: 12),
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemCount: subscriptions.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            Get.lazyPut(
                                () => ChannelController(
                                    channel: subscriptions[index]),
                                tag: subscriptions[index].rssFeedUrl);
                            context.pushTransparentRoute(Channel(
                              rssFeedUrl: subscriptions[index].rssFeedUrl!,
                            ));
                          },
                          child: card.PodcastCard(
                            subscription: subscriptions[index],
                          ),
                        );
                      });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
