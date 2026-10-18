import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import 'account_login_screen.dart';
import 'demo_account_screen.dart';
import '../widgets/common_widgets.dart';

class WelcomeScreen extends StatefulWidget {
  final Future<void> Function({
    required String name,
    required String phone,
    required String nationalId,
    required String bloodType,
    required String vehicleMake,
    required String vehicleModel,
    required String vehicleRegistration,
    required bool acceptedTerms,
    required bool acceptedHealthData,
  }) onComplete;
  final Future<void> Function(String email, String password) onLogin;
  final ValueChanged<DemoAccountMode> onOpenDemo;

  const WelcomeScreen({
    super.key,
    required this.onComplete,
    required this.onLogin,
    required this.onOpenDemo,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _profileFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _vehicleMakeController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleRegistrationController = TextEditingController();
  String _bloodType = 'Unknown';
  bool _showNationalId = false;
  bool _termsAccepted = false;
  bool _termsError = false;
  bool _healthDataConsent = false;
  int _step = 0;
  bool _requestingPermissions = false;
  bool _settingsNeeded = false;
  String? _permissionMessage;

  Future<void> _openLogin({DemoAccountMode? demoMode}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AccountLoginScreen(
          onLogin: widget.onLogin,
          onOpenDemo: widget.onOpenDemo,
          initialDemoMode: demoMode,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    _vehicleMakeController.dispose();
    _vehicleModelController.dispose();
    _vehicleRegistrationController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    if (_step != 1 || !_termsAccepted) return;
    setState(() => _requestingPermissions = true);
    try {
      await widget.onComplete(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        nationalId: _nationalIdController.text.trim(),
        bloodType: _bloodType,
        vehicleMake: _vehicleMakeController.text.trim(),
        vehicleModel: _vehicleModelController.text.trim(),
        vehicleRegistration: _vehicleRegistrationController.text.trim(),
        acceptedTerms: _termsAccepted,
        acceptedHealthData: _healthDataConsent,
      );
    } catch (error) {
      debugPrint('Onboarding Firestore save failed: $error');
      if (!mounted) return;
      setState(() {
        _requestingPermissions = false;
        _permissionMessage = _profileSaveError(error);
      });
    }
  }

  String _profileSaveError(Object error) {
    final errorText = error.toString().toUpperCase();
    if (errorText.contains('CONFIGURATION_NOT_FOUND')) {
      return 'Firebase Authentication is not configured for roadrescuecut. In Firebase Console, open Authentication, select Get started, then enable Anonymous under Sign-in method.';
    }
    if (error is FirebaseAuthException &&
        error.code == 'operation-not-allowed') {
      return 'Anonymous sign-in is disabled. Enable it in Firebase Console under Authentication sign-in providers.';
    }
    if (error is FirebaseAuthException) {
      return 'Firebase Authentication could not create your session. In Firebase Console, initialize Authentication and enable Anonymous sign-in.';
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Firebase rejected the profile or vehicle write. Deploy the updated Firestore rules and try again.';
    }
    if (error is FirebaseException && error.code == 'unavailable') {
      return 'Firebase is unavailable. Check your connection and try again.';
    }
    if (error is StateError) {
      return 'Firebase is not ready. Check Firebase initialization and try again.';
    }
    return 'Your profile could not be saved to Firebase. Check your connection and try again.';
  }

  Future<void> _requestPermissions() async {
    if (_requestingPermissions || _step != 1) return;
    setState(() {
      _requestingPermissions = true;
      _permissionMessage = null;
      _settingsNeeded = false;
    });

    try {
      final location = await Permission.locationWhenInUse.request();
      final notifications = await Permission.notification.request();
      final statuses = [location, notifications];
      final denied = statuses.any((status) => !status.isGranted);
      final blocked = statuses.any(
        (status) => status.isPermanentlyDenied || status.isRestricted,
      );

      if (denied) {
        if (!mounted) return;
        setState(() {
          _requestingPermissions = false;
          _settingsNeeded = blocked;
          _permissionMessage = blocked
              ? 'A permission is blocked in system settings. You can enable it now or continue and allow it later.'
              : 'You can continue without these permissions and enable them later when you use rescue or alert features.';
        });
        return;
      }

      await _finishOnboarding();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requestingPermissions = false;
        _permissionMessage =
            'Permission setup could not finish. You can retry or continue and allow access later.';
      });
    }
  }

  void _continueToPermissions() {
    if (!(_profileFormKey.currentState?.validate() ?? false)) return;
    if (!_validateTerms()) return;
    setState(() {
      _step = 1;
      _permissionMessage = null;
      _settingsNeeded = false;
    });
  }

  Future<void> _openSettings() async {
    final opened = await openAppSettings();
    if (!opened && mounted) {
      setState(() {
        _permissionMessage =
            'Could not open system settings. You can enable permissions from your device settings.';
      });
    }
  }

  bool _validateTerms() {
    if (_termsAccepted) return true;
    setState(() => _termsError = true);
    return false;
  }

  Widget _permissionRow(IconData icon, String title, String description) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 23, color: C.navy),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: C.dark, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(description,
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8ECFA), C.bg, Color(0xFFE8F8EF)],
            stops: [0, 0.58, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  children: [
                    Row(children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: C.navy,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.car_crash_rounded,
                            color: Colors.white, size: 27),
                      ),
                      const SizedBox(width: 12),
                      const Text('RoadRescue',
                          style: TextStyle(
                              color: C.dark,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 34),
                    Text(
                      _step == 0
                          ? 'Help, when and where you need it.'
                          : 'Set up your permissions.',
                      style: const TextStyle(
                          color: C.dark,
                          fontSize: 30,
                          height: 1.12,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _step == 0
                          ? 'Add your details to set up your rescue profile.'
                          : 'Review what RoadRescue uses. You can allow access now or enable it later in device settings.',
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    if (_step == 0) ...[
                      const Text('Your details',
                          style: TextStyle(
                              color: C.dark,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Form(
                        key: _profileFormKey,
                        child: Column(children: [
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Full name',
                              hintText: 'Your name',
                              prefixIcon:
                                  const Icon(Icons.person_outline_rounded),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              final name = value?.trim() ?? '';
                              if (name.length < 2) {
                                return 'Enter your full name.';
                              }
                              if (name.length > 100) return 'Name is too long.';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Phone number',
                              hintText: '+263 77 123 4567',
                              prefixIcon: const Icon(Icons.phone_outlined),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              final phone = value?.trim() ?? '';
                              final digitCount =
                                  RegExp(r'[0-9]').allMatches(phone).length;
                              if (digitCount < 7 || digitCount > 15) {
                                return 'Enter a valid phone number.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nationalIdController,
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.characters,
                            obscureText: !_showNationalId,
                            decoration: InputDecoration(
                              labelText: 'National ID number',
                              hintText: 'Enter your ID number',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              suffixIcon: IconButton(
                                tooltip: _showNationalId
                                    ? 'Hide ID number'
                                    : 'Show ID number',
                                onPressed: () => setState(
                                    () => _showNationalId = !_showNationalId),
                                icon: Icon(_showNationalId
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              final id = value?.trim() ?? '';
                              if (!RegExp(r'^[A-Za-z0-9/-]{4,32}$')
                                  .hasMatch(id)) {
                                return 'Enter a valid ID number.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _healthDataConsent,
                            activeColor: C.navy,
                            title: const Text(
                                'I explicitly consent to storing my blood type.'),
                            subtitle: const Text(
                                'Blood type is sensitive health data. This is optional and stays on this device in the prototype.'),
                            onChanged: (value) => setState(() {
                              _healthDataConsent = value ?? false;
                              if (!_healthDataConsent) _bloodType = 'Unknown';
                            }),
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: _bloodType,
                            decoration: InputDecoration(
                              labelText: _healthDataConsent
                                  ? 'Blood type'
                                  : 'Blood type (optional)',
                              prefixIcon: const Icon(Icons.bloodtype_outlined),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: const [
                              'Unknown',
                              'A+',
                              'A-',
                              'B+',
                              'B-',
                              'AB+',
                              'AB-',
                              'O+',
                              'O-',
                            ].map((type) {
                              return DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              );
                            }).toList(),
                            onChanged: _healthDataConsent
                                ? (value) {
                                    if (value != null) {
                                      setState(() => _bloodType = value);
                                    }
                                  }
                                : null,
                          ),
                          const SizedBox(height: 24),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Vehicle details',
                                style: TextStyle(
                                    color: C.dark,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _vehicleMakeController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Vehicle make',
                              hintText: 'e.g. Toyota',
                              prefixIcon:
                                  const Icon(Icons.directions_car_outlined),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              final make = value?.trim() ?? '';
                              if (make.isEmpty) {
                                return 'Enter the vehicle make.';
                              }
                              if (make.length > 80) return 'Make is too long.';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _vehicleModelController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Vehicle model',
                              hintText: 'e.g. Corolla',
                              prefixIcon: const Icon(Icons.car_repair_outlined),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              final model = value?.trim() ?? '';
                              if (model.isEmpty) {
                                return 'Enter the vehicle model.';
                              }
                              if (model.length > 80) {
                                return 'Model is too long.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _vehicleRegistrationController,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Registration number',
                              hintText: 'Vehicle plate',
                              prefixIcon: const Icon(Icons.pin_outlined),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              final registration = value?.trim() ?? '';
                              if (registration.isEmpty) {
                                return 'Enter the registration number.';
                              }
                              if (registration.length > 32) {
                                return 'Registration number is too long.';
                              }
                              return null;
                            },
                          ),
                        ]),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _termsError
                                ? const Color(0xFFB42318)
                                : const Color(0xFFE2E5EF),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Terms & conditions',
                                style: TextStyle(
                                    color: C.dark,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            const Text(
                              'Keep your details accurate. Your profile and vehicle details are saved to your RoadRescue Firebase account. When an alert is registered, your name, phone, vehicle details, and current location are included. Blood type is optional, separately consented to, and stored only in your account. This prototype does not forward alerts to emergency services or contacts.',
                              style:
                                  TextStyle(color: Colors.black54, height: 1.4),
                            ),
                            Material(
                              color: Colors.transparent,
                              child: CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: _termsAccepted,
                                activeColor: C.navy,
                                title: const Text('I have read and agree.'),
                                onChanged: (value) => setState(() {
                                  _termsAccepted = value ?? false;
                                  _termsError = false;
                                }),
                              ),
                            ),
                            if (_termsError)
                              const Text(
                                'Accept the terms to continue.',
                                style: TextStyle(
                                    color: Color(0xFFB42318), fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (_step == 1) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _requestingPermissions
                              ? null
                              : () => setState(() {
                                    _step = 0;
                                    _permissionMessage = null;
                                  }),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Back to details'),
                        ),
                      ),
                      const Text('Permissions',
                          style: TextStyle(
                              color: C.dark,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      _permissionRow(
                        Icons.location_on_outlined,
                        'Location while using the app',
                        'Shares your position with a rescue request and helps find nearby assistance.',
                      ),
                      const Divider(height: 1),
                      _permissionRow(
                        Icons.notifications_none_rounded,
                        'Notifications',
                        'Provides updates about rescue requests and important vehicle alerts.',
                      ),
                      const Divider(height: 1),
                      _permissionRow(
                        Icons.description_outlined,
                        'Provider documents',
                        'Camera or photo access is requested only when you attach provider verification documents.',
                      ),
                      if (_permissionMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1DE),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(_permissionMessage!,
                              style:
                                  const TextStyle(color: C.dark, height: 1.4)),
                        ),
                        if (_settingsNeeded) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _openSettings,
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('Open Settings'),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: _requestingPermissions
                          ? null
                          : _step == 0
                              ? _continueToPermissions
                              : _permissionMessage == null
                                  ? _requestPermissions
                                  : _finishOnboarding,
                      style: FilledButton.styleFrom(
                        backgroundColor: C.navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: _requestingPermissions
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_step == 0
                              ? 'Continue'
                              : _permissionMessage == null
                                  ? 'Allow & Continue'
                                  : 'Continue to RoadRescue'),
                    ),
                    if (_step == 1 && _permissionMessage != null)
                      TextButton(
                        onPressed:
                            _requestingPermissions ? null : _requestPermissions,
                        child: const Text('Try permissions again'),
                      ),
                    if (_step == 0) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _openLogin,
                        child: const Text('Already have an account? Log in'),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Try a demo account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: C.dark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _openLogin(demoMode: DemoAccountMode.motorist),
                              icon: const Icon(Icons.directions_car_outlined),
                              label: const Text('Motorist demo'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _openLogin(demoMode: DemoAccountMode.provider),
                              icon: const Icon(Icons.handyman_outlined),
                              label: const Text('Provider demo'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
