import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ExpandableText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int maxLines;

  const ExpandableText(
    this.text, {
    super.key,
    this.maxLines = 2,
    this.textAlign = TextAlign.left,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final TextSpan span = TextSpan(text: text, style: style);
        final TextPainter tp = TextPainter(
          text: span,
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
          textAlign: textAlign,
        );
        tp.layout(maxWidth: constraints.maxWidth - 16);

        if (tp.didExceedMaxLines) {
          return GestureDetector(
            onTap: () {
              Get.dialog(
                AlertDialog(
                  content: Scrollbar(
                    trackVisibility: true,
                    thickness: 2,
                    child: SingleChildScrollView(
                      child: Text(text, style: style),
                    ),
                  ),
                  actions: [
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8.0),
              width: constraints.maxWidth,
              decoration: ShapeDecoration(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                color: Colors.blue.withOpacity(0.1),
              ),
              child: Text(
                text.replaceAll('\n\n', '\n'),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: style,
                textAlign: textAlign,
              ),
            ),
          );
        } else {
          return Text(text, style: style, textAlign: textAlign);
        }
      },
    );
  }
}
