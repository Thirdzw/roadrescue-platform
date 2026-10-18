import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact.dart';

class TestConfig {
  TestConfig._();

  static const _contactsKey = 'debug_crash_test_contacts';
  static const _enabledKey = 'debug_crash_test_mode';
  static bool _on = true;
  static List<Contact> _testContacts = const [];

  static bool get enabled => kDebugMode && _on;
  static List<Contact> get testContacts => List.unmodifiable(_testContacts);

  static Future<void> set(bool value) async {
    if (!kDebugMode) return;
    _on = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
  }

  static Future<void> loadContacts() async {
    if (!kDebugMode) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    _on = preferences.getBool(_enabledKey) ?? true;
    final encoded = preferences.getString(_contactsKey);
    if (encoded == null) {
      _testContacts = const [];
      return;
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Debug test contacts must be a list.');
    }
    _testContacts = decoded
        .whereType<Map>()
        .map(
          (data) => Contact.fromMap(
            data['id'] as String? ?? '',
            Map<String, dynamic>.from(data),
          ),
        )
        .toList(growable: false);
  }

  static Future<void> addContact(Contact contact) async {
    _requireDebugBuild();
    if (contact.name.trim().isEmpty || contact.phone.trim().isEmpty) {
      throw ArgumentError('Test contact name and phone are required.');
    }
    final id = contact.id.trim().isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : contact.id.trim();
    _testContacts = [
      ..._testContacts.where((item) => item.id != id),
      Contact(
        id: id,
        name: contact.name.trim(),
        phone: contact.phone.trim(),
        type: contact.type,
        userId: contact.userId?.trim().isEmpty == true
            ? null
            : contact.userId?.trim(),
        relationship: contact.relationship,
      ),
    ];
    await _saveContacts();
  }

  static Future<void> removeContact(String id) async {
    _requireDebugBuild();
    _testContacts =
        _testContacts.where((contact) => contact.id != id).toList();
    await _saveContacts();
  }

  static void _requireDebugBuild() {
    if (!kDebugMode) {
      throw UnsupportedError('Crash test contacts are debug-build only.');
    }
  }

  static Future<void> _saveContacts() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _contactsKey,
      jsonEncode(
        _testContacts
            .map((contact) => {'id': contact.id, ...contact.toMap()})
            .toList(growable: false),
      ),
    );
  }
}
