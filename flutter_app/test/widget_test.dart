import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:safety_app/app/app.dart';

void main() {
  testWidgets('SafetyApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SafetyApp(),
      ),
    );

    // Basic smoke test - app should render without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
