// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadrescue/main.dart';
import 'package:roadrescue/screens/main_navigation.dart';
import 'package:roadrescue/screens/welcome_screen.dart';

void main() {
  testWidgets('app builds successfully', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RoadRescueApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('provider registration opens from the motorist menu',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigation()));

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.text('Switch to Provider'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Join the verified network'), findsOneWidget);
    await tester.tap(find.text('Start registration'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Step 1 of 4  ·  Service'), findsOneWidget);
    expect(find.text('Mobile mechanic'), findsOneWidget);
    expect(find.text('Tow operator'), findsOneWidget);
  });
}
