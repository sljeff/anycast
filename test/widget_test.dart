import 'package:anycast/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('root application widget can be constructed', () {
    expect(const NavigationBarApp(), isA<StatelessWidget>());
  });
}
