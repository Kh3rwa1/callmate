import 'package:flutter/material.dart';
import 'package:callpilot/services/contacts/contacts_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

class _FakeContacts implements ContactsSource {
  _FakeContacts({this.allow = true});
  bool allow;
  int settingsOpened = 0;
  int requests = 0;

  @override
  Future<bool> requestAccess() async {
    requests++;
    return allow;
  }

  @override
  Future<List<PhoneContact>> load() async => dedupeContacts(const [
    ('Ramesh Gupta', '98300 11111'),
    ('Sunita Devi', '+91 97480 22222'),
    ('Sunita Devi (2)', '9748022222'), // same number again
    ('Landline', '033 2222 3333'), // not a mobile
    ('', '9007733333'), // no name
  ]);

  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  test('dedupeContacts keeps Indian mobiles once, sorted by name', () {
    final list = dedupeContacts(const [
      ('Zed', '9830011111'),
      ('amit', '+919830022222'),
      ('Amit again', '09830022222'),
      ('Office', '033 4000 5000'),
    ]);
    expect(list.map((c) => c.name), ['amit', 'Zed']);
    expect(list.first.phone, '919830022222');
  });

  late _FakeContacts fake;

  appTest(
    'owner picks contacts and adds them as customers',
    (h) async {
      final before = h.backend.leads.length;
      await h.push('/leads/contacts');
      await h.tapText('I agree, continue');
      expect(find.text('Ramesh Gupta'), findsOneWidget);
      expect(find.text('Sunita Devi'), findsOneWidget);
      expect(find.text('Sunita Devi (2)'), findsNothing);
      expect(find.text('Landline'), findsNothing);

      await h.tapText('Ramesh Gupta');
      await h.tapText('Sunita Devi');
      await h.tapText('Add 2 customers');
      expect(h.backend.leads.length, before + 2);
      expect(find.text('2 customers imported'), findsOneWidget);
    },
    overrides: () => [
      contactsSourceProvider.overrideWithValue(fake = _FakeContacts()),
    ],
  );

  appTest(
    'search narrows the list; select all picks what is shown',
    (h) async {
      await h.push('/leads/contacts');
      await h.tapText('I agree, continue');
      await h.tester.enterText(find.byType(TextField), 'sun');
      await h.settle(2);
      expect(find.text('Ramesh Gupta'), findsNothing);
      await h.tapText('Select all');
      expect(find.text('Add 1 customer'), findsOneWidget);
    },
    overrides: () => [
      contactsSourceProvider.overrideWithValue(fake = _FakeContacts()),
    ],
  );

  appTest(
    'without permission it explains and links to settings',
    (h) async {
      await h.push('/leads/contacts');
      await h.tapText('I agree, continue');
      expect(find.text('Allow contacts'), findsOneWidget);
      await h.tapText('Open settings');
      expect(fake.settingsOpened, 1);
      fake.allow = true;
      await h.tapText('Allow access');
      expect(find.text('Ramesh Gupta'), findsOneWidget);
    },
    overrides: () => [
      contactsSourceProvider.overrideWithValue(
        fake = _FakeContacts(allow: false),
      ),
    ],
  );

  appTest(
    'explains what is read and sent before asking Android',
    (h) async {
      await h.push('/leads/contacts');
      expect(find.text('Before we open your contacts'), findsOneWidget);
      expect(fake.requests, 0);
      expect(h.prefs.contactsConsent, isFalse);

      await h.tapText('Not now');
      expect(fake.requests, 0);
      expect(h.location, isNot('/leads/contacts'));
    },
    overrides: () => [
      contactsSourceProvider.overrideWithValue(fake = _FakeContacts()),
    ],
  );

  appTest(
    'agreeing asks Android once and is remembered',
    (h) async {
      await h.push('/leads/contacts');
      await h.tapText('I agree, continue');
      expect(fake.requests, 1);
      expect(h.prefs.contactsConsent, isTrue);
      expect(find.text('Ramesh Gupta'), findsOneWidget);
    },
    overrides: () => [
      contactsSourceProvider.overrideWithValue(fake = _FakeContacts()),
    ],
  );

  appTest(
    'once agreed, the next visit goes straight to the list',
    (h) async {
      await h.prefs.setContactsConsent(true);
      await h.push('/leads/contacts');
      expect(find.text('Before we open your contacts'), findsNothing);
      expect(find.text('Ramesh Gupta'), findsOneWidget);
      expect(fake.requests, 1);
    },
    overrides: () => [
      contactsSourceProvider.overrideWithValue(fake = _FakeContacts()),
    ],
  );

  appTest(
    'add customers screen offers phone contacts first',
    (h) async {
      await h.push('/leads/import');
      expect(find.text('From phone contacts'), findsOneWidget);
      await h.tapText('Choose from contacts');
      expect(h.location, '/leads/contacts');
    },
    overrides: () => [
      contactsSourceProvider.overrideWithValue(_FakeContacts()),
    ],
  );
}
