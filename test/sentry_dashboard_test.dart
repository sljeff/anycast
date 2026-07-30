import 'package:anycast/sentry_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Sentry dashboard switches periods and issue views', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const SentryDashboardApp());
    await tester.pumpAndSettle();

    expect(find.text('APP DEVELOPMENT FEEDBACK'), findsOneWidget);
    expect(find.text('8'), findsWidgets);
    expect(find.text('ANYCAST-NM'), findsOneWidget);

    await tester.tap(find.text('7D'));
    await tester.pumpAndSettle();

    expect(find.text('27'), findsWidgets);
    expect(find.text('7D total'), findsOneWidget);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    expect(find.text('ANYCAST-Q1'), findsOneWidget);
    expect(find.text('ANYCAST-NM'), findsNothing);
  });
}
