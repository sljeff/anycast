import 'package:anycast/models/episode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:sanitize_html/sanitize_html.dart' show sanitizeHtml;

class DetailWidget extends StatefulWidget {
  final Episode episode;

  const DetailWidget(this.episode, {super.key});

  @override
  State<DetailWidget> createState() => _DetailWidgetState();
}

class _DetailWidgetState extends State<DetailWidget> {
  @override
  Widget build(BuildContext context) {
    return BottomSheet(
        onClosing: () {},
        builder: (context) => DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
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
                                    widget.episode.imageUrl!,
                                    width: 60,
                                    height: 60,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // link text channelTitle
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    widget.episode.channelTitle!,
                                    style: const TextStyle(fontSize: 8),
                                    maxLines: 2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                                child: Text(
                              widget.episode.title!,
                              style: const TextStyle(fontSize: 16),
                            )),
                          ],
                        ),
                        renderHtml(context, widget.episode.description!),
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
