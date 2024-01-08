import 'package:anycast/widgets/channel.dart';
import 'package:flutter/material.dart';
import 'package:anycast/states/subscription.dart';
import 'package:get/get.dart';

class Subscriptions extends StatelessWidget {
  final SubscriptionController controller = Get.put(SubscriptionController());

  Subscriptions({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.subscriptions.isEmpty) {
        return const Center(
          child: Text('No subscriptions'),
        );
      }
      return ListView.builder(
        itemCount: controller.subscriptions.length,
        itemBuilder: (context, index) {
          return ListTile(
            leading: GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) {
                    return const Channel();
                  },
                ));
              },
              child: controller.subscriptions[index].imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                          controller.subscriptions[index].imageUrl!,
                          width: 50,
                          height: 50),
                    )
                  : const SizedBox(
                      width: 50,
                      height: 50,
                      child: Icon(Icons.image),
                    ),
            ),
            title: Text(controller.subscriptions[index].title!),
            subtitle: Text(
              controller.subscriptions[index].description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      );
    });
  }
}
