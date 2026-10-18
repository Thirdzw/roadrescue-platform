import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logic/crash_controller.dart';
import '../models/contact.dart';
import '../services/emergency_settings_service.dart';
import '../services/location_service.dart';
import '../services/test_config.dart';
import '../services/demo_session.dart';
import '../widgets/common_widgets.dart';

class EmergencySettingsScreen extends StatefulWidget {
  const EmergencySettingsScreen({super.key});

  @override
  State<EmergencySettingsScreen> createState() =>
      _EmergencySettingsScreenState();
}

class _EmergencySettingsScreenState extends State<EmergencySettingsScreen> {
  final _settings = EmergencySettingsService.instance;
  final _testNameController = TextEditingController();
  final _testPhoneController = TextEditingController();
  final _testUserIdController = TextEditingController();
  bool _loading = true;
  ContactType _testContactType = ContactType.emergencyContact;

  @override
  void initState() {
    super.initState();
    _load();
    _settings.addListener(_refresh);
  }

  Future<void> _load() async {
    await _settings.load();
    if (kDebugMode && !DemoSession.instance.isActive) {
      await TestConfig.loadContacts();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    _testNameController.dispose();
    _testPhoneController.dispose();
    _testUserIdController.dispose();
    super.dispose();
  }

  Future<void> _addTestContact() async {
    try {
      await TestConfig.addContact(
        Contact(
          id: '',
          name: _testNameController.text,
          phone: _testPhoneController.text,
          type: _testContactType,
          userId: _testContactType == ContactType.circleMember
              ? _testUserIdController.text
              : null,
        ),
      );
      _testNameController.clear();
      _testPhoneController.clear();
      _testUserIdController.clear();
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save test contact: $error')),
      );
    }
  }

  Future<void> _removeTestContact(String id) async {
    try {
      await TestConfig.removeContact(id);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove test contact: $error')),
      );
    }
  }

  Future<void> _simulateCrash() async {
    try {
      await CrashController.instance.simulateCrash();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not simulate crash: $error')),
      );
    }
  }

  Future<void> _setAutoCrash(bool value) async {
    if (value) {
      await _settings.setAutoCrashDetectionEnabled(true);
      try {
        await CrashController.instance.start();
      } catch (error) {
        await _settings.setAutoCrashDetectionEnabled(false);
        debugPrint('Enabling crash detection failed: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Crash detection could not start: $error')),
          );
        }
      }
    } else {
      if (CrashController.instance.state == CrashState.awaitingResponse) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Crash monitoring cannot stop while an alert is pending.',
              ),
            ),
          );
        }
        return;
      }
      await CrashController.instance.stop();
      await _settings.setAutoCrashDetectionEnabled(false);
    }
  }

  Future<void> _setDirectCall(bool value) async {
    if (value && !DemoSession.instance.isActive) {
      final permission = await Permission.phone.request();
      if (!permission.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Phone permission is required for direct calls.')),
          );
        }
        return;
      }
    }
    await _settings.setDirectCallEnabled(value);
  }

  Future<void> _setCrashSoundCue(bool value) async {
    if (value && !DemoSession.instance.isActive) {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Microphone permission is optional and was not enabled.',
              ),
            ),
          );
        }
        return;
      }
    }
    await _settings.setCrashSoundDetectionEnabled(value);
    await CrashController.instance.setSoundCueEnabled(value);
  }

  Future<void> _setTripTracking(bool value) async {
    if (!value && _settings.isTripActive) {
      await _settings.endTrip();
      await LocationService.instance.stopTracking();
    }
    await _settings.setTripTrackingEnabled(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Emergency settings')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const Text(
                    'Crash detection uses background location to estimate speed, a persistent notification to stay active, and SMS permission to contact your saved emergency contacts. Lock-screen alerts depend on Android notification settings. Some phone brands also require enabling autostart or removing battery restrictions for RoadRescue.',
                    style: TextStyle(color: Colors.black54, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  card(Column(children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Automatic crash detection'),
                      subtitle: const Text(
                          'Android only. The foreground service monitors phone sensors while the screen is off. High-evidence crashes use a 10-second response countdown; other confirmed candidates use 30 seconds.'),
                      value: _settings.autoCrashDetectionEnabled,
                      onChanged: DemoSession.instance.isActive ||
                              defaultTargetPlatform == TargetPlatform.android
                          ? _setAutoCrash
                          : null,
                    ),
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Optional sound impact cue'),
                      subtitle: const Text(
                        'Uses microphone level only while the app is open. Audio is analyzed on-device and is not saved or sent. Crash confirmation does not depend on this cue.',
                      ),
                      value: _settings.crashSoundDetectionEnabled,
                      onChanged: DemoSession.instance.isActive ||
                              defaultTargetPlatform == TargetPlatform.android
                          ? _setCrashSoundCue
                          : null,
                    ),
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Direct call after countdown'),
                      subtitle: const Text(
                          'Android only. Places the call without opening the dialer and requires Phone permission. Off means RoadRescue opens the dialer for confirmation.'),
                      value: (DemoSession.instance.isActive ||
                              defaultTargetPlatform == TargetPlatform.android) &&
                          _settings.directCallEnabled,
                      onChanged: DemoSession.instance.isActive ||
                              defaultTargetPlatform == TargetPlatform.android
                          ? _setDirectCall
                          : null,
                    ),
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dry-run mode'),
                        subtitle: const Text(kDebugMode
                          ? 'Always on in debug builds. Shows the exact number and message without opening phone or messaging apps.'
                          : 'Shows the exact number and message without opening phone or messaging apps.'),
                      value: _settings.dryRunEnabled,
                      onChanged:
                          kDebugMode ? null : _settings.setDryRunEnabled,
                    ),
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Allow trip tracking'),
                      subtitle: const Text(
                          'Location is requested only while RoadRescue is open. It is tracked only during a trip you explicitly start.'),
                      value: _settings.tripTrackingEnabled,
                      onChanged: _setTripTracking,
                    ),
                  ])),
                  if (DemoSession.instance.isActive) ...[
                    const SizedBox(height: 18),
                    card(Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'DEMO SIMULATION',
                          style: TextStyle(
                            color: C.navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Try the crash-response countdown with sample data. '
                          'No sensors, calls, SMS or push alerts are used.',
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: CrashController.instance.isRunning
                              ? _simulateCrash
                              : null,
                          icon: const Icon(Icons.car_crash),
                          label: const Text('Simulate crash response'),
                        ),
                      ],
                    )),
                  ],
                  if (kDebugMode && !DemoSession.instance.isActive) ...[
                    const SizedBox(height: 18),
                    card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'DEBUG TESTING ONLY',
                            style: TextStyle(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Test mode'),
                            subtitle: const Text(
                              'Prefixes test messages and limits simulated alerts to the contacts listed below. This control and test mode are absent from release builds.',
                            ),
                            value: TestConfig.enabled,
                            onChanged: (value) async {
                              await CrashController.instance
                                  .setTestMode(value);
                              setState(() {});
                            },
                          ),
                          const Text(
                            'Enter tester details on this device. They are stored locally for debug builds only and are not compiled into source.',
                          ),
                          const SizedBox(height: 12),
                          for (final contact in TestConfig.testContacts)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(contact.name),
                              subtitle: Text(
                                '${contact.phone} · ${contact.type.name}'
                                '${contact.userId == null ? '' : ' · ${contact.userId}'}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Remove test contact',
                                onPressed: () =>
                                    _removeTestContact(contact.id),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          TextField(
                            controller: _testNameController,
                            decoration:
                                const InputDecoration(labelText: 'Tester name'),
                          ),
                          TextField(
                            controller: _testPhoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Tester phone number',
                            ),
                          ),
                          DropdownButtonFormField<ContactType>(
                            initialValue: _testContactType,
                            decoration: const InputDecoration(
                              labelText: 'Contact type',
                            ),
                            items: ContactType.values
                                .map(
                                  (type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type.name),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (type) {
                              if (type != null) {
                                setState(() => _testContactType = type);
                              }
                            },
                          ),
                          if (_testContactType == ContactType.circleMember)
                            TextField(
                              controller: _testUserIdController,
                              decoration: const InputDecoration(
                                labelText: 'Circle member RoadRescue user ID',
                              ),
                            ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _addTestContact,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Add local test contact'),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: TestConfig.enabled &&
                                    TestConfig.testContacts.isNotEmpty &&
                                    CrashController.instance.isRunning &&
                                    CrashController.instance.state !=
                                        CrashState.awaitingResponse
                                ? _simulateCrash
                                : null,
                            icon: const Icon(Icons.car_crash),
                            label: const Text('Simulate crash (TEST)'),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Starts a short test countdown and uses these test recipients only. Crash monitoring must already be enabled. SMS may incur carrier charges; test Circle pushes require valid, mutually linked Circle user IDs.',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'Emergency numbers and approximate city coordinates are bundled for offline use. They are marked unverified; confirm them before relying on them.',
                    style: TextStyle(color: Colors.black54, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'RoadRescue is a safety aid, not a guaranteed safety system. Sensor accuracy, device settings, network coverage, and emergency contact availability may affect alerts. Keep your phone secure and contact emergency services directly when possible.',
                    style: TextStyle(color: Colors.black54, height: 1.45),
                  ),
                ],
              ),
      );
}
