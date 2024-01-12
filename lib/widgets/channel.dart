import 'package:anycast/models/subscription.dart';
import 'package:anycast/widgets/feeds_episodes_list.dart';
import 'package:anycast/widgets/player.dart';
import 'package:flutter/material.dart';
import 'package:expandable_text/expandable_text.dart';

class Channel extends StatelessWidget {
  final SubscriptionModel subscription;

  const Channel({Key? key, required this.subscription}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var subscribed = subscription.id != null;
    var screenSize = MediaQuery.of(context).size;

    return Scaffold(
      floatingActionButton: PlayerWidget(),
      appBar: AppBar(
        title: Text(subscription.title!),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Hero(
                  tag: subscription.imageUrl!,
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(subscription.imageUrl!),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  width: screenSize.width - 200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subscription.title!,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                      ),
                      Text(subscription.author!),
                    ],
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () {},
                        icon: Icon(subscribed ? Icons.check : Icons.add),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            width: screenSize.width,
            child: ExpandableText(
              subscription.description!,
              expandText: "show more",
              collapseText: "show less",
              maxLines: 3,
              linkColor: Colors.blue,
            ),
          ),
          const SizedBox(height: 16),
          // scrollable list of episodes
          Expanded(
            child: FutureBuilder(
              future: subscription.listAllEpisodes(),
              builder: (context, snapshot) {
                if (snapshot.hasData == false) {
                  return const Center(child: CircularProgressIndicator());
                }
                var episodes = snapshot.data!;
                return FeedsEpisodesListView(episodes, false);
              },
            ),
          )
        ],
      ),
    );
  }
}
