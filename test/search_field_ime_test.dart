import 'package:anycast/design_system/anycast_theme.dart';
import 'package:anycast/pages/channel.dart' as channel;
import 'package:anycast/widgets/import_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get _textField => find.byType(TextField);

TextEditingController _controller(WidgetTester tester) {
  return tester.widget<TextField>(_textField).controller!;
}

Future<void> _sendEditingValue(
  WidgetTester tester, {
  required String text,
  required int selection,
  TextRange composing = TextRange.empty,
}) async {
  await tester.showKeyboard(_textField);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: selection),
      composing: composing,
    ),
  );
  await tester.idle();
  await tester.pump();
}

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AnycastTheme.light,
      home: Scaffold(body: child),
    );
  }

  group('channel episode search field', () {
    testWidgets('keeps IME composing after the Clear button appears',
        (tester) async {
      await tester.pumpWidget(
        wrap(const channel.SearchBar(rssFeedUrl: 'https://example.com/feed')),
      );

      await tester.tap(_textField);
      await tester.pump();

      await _sendEditingValue(
        tester,
        text: 'y',
        selection: 1,
        composing: const TextRange(start: 0, end: 1),
      );

      expect(find.text('Clear'), findsOneWidget);

      final controller = _controller(tester);
      expect(controller.text, 'y');
      expect(controller.value.composing, const TextRange(start: 0, end: 1));
      expect(controller.selection, const TextSelection.collapsed(offset: 1));

      await _sendEditingValue(
        tester,
        text: 'ys',
        selection: 2,
        composing: const TextRange(start: 0, end: 2),
      );

      expect(_controller(tester).text, 'ys');
      expect(
        _controller(tester).value.composing,
        const TextRange(start: 0, end: 2),
      );
      expect(
        _controller(tester).selection,
        const TextSelection.collapsed(offset: 2),
      );
    });

    testWidgets('keeps the caret where a character was deleted', (tester) async {
      await tester.pumpWidget(
        wrap(const channel.SearchBar(rssFeedUrl: 'https://example.com/feed')),
      );

      await tester.tap(_textField);
      await tester.pump();

      await _sendEditingValue(tester, text: 'yys', selection: 3);
      await _sendEditingValue(tester, text: 'ys', selection: 1);

      final controller = _controller(tester);
      expect(controller.text, 'ys');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
    });
  });

  group('RSS import field', () {
    testWidgets('reuses the same controller across parent rebuilds',
        (tester) async {
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          theme: AnycastTheme.light,
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return const ImportExportBlock();
            },
          ),
        ),
      );

      final original = _controller(tester);
      await tester.enterText(_textField, 'https://example.com/rss');
      await tester.pump();

      rebuild(() {});
      await tester.pump();

      final afterRebuild = _controller(tester);
      expect(identical(original, afterRebuild), isTrue);
      expect(afterRebuild.text, 'https://example.com/rss');
    });

    testWidgets('keeps IME composing instead of rewriting controller.text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AnycastTheme.light,
          home: const ImportExportBlock(),
        ),
      );

      await tester.tap(_textField);
      await tester.pump();

      await _sendEditingValue(
        tester,
        text: 'ys',
        selection: 2,
        composing: const TextRange(start: 0, end: 2),
      );

      final controller = _controller(tester);
      expect(controller.text, 'ys');
      expect(controller.value.composing, const TextRange(start: 0, end: 2));
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });
  });
}
