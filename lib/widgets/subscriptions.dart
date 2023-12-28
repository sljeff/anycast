import 'package:flutter/material.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/subscription.dart';
import 'package:provider/provider.dart';

class Subscriptions extends StatefulWidget {
  const Subscriptions({super.key});

  @override
  State<Subscriptions> createState() => _SubscriptionsState();
}

class _SubscriptionsState extends State<Subscriptions> {
  final DatabaseHelper databaseHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    databaseHelper.db.then((db) {
      if (db == null) {
        throw Exception('Unable to open database');
      }
      SubscriptionModel.listAll(db).then((value) {
        Provider.of<SubscriptionProvider>(context, listen: false).load(value);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, SubscriptionProvider value, child) {
      if (value.subscriptions.isEmpty) {
        return const Center(
          child: Text('No subscriptions'),
        );
      }
      return ListView.builder(
        itemCount: value.subscriptions.length,
        itemBuilder: (context, index) {
          return ListTile(
            leading: value.subscriptions[index].imageUrl != null
                ? Image.network(value.subscriptions[index].imageUrl!,
                    width: 50, height: 50)
                : const SizedBox(
                    width: 50,
                    height: 50,
                    child: Icon(Icons.image),
                  ),
            title: Text(value.subscriptions[index].title!),
            subtitle: Text(
              value.subscriptions[index].description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      );
    });
  }
}
