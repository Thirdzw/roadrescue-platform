import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../models/emergency_contact.dart';
import '../services/firestore_service.dart';
import '../widgets/common_widgets.dart';
import 'emergency_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<List<EmergencyContact>> _contactsStream;
  late final Future<String> _userIdFuture;

  @override
  void initState() {
    super.initState();
    _contactsStream = FirestoreService().watchEmergencyContacts();
    _userIdFuture = FirestoreService().currentUserId();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _addEmergencyContact() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const _EmergencyContactForm(),
      );

  Future<void> _copyUserId(String userId) async {
    await Clipboard.setData(ClipboardData(text: userId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('RoadRescue ID copied')),
    );
  }

  Widget info(String v, String l) => Expanded(
        child: Column(children: [
          Text(v,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: C.dark)),
          const SizedBox(height: 4),
          Text(l, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );

  Widget tip(IconData i, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(i, color: C.navy, size: 22),
          const SizedBox(width: 12),
          Expanded(
              child: Text(t,
                  style: const TextStyle(
                      fontSize: 14, height: 1.3, color: C.dark))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return page(const Color(0xFFE6E9F8), [
      heading('Safety', 'Your contacts and crash protection'),
      card(ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
            backgroundColor: C.navy.withValues(alpha: 0.12),
            child: const Icon(Icons.car_crash_rounded, color: C.navy)),
        title: const Text('Crash detection settings',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15, color: C.dark)),
        subtitle: const Text(
            'Optional and off by default. Detected crashes start a cancellable call countdown.'),
        trailing: IconButton(
          tooltip: 'Open emergency settings',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const EmergencySettingsScreen()),
          ),
          icon: const Icon(Icons.settings_outlined, color: C.navy),
        ),
      )),
      sectionTitle('Medical ID'),
      card(Row(children: [
        info('O+', 'Blood type'),
        info('None', 'Allergies'),
        info('AEB 1234', 'Plate'),
      ])),
      sectionTitle('Circle ID'),
      card(
        FutureBuilder<String>(
          future: _userIdFuture,
          builder: (context, snapshot) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_rounded, color: C.navy),
            title: const Text('Your RoadRescue user ID'),
            subtitle: snapshot.hasError
                ? const Text('Could not load your ID.')
                : snapshot.hasData
                    ? SelectableText(snapshot.data!)
                    : const Text('Loading…'),
            trailing: snapshot.hasData
                ? IconButton(
                    tooltip: 'Copy RoadRescue ID',
                    onPressed: () => _copyUserId(snapshot.data!),
                    icon: const Icon(Icons.copy_rounded),
                  )
                : null,
          ),
        ),
      ),
      sectionTitle('Emergency contacts and Circle members',
          trailing: TextButton.icon(
            onPressed: _addEmergencyContact,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add'),
            style: TextButton.styleFrom(foregroundColor: C.navy),
          )),
      StreamBuilder<List<EmergencyContact>>(
        stream: _contactsStream,
        builder: (context, snapshot) {
          final contacts = snapshot.data ?? const <EmergencyContact>[];
          return card(
            Column(children: [
              if (snapshot.hasError)
                const ListTile(
                  leading: Icon(Icons.error_outline_rounded, color: C.sosDark),
                  title: Text('Could not load emergency contacts'),
                  subtitle: Text('Check your connection and try again.'),
                )
              else if (!snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (contacts.isEmpty)
                const ListTile(
                  leading: Icon(Icons.contact_phone_outlined, color: C.navy),
                  title: Text('No emergency contacts yet'),
                  subtitle:
                      Text('Add someone you trust to contact in an emergency.'),
                )
              else
                for (final contact in contacts)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: CircleAvatar(
                      backgroundColor: C.navy.withValues(alpha: 0.12),
                      child: Text(
                        contact.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                            color: C.navy, fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text(contact.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: C.dark)),
                    subtitle: Text(
                      '${contact.type == ContactType.circleMember ? 'Circle member' : contact.relationship.isEmpty ? 'Emergency contact' : contact.relationship} | ${contact.phone}${contact.userId == null ? '' : ' | App user linked'}',
                    ),
                  ),
            ]),
            p: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          );
        },
      ),
      sectionTitle('If you break down'),
      card(Column(children: [
        tip(Icons.warning_amber_rounded, 'Switch on your hazard lights'),
        tip(Icons.directions_car_filled_rounded,
            'Move to the side of the road if it is safe'),
        tip(Icons.person_pin_circle_rounded,
            'Stay in the car and share your location'),
      ])),
    ]);
  }
}

class _EmergencyContactForm extends StatefulWidget {
  const _EmergencyContactForm();

  @override
  State<_EmergencyContactForm> createState() => _EmergencyContactFormState();
}

class _EmergencyContactFormState extends State<_EmergencyContactForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _phoneController = TextEditingController();
  final _userIdController = TextEditingController();
  bool _saving = false;
  String? _error;
  ContactType _type = ContactType.emergencyContact;

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _phoneController.dispose();
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FirestoreService().addEmergencyContact(
        name: _nameController.text,
        relationship: _relationshipController.text,
        phone: _phoneController.text,
        type: _type,
        userId: _userIdController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save contact. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                24, 12, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Add safety contact',
                        style: TextStyle(
                            color: C.dark,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<ContactType>(
                      value: _type,
                      decoration: const InputDecoration(
                        labelText: 'Contact type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ContactType.emergencyContact,
                          child: Text('Emergency contact'),
                        ),
                        DropdownMenuItem(
                          value: ContactType.circleMember,
                          child: Text('Circle member'),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) setState(() => _type = value);
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a name'
                              : value.trim().length > 100
                                  ? 'Name must be 100 characters or less'
                                  : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _relationshipController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Relationship (optional)',
                        prefixIcon: Icon(Icons.people_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value != null && value.length > 64
                          ? 'Use 64 characters or less'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      maxLength: 32,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final phone = value?.trim() ?? '';
                        final digits = phone.replaceAll(RegExp(r'\D'), '');
                        if (digits.length < 7 || digits.length > 15) {
                          return 'Enter a valid phone number';
                        }
                        if (!RegExp(r'^\+?[0-9\s().-]+$').hasMatch(phone)) {
                          return 'Use digits and standard phone punctuation';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _userIdController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'RoadRescue user ID (optional)',
                        helperText:
                            'Enter a Circle member UID. They must also link your UID for push alerts.',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final userId = value?.trim() ?? '';
                        if (userId.isEmpty) return null;
                        if (userId.length > 128) {
                          return 'User ID must be 128 characters or less';
                        }
                        if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(userId)) {
                          return 'Enter a valid RoadRescue user ID';
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(_error!, style: const TextStyle(color: C.sosDark)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(_saving ? 'Saving…' : 'Save contact'),
                        style: FilledButton.styleFrom(backgroundColor: C.navy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
