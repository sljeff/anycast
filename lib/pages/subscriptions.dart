import 'package:anycast/widgets/card.dart';
import 'package:flutter/material.dart';
import 'package:anycast/states/subscription.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class Subscriptions extends StatelessWidget {
  final SubscriptionController controller = Get.put(SubscriptionController());

  Subscriptions({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.subscriptions.isEmpty) {
        return Center(
          child: SizedBox(
            width: 300,
            child: Text(
              'Whoops! \n\nLooks like your podcast galaxy is still unexplored.\n \nStart subscribing and fill it with stars of shows!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontFamily: GoogleFonts.comfortaa().fontFamily,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.40,
              ),
            ),
          ),
        );
      }
      return ListView.separated(
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
        itemCount: controller.subscriptions.length,
        itemBuilder: (context, index) {
          return PodcastCard(subscription: controller.subscriptions[index]);
        },
      );
    });
  }
}
