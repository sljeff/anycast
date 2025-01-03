import 'package:anycast/pages/discover.dart';
import 'package:anycast/pages/settings.dart';
import 'package:anycast/states/discover.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:simple_gradient_text/simple_gradient_text.dart';

class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const MyAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, top: 8),
        child: Column(
          children: [
            Container(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {
                  showMaterialModalBottomSheet(
                    expand: true,
                    context: context,
                    builder: (context) {
                      return const SettingsPage();
                    },
                    closeProgressThreshold: 0.9,
                  );
                },
                child: Container(
                  height: 36,
                  width: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF232830),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.settings_rounded,
                    color: Colors.grey.shade400,
                    size: 24,
                  ),
                ),
              ),
            ),
            Container(
              alignment: Alignment.centerLeft,
              height: 48,
              child: GradientText(
                title,
                gradientDirection: GradientDirection.ttb,
                colors: const [
                  Color(0xFF059669),
                  Color(0x00059669),
                ],
                style: TextStyle(
                  fontSize: 44,
                  fontFamily: GoogleFonts.comfortaa().fontFamily,
                  fontWeight: FontWeight.w700,
                  height: 0,
                  letterSpacing: 4.40,
                ),
              ),
            ),
            const SearchBar(),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(148);
}

class SearchBar extends GetView<DiscoverController> {
  const SearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    var searchBar = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        onTapOutside: (event) {
          FocusScope.of(context).unfocus();
        },
        onChanged: (value) {
          controller.searchText.value = value;
        },
        onSubmitted: (value) {
          if (value.isEmpty) {
            return;
          }
          controller.searchText.value = value;
          showMaterialModalBottomSheet(
            expand: true,
            context: context,
            builder: (context) => SearchPage(searchText: value),
            closeProgressThreshold: 0.8,
          );
        },
        controller: controller.searchController,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          hintText: 'Shows,Episodes,and more',
          hintStyle: TextStyle(
            color: const Color(0xFF4B5563),
            fontSize: 16,
            fontFamily: GoogleFonts.comfortaa().fontFamily,
            fontWeight: FontWeight.w400,
            height: 0,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFF4B5563),
            size: 24,
          ),
          filled: true,
          fillColor: const Color(0xFF232830),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF232830),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF232830),
            ),
          ),
        ),
      ),
    );

    return Obx(() {
      Widget cancel = const SizedBox.shrink();
      if (controller.searchText.value.isNotEmpty) {
        cancel = Row(
          children: [
            const SizedBox(
              width: 16,
            ),
            GestureDetector(
              onTap: () {
                controller.searchController.clear();
                controller.searchText.value = '';
                FocusScope.of(context).requestFocus(FocusNode());
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: const Color(0xFF34D399),
                  fontSize: 16,
                  fontFamily: GoogleFonts.comfortaa().fontFamily,
                  fontWeight: FontWeight.w400,
                  height: 0,
                ),
              ),
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: searchBar),
          cancel,
        ],
      );
    });
  }
}
