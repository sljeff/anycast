import 'package:anycast/utils/keepalive.dart';
import 'package:flutter/material.dart';
import 'package:anycast/widgets/feeds.dart';
import 'package:anycast/widgets/Subscriptions.dart';

class PodcastsPage extends StatefulWidget {
  const PodcastsPage({super.key});

  @override
  State<PodcastsPage> createState() => _PodcastsPageState();
}

class _PodcastsPageState extends State<PodcastsPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
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
          body: TabBarView(
            children: [
              KeepAliveWrapper(key: const Key('feeds'), child: Feeds()),
              KeepAliveWrapper(
                  key: const Key('subscriptions'), child: Subscriptions()),
            ],
          )),
    );
  }
}
