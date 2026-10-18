import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logic/crash_controller.dart';
import 'firebase_options.dart';
import 'services/crash_notification_service.dart';
import 'services/auth_service.dart';
import 'services/client_location_sharing_service.dart';
import 'services/emergency_settings_service.dart';
import 'services/foreground_monitor_service.dart';
import 'services/firestore_service.dart';
import 'services/demo_session.dart';
import 'services/location_service.dart';
import 'services/maintenance_reminder_service.dart';
import 'services/push_token_service.dart';
import 'widgets/common_widgets.dart';
import 'screens/main_navigation.dart';
import 'screens/welcome_screen.dart';
import 'screens/demo_account_screen.dart';
import 'ui/safety_prompt_screen.dart';

final _appNavigatorKey = GlobalKey<NavigatorState>();
bool _safetyPromptVisible = false;

void _showSafetyPrompt() {
  final navigator = _appNavigatorKey.currentState;
  if (navigator == null || _safetyPromptVisible) return;
  _safetyPromptVisible = true;
  unawaited(
    navigator
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const SafetyPromptScreen(),
          ),
        )
        .whenComplete(() => _safetyPromptVisible = false),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ForegroundMonitorService.initialize();
  CrashController.instance.initialize();
  try {
    await MaintenanceReminderService.instance.initialize();
  } catch (error) {
    debugPrint('Loading maintenance reminder tracking failed: $error');
  }
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    debugPrint('Firebase initialization failed: $error');
  }
  try {
    await CrashNotificationService.instance.initialize(
      onPromptOpened: CrashController.instance.sync,
    );
  } catch (error) {
    debugPrint('Crash notification initialization failed: $error');
  }
  runApp(const RoadRescueApp());
}

const _currentTermsVersion = '2026-10-v2';

class RoadRescueApp extends StatefulWidget {
  const RoadRescueApp({super.key});

  @override
  State<RoadRescueApp> createState() => _RoadRescueAppState();
}

class _RoadRescueAppState extends State<RoadRescueApp> {
  bool? _welcomeComplete;
  DemoAccountMode? _demoMode;
  late final StreamSubscription<CrashState> _crashStateSubscription;

  @override
  void initState() {
    super.initState();
    _crashStateSubscription = CrashController.instance.states.listen((state) {
      if (state == CrashState.awaitingResponse) {
        _showSafetyPrompt();
      } else if (state == CrashState.armed || state == CrashState.idle) {
        unawaited(
          CrashNotificationService.instance.clearCrashPrompt().catchError(
            (Object error) {
              debugPrint('Clearing crash prompt notification failed: $error');
            },
          ),
        );
      }
    });
    CrashController.instance.sync();
    _loadWelcomeState();
  }

  Future<void> _loadWelcomeState() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      var welcomeComplete =
          (preferences.getBool('welcome_complete') ?? false) &&
              (preferences.getBool('terms_accepted') ?? false) &&
              (preferences.getBool('profile_saved_to_firebase') ?? false) &&
              preferences.getString('terms_version') == _currentTermsVersion;

      if (welcomeComplete && Firebase.apps.isNotEmpty) {
        final auth = FirebaseAuth.instance;
        final user = await auth.authStateChanges().first;
        if (user == null) {
          welcomeComplete = false;
        } else {
          try {
            await user.reload();
          } on FirebaseAuthException catch (error) {
            if (error.code == 'user-not-found' ||
                error.code == 'invalid-user-token') {
              await auth.signOut();
              welcomeComplete = false;
            } else {
              debugPrint('Firebase account verification failed: $error');
            }
          }
        }
      }

      if (!welcomeComplete &&
          (preferences.getBool('welcome_complete') ?? false)) {
        await preferences.setBool('welcome_complete', false);
        await preferences.setBool('profile_saved_to_firebase', false);
      }
      if (welcomeComplete) {
        try {
          await PushTokenService.instance.start();
        } catch (error) {
          debugPrint('Registering crash push notifications failed: $error');
        }
        await EmergencySettingsService.instance.load();
        if (EmergencySettingsService.instance.autoCrashDetectionEnabled) {
          try {
            await CrashController.instance.start();
          } catch (error) {
            debugPrint('Restoring crash monitoring failed: $error');
          }
        }
      }
      if (!mounted) return;
      setState(() => _welcomeComplete = welcomeComplete);
    } catch (error) {
      debugPrint('Loading onboarding state failed: $error');
      if (!mounted) return;
      setState(() => _welcomeComplete = false);
    }
  }

  @override
  void dispose() {
    _crashStateSubscription.cancel();
    super.dispose();
  }

  Future<void> _completeWelcome({
    required String name,
    required String phone,
    required String nationalId,
    required String bloodType,
    required String vehicleMake,
    required String vehicleModel,
    required String vehicleRegistration,
    required bool acceptedTerms,
    required bool acceptedHealthData,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await FirestoreService().saveOnboardingProfile(
      name: name,
      phone: phone,
      nationalId: nationalId,
      bloodType: bloodType,
      vehicleMake: vehicleMake,
      vehicleModel: vehicleModel,
      vehicleRegistration: vehicleRegistration,
      acceptedHealthData: acceptedHealthData,
      termsVersion: _currentTermsVersion,
    );
    try {
      await PushTokenService.instance.start();
    } catch (error) {
      debugPrint('Registering crash push notifications failed: $error');
    }
    await preferences.setBool('terms_accepted', acceptedTerms);
    await preferences.setString('terms_version', _currentTermsVersion);
    await preferences.setBool('profile_saved_to_firebase', true);
    await preferences.setBool('welcome_complete', true);
    if (mounted) setState(() => _welcomeComplete = true);
  }

  Future<void> _signInExistingAccount(
    String email,
    String password,
  ) async {
    await AuthService().signIn(email, password);
    final profile = await FirestoreService().loadCurrentUserProfile();
    final acceptedAt = profile['termsAcceptedAt'];
    final termsVersion = profile['termsVersion'];
    if (acceptedAt == null || termsVersion != _currentTermsVersion) {
      throw StateError(
        'This account needs to review the current terms before continuing. '
        'Use the profile setup flow to update consent.',
      );
    }
    final name = profile['name'] as String? ?? '';
    final phone = profile['phone'] as String? ?? '';
    final nationalId = profile['nationalId'] as String? ?? '';
    if (name.trim().isEmpty ||
        phone.trim().isEmpty ||
        nationalId.trim().isEmpty) {
      throw StateError(
        'This account profile is incomplete. Complete profile setup first.',
      );
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('terms_accepted', true);
    await preferences.setString('terms_version', _currentTermsVersion);
    await preferences.setBool('profile_saved_to_firebase', true);
    await preferences.setBool('welcome_complete', true);
    try {
      await PushTokenService.instance.start();
    } catch (error) {
      debugPrint('Registering crash push notifications failed: $error');
    }
    await EmergencySettingsService.instance.load();
    if (EmergencySettingsService.instance.autoCrashDetectionEnabled) {
      try {
        await CrashController.instance.start();
      } catch (error) {
        debugPrint('Restoring crash monitoring after login failed: $error');
      }
    }
    if (mounted) {
      setState(() {
        _demoMode = null;
        _welcomeComplete = true;
      });
    }
  }

  void _openDemoAccount(DemoAccountMode mode) {
    DemoSession.instance.start(
      provider: mode == DemoAccountMode.provider,
    );
    EmergencySettingsService.instance.enterDemoMode();
    MaintenanceReminderService.instance.enterDemoMode();
    setState(() => _demoMode = mode);
  }

  void _exitDemoAccount() {
    CrashController.instance.cancelAlert();
    unawaited(CrashController.instance.stop());
    unawaited(ClientLocationSharingService.instance.stopLocal());
    unawaited(LocationService.instance.stopTracking());
    LocationService.instance.clearDemoPosition();
    DemoSession.instance.end();
    EmergencySettingsService.instance.leaveDemoMode();
    MaintenanceReminderService.instance.leaveDemoMode();
    setState(() => _demoMode = null);
  }

  Future<void> _signOut() async {
    await EmergencySettingsService.instance.load();
    await FirestoreService().stopCurrentUserLocationSharing();
    await ClientLocationSharingService.instance.stopLocal();
    await LocationService.instance.stopTracking();
    await CrashController.instance.stop();
    await EmergencySettingsService.instance.setAutoCrashDetectionEnabled(false);
    await EmergencySettingsService.instance.endTrip();
    await AuthService().signOut();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('welcome_complete', false);
    await preferences.setBool('profile_saved_to_firebase', false);
    if (mounted) {
      setState(() {
        _demoMode = null;
        _welcomeComplete = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _appNavigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'RoadRescue',
        theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: C.navy,
            scaffoldBackgroundColor: C.bg),
        home: _demoMode != null
            ? DemoAccountScreen(mode: _demoMode!, onExit: _exitDemoAccount)
            : _welcomeComplete == null
                ? const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(color: C.navy),
                    ),
                  )
                : _welcomeComplete!
                    ? MainNavigation(onSignOut: _signOut)
                    : WelcomeScreen(
                        onComplete: _completeWelcome,
                        onLogin: _signInExistingAccount,
                        onOpenDemo: _openDemoAccount,
                      ),
      );
}
