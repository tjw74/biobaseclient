import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:biobase_client/main.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const BiobaseApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
