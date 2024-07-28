import 'package:anycast/pages/subscriptions.dart';
import 'package:anycast/utils/keepalive.dart';
import 'package:anycast/widgets/appbar.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:anycast/pages/feeds.dart';

class PodcastsPage extends StatelessWidget {
  const PodcastsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
        appBar: MyAppBar(
          title: 'PODCAST',
        ),
        body: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(
                    text: 'Inbox',
                    icon: Icon(FluentIcons.mail_inbox_all_24_filled),
                  ),
                  Tab(
                    text: 'Subscriptions',
                    icon: Icon(FluentIcons.library_24_filled),
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    KeepAliveWrapper(key: Key('feeds'), child: Feeds()),
                    KeepAliveWrapper(
                        key: Key('subscriptions'), child: Subscriptions()),
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}
