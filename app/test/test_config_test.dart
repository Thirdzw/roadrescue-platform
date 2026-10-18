import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadrescue/models/contact.dart';
import 'package:roadrescue/services/test_config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('test mode setting persists and is reloaded', () async {
    await TestConfig.set(false);
    await TestConfig.loadContacts();
    expect(TestConfig.enabled, isFalse);

    await TestConfig.set(true);
    await TestConfig.loadContacts();
    expect(TestConfig.enabled, isTrue);
  });

  test('test contacts persist locally and can be removed', () async {
    await TestConfig.loadContacts();
    final contact = Contact(
      id: '',
      name: 'Debug tester',
      phone: '+15555550123',
      type: ContactType.circleMember,
      userId: 'debug-circle-user',
    );

    await TestConfig.addContact(contact);
    await TestConfig.loadContacts();

    expect(TestConfig.testContacts, hasLength(1));
    expect(TestConfig.testContacts.single.name, 'Debug tester');
    expect(TestConfig.testContacts.single.phone, '+15555550123');
    expect(TestConfig.testContacts.single.userId, 'debug-circle-user');

    await TestConfig.removeContact(TestConfig.testContacts.single.id);
    await TestConfig.loadContacts();
    expect(TestConfig.testContacts, isEmpty);
  });
}
