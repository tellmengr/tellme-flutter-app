import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('placeholder test', (WidgetTester tester) async {
    // Minimal widget that does NOT depend on any Providers or your app.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: Center(
            child: Text('Hello tests'),
          ),
        ),
      ),
    );

    // Verify that our placeholder text is found.
    expect(find.text('Hello tests'), findsOneWidget);
  });
}
