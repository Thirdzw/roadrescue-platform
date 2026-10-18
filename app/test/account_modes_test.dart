import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:roadrescue/screens/account_login_screen.dart';
import 'package:roadrescue/screens/demo_account_screen.dart';
import 'package:roadrescue/models/job.dart';
import 'package:roadrescue/services/emergency_call_service.dart';
import 'package:roadrescue/services/demo_session.dart';
import 'package:roadrescue/services/emergency_settings_service.dart';
import 'package:roadrescue/services/location_service.dart';
import 'package:roadrescue/services/maintenance_reminder_service.dart';

void main() {
  tearDown(() {
    DemoSession.instance.end();
    EmergencySettingsService.instance.leaveDemoMode();
    MaintenanceReminderService.instance.leaveDemoMode();
    LocationService.instance.clearDemoPosition();
  });

  testWidgets('existing account login validates email and password',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountLoginScreen(
          onLogin: (_, __) async {
            fail('Login callback should not run with invalid input.');
          },
          onOpenDemo: (_) {
            fail('Demo callback should not run with invalid input.');
          },
        ),
      ),
    );

    await tester.ensureVisible(find.text('Log in'));
    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('demo login requires password and second-step verification',
      (tester) async {
    DemoAccountMode? openedMode;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountLoginScreen(
          initialDemoMode: DemoAccountMode.provider,
          onLogin: (_, __) async {
            fail('Demo login should not call Firebase sign-in.');
          },
          onOpenDemo: (mode) => openedMode = mode,
        ),
      ),
    );

    expect(find.text(DemoAccountCredentials.providerEmail), findsOneWidget);
    await tester.ensureVisible(find.text('Log in'));
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Step 2 of 2'), findsOneWidget);
    expect(find.text('Demo verification code: 246810'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      DemoAccountCredentials.verificationCode,
    );
    await tester.tap(find.text('Verify & continue'));
    await tester.pumpAndSettle();

    expect(openedMode, DemoAccountMode.provider);
  });

  testWidgets('demo login rejects an incorrect password', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountLoginScreen(
          initialDemoMode: DemoAccountMode.motorist,
          onLogin: (_, __) async {
            fail('Demo login should not call Firebase sign-in.');
          },
          onOpenDemo: (_) {
            fail('Demo must not open with an incorrect password.');
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(1), 'incorrect');
    await tester.ensureVisible(find.text('Log in'));
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Demo email or password is incorrect.'), findsOneWidget);
    expect(find.textContaining('Step 2 of 2'), findsNothing);
  });

  testWidgets('demo login rejects an incorrect second-step code',
      (tester) async {
    DemoAccountMode? openedMode;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountLoginScreen(
          initialDemoMode: DemoAccountMode.motorist,
          onLogin: (_, __) async {},
          onOpenDemo: (mode) => openedMode = mode,
        ),
      ),
    );

    await tester.ensureVisible(find.text('Log in'));
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '000000');
    await tester.tap(find.text('Verify & continue'));
    await tester.pumpAndSettle();

    expect(find.text('Verification code is incorrect.'), findsOneWidget);
    expect(openedMode, isNull);
  });

  testWidgets('provider demo opens the interactive provider workspace',
      (tester) async {
    DemoSession.instance.start(provider: true);
    await tester.pumpWidget(
      MaterialApp(
        home: DemoAccountScreen(
          mode: DemoAccountMode.provider,
          onExit: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('DEMO SIMULATION · Sample data only'),
        findsOneWidget);
    expect(find.text('Provider mode'), findsOneWidget);
    expect(find.text('Your workday'), findsOneWidget);
    expect(find.text('Live rescue jobs'), findsOneWidget);
    expect(find.text('Tyre change'), findsOneWidget);
    expect(DemoSession.instance.currentUserId, DemoSession.providerId);
  });

  testWidgets('motorist demo remains a motorist after navigation mounts',
      (tester) async {
    DemoSession.instance.start(provider: false);
    await tester.pumpWidget(
      MaterialApp(
        home: DemoAccountScreen(
          mode: DemoAccountMode.motorist,
          onExit: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(DemoSession.instance.currentUserId, DemoSession.motoristId);
    expect(find.text('Emergency'), findsOneWidget);
  });

  test('demo request can be accepted in the local shared session', () async {
    final session = DemoSession.instance;
    session.start(provider: false);
    final request = await session.createRescueRequest(
      serviceType: 'Towing',
      position: Position.fromMap({
        'latitude': DemoSession.locationLatitude,
        'longitude': DemoSession.locationLongitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'accuracy': 20.0,
        'altitude': 0.0,
        'heading': 0.0,
        'speed': 0.0,
        'speed_accuracy': 0.0,
        'altitude_accuracy': 0.0,
        'heading_accuracy': 0.0,
      }),
    );

    expect(session.jobs.any((job) => job.id == request.id), isTrue);
    session.setProviderMode(true);
    session.updateJobStatus(
      request.id,
      JobStatus.matched.name,
      mechanicId: DemoSession.providerId,
    );

    expect(session.currentUserId, DemoSession.providerId);
    expect(
      session.jobs.singleWhere((job) => job.id == request.id).status,
      JobStatus.matched,
    );
    expect(
      session.jobs.singleWhere((job) => job.id == request.id).mechanicId,
      DemoSession.providerId,
    );
  });

  test('demo location and emergency call stay simulated', () async {
    DemoSession.instance.start(provider: false);

    final position = await LocationService.instance.getCurrentLocation();
    final callOpened = await EmergencyCallService.callNumber(
      number: '999',
      triggerType: 'demo_test',
      dryRun: false,
      directCall: true,
    );

    expect(position.isMocked, isTrue);
    expect(callOpened, isFalse);
    expect(LocationService.instance.lastPosition?.isMocked, isTrue);

    DemoSession.instance.end();
    LocationService.instance.clearDemoPosition();
    expect(LocationService.instance.lastPosition, isNull);
  });

  test('demo maintenance changes are discarded when demo mode ends', () async {
    final service = MaintenanceReminderService.instance;
    service.enterDemoMode();

    await service.recordService(
      odometerKm: 123456,
      serviceDate: DateTime.now().subtract(const Duration(days: 1)),
      intervalKm: 8000,
    );
    expect(service.lastServiceOdometerKm, 123456);

    service.leaveDemoMode();

    expect(service.hasServiceRecord, isFalse);
    expect(service.serviceIntervalKm, defaultMaintenanceIntervalKm);
  });
}
