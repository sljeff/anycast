import 'package:flutter/material.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/widgets/feeds.dart';
import 'package:anycast/widgets/Subscriptions.dart';
import 'package:provider/provider.dart';

class PodcastsPage extends StatefulWidget {
  const PodcastsPage({super.key});

  @override
  State<PodcastsPage> createState() => _PodcastsPageState();
}

class _PodcastsPageState extends State<PodcastsPage> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FeedEpisodeProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
      ],
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
            appBar: AppBar(
              title: const Text('Podcasts'),
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.view_timeline), text: 'Feeds'),
                  Tab(icon: Icon(Icons.subscriptions), text: 'Subscriptions'),
                ],
              ),
            ),
            body: const TabBarView(
              children: [
                Feeds(),
                Subscriptions(),
              ],
            )),
      ),
    );
  }
}
