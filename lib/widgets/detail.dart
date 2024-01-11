import 'package:anycast/models/episode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:sanitize_html/sanitize_html.dart' show sanitizeHtml;

class DetailWidget extends StatelessWidget {
  final Episode episode;

  const DetailWidget(this.episode, {super.key});

  @override
  Widget build(BuildContext context) {
    return BottomSheet(
        enableDrag: false,
        onClosing: () {},
        builder: (context) => DraggableScrollableSheet(
              initialChildSize: 1,
              minChildSize: 0.6,
              expand: false,
              builder:
                  (BuildContext context, ScrollController scrollController) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12, left: 12, right: 12),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    episode.imageUrl!,
                                    width: 60,
                                    height: 60,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // link text channelTitle
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    episode.channelTitle!,
                                    style: const TextStyle(fontSize: 8),
                                    maxLines: 2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                                child: Text(
                              episode.title!,
                              style: const TextStyle(fontSize: 16),
                            )),
                          ],
                        ),
                        renderHtml(context, episode.description!),
                      ],
                    ),
                  ),
                );
              },
            ));
  }
}

Widget renderHtml(context, String html) {
  // if starts with <
  if (html.trim().startsWith('<')) {
    return Html(
      data: sanitizeHtml(html),
    );
  }

  return Text(html, style: const TextStyle(fontSize: 14));
}
