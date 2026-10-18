import 'package:flutter/material.dart';

import '../models/emergency_data.dart';
import '../models/emergency_location_context.dart';
import '../services/emergency_call_service.dart';
import '../services/emergency_data_service.dart';
import '../services/emergency_help_service.dart';
import '../services/emergency_settings_service.dart';
import '../widgets/common_widgets.dart';
import 'emergency_countdown_screen.dart';

class EmergencyHelpScreen extends StatefulWidget {
  const EmergencyHelpScreen({super.key});

  @override
  State<EmergencyHelpScreen> createState() => _EmergencyHelpScreenState();
}

class _EmergencyHelpScreenState extends State<EmergencyHelpScreen> {
  EmergencyData? _data;
  EmergencyLocationContext? _location;
  String? _loadError;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _location = null;
      _locating = true;
    });
    try {
      final data = await EmergencyDataService.instance.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _location = const EmergencyLocationContext(
          locationError: 'Getting location...',
        );
      });
      final location = await EmergencyHelpService.instance.locate(data);
      if (mounted) {
        setState(() {
          _location = location;
          _locating = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error.toString();
          _locating = false;
        });
      }
    }
  }

  Future<void> _call(Contact contact, String sourceNumber,
      EmergencyLocationContext location, String triggerType) async {
    final number = ZimbabwePhoneNumberNormalizer.normalize(sourceNumber);
    if (number == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('This number cannot be dialled in a standard format.')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmergencyCountdownScreen(
          number: number,
          contactName: contact.name,
          triggerType: triggerType,
          location: location,
        ),
      ),
    );
  }

  Future<void> _shareLocation(EmergencyLocationContext location) async {
    if (location.position == null) return;
    final dryRun = EmergencySettingsService.instance.dryRunEnabled;
    final message = EmergencyCallService.locationMessage(location);
    await EmergencyCallService.openSmsComposer(
      context: location,
      dryRun: dryRun,
    );
    if (!mounted) return;
    if (dryRun) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Dry-run message'),
          content: SelectableText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _phoneButton(
    Contact contact,
    String sourceNumber,
    EmergencyLocationContext location,
    String triggerType,
  ) {
    final number = ZimbabwePhoneNumberNormalizer.normalize(sourceNumber);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Expanded(
          child: SelectableText(sourceNumber,
              style: const TextStyle(
                  color: C.dark, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: number == null
                ? null
                : () => _call(contact, sourceNumber, location, triggerType),
            icon: const Icon(Icons.call_rounded, size: 17),
            label: const Text('Call'),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.navy,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _contactCard(
    Contact contact,
    EmergencyLocationContext location,
    String triggerType,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: card(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(contact.name,
                style: const TextStyle(
                    color: C.dark, fontWeight: FontWeight.w800, fontSize: 15)),
            if (contact.address != null) ...[
              const SizedBox(height: 3),
              Text(contact.address!,
                  style: const TextStyle(color: Colors.black54, height: 1.35)),
            ],
            if (contact.note != null) ...[
              const SizedBox(height: 3),
              Text(contact.note!,
                  style: const TextStyle(color: Colors.black54, height: 1.35)),
            ],
            for (final phone in contact.phones)
              _phoneButton(contact, phone, location, triggerType),
          ]),
          p: const EdgeInsets.all(14),
        ),
      );

  Widget _section(
    String title,
    List<Contact> contacts,
    EmergencyLocationContext location,
    String triggerType,
  ) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionTitle(title),
        if (contacts.isEmpty)
          card(const Text(
              'No local number is listed. Try the national line 999.',
              style: TextStyle(color: Colors.black54, height: 1.4)))
        else
          for (final contact in contacts)
            _contactCard(contact, location, triggerType),
      ]);

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final location = _location;
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency help')),
      body: data == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Emergency numbers could not be loaded.'),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                if (_locating) const LinearProgressIndicator(),
                if (location != null) ...[
                  Text(
                    location.nearbyCity?.name ?? 'Zimbabwe emergency numbers',
                    style: const TextStyle(
                        color: C.dark,
                        fontSize: 22,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(location.helpNotice,
                      style:
                          const TextStyle(color: Colors.black54, height: 1.4)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: location.position == null
                          ? null
                          : () => _shareLocation(location),
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('Share my location'),
                      style: FilledButton.styleFrom(
                        backgroundColor: C.navy,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (location.position == null && !_locating) ...[
                    const SizedBox(height: 8),
                    Text(location.locationError ?? 'Location is unavailable.',
                        style: const TextStyle(color: C.sosDark)),
                  ],
                  sectionTitle('National emergency numbers'),
                  for (final contact in data.national)
                    _contactCard(contact, location, 'national_help'),
                  if (location.nearbyCity != null) ...[
                    _section(
                      'Ambulance',
                      location.nearbyCity!.ambulance,
                      location,
                      'ambulance',
                    ),
                    _section(
                      'Police',
                      [
                        ...location.nearbyCity!.police,
                        ...data.national.where((c) => c.name == 'Police'),
                      ],
                      location,
                      'police',
                    ),
                    _section(
                      'Fire',
                      [
                        ...location.nearbyCity!.fire,
                        ...data.national
                            .where((c) => c.name == 'Fire Department'),
                      ],
                      location,
                      'fire',
                    ),
                    _section('Road assistance', data.roadAssistance, location,
                        'road_assistance'),
                    _section('Hospitals / 24hr trauma',
                        location.nearbyCity!.hospitals, location, 'hospital'),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'RoadRescue helps connect you to services. It does not replace calling emergency services. Numbers may change.',
                    style: TextStyle(color: Colors.black54, height: 1.45),
                  ),
                ],
              ],
            ),
    );
  }
}
