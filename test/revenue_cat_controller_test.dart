import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anycast/states/user.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const purchasesChannel = MethodChannel('purchases_flutter');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchasesChannel, null);
  });

  test('RevenueCat sign out handles an offline platform error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchasesChannel, (call) async {
      expect(call.method, 'logOut');
      throw PlatformException(
        code: '35',
        message: 'Synthetic offline error',
      );
    });

    await expectLater(
      RevenueCatController().signOut(),
      completes,
    );
  });
}
