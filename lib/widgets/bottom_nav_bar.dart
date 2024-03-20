import 'package:anycast/states/tab.dart';
import 'package:anycast/styles.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BottomNavBar extends GetView<HomeTabController> {
  const BottomNavBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.only(
        top: 16,
        left: 24,
        right: 24,
        bottom: 24,
      ),
      decoration: ShapeDecoration(
        color: DarkColor.primaryBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        shadows: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 0),
            spreadRadius: 0,
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BottomIcon(
            icon: Icons.podcasts,
            index: 0,
            onTap: () {
              controller.onItemTapped(0);
            },
          ),
          BottomIcon(
            icon: Icons.playlist_play,
            index: 1,
            onTap: () {
              controller.onItemTapped(1);
            },
          ),
          BottomIcon(
            icon: Icons.search,
            index: 2,
            onTap: () {
              controller.onItemTapped(2);
            },
          ),
        ],
      ),
    );
  }
}

class BottomIcon extends GetView<HomeTabController> {
  final IconData icon;
  final int index;
  final VoidCallback onTap;

  const BottomIcon({
    required this.icon,
    required this.index,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var iconColor = DarkColor.secondaryColor;
      var decorationColor = Colors.transparent;
      if (index == controller.selectedIndex.value) {
        iconColor = Colors.white;
        decorationColor = DarkColor.primary;
      }

      var iconBtn = Container(
        width: 48,
        height: 48,
        decoration: ShapeDecoration(
          color: decorationColor,
          shape: const OvalBorder(),
        ),
        child: Icon(
          icon,
          color: iconColor,
        ),
      );

      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 96,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: iconBtn,
        ),
      );
    });
  }
}
