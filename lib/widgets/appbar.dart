import 'package:anycast/design_system/anycast_theme.dart';
import 'package:anycast/pages/discover.dart';
import 'package:anycast/pages/settings.dart';
import 'package:anycast/states/discover.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const MyAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      title: Padding(
        padding: const EdgeInsets.fromLTRB(
          AnycastSpacing.pageH,
          AnycastSpacing.xs,
          AnycastSpacing.pageH,
          AnycastSpacing.gap,
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _displayTitle(title),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    style: theme.textTheme.displayLarge,
                  ),
                ),
                const SizedBox(width: AnycastSpacing.gap),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () {
                    showMaterialModalBottomSheet(
                      expand: true,
                      context: context,
                      builder: (context) {
                        return const SettingsPage();
                      },
                      closeProgressThreshold: 0.9,
                    );
                  },
                  style: IconButton.styleFrom(
                    fixedSize: const Size(
                      AnycastSpacing.xxl,
                      AnycastSpacing.xxl,
                    ),
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                  icon: const Icon(Icons.settings_rounded, size: 26),
                ),
              ],
            ),
            const SizedBox(height: AnycastSpacing.gap),
            const SearchBar(),
          ],
        ),
      ),
    );
  }

  String _displayTitle(String value) {
    if (value.isEmpty) return value;
    final lower = value.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }

  @override
  Size get preferredSize => const Size.fromHeight(148);
}

class SearchBar extends GetView<DiscoverController> {
  const SearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var searchBar = SizedBox(
      height: 48,
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
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Shows, episodes, and more',
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 24,
          ),
        ),
      ),
    );

    return Obx(() {
      Widget cancel = const SizedBox.shrink();
      if (controller.searchText.value.isNotEmpty) {
        cancel = Row(
          children: [
            const SizedBox(width: AnycastSpacing.md),
            TextButton(
              onPressed: () {
                controller.searchController.clear();
                controller.searchText.value = '';
                FocusScope.of(context).requestFocus(FocusNode());
              },
              child: const Text('Cancel'),
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
