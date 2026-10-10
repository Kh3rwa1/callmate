import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/phone.dart';

/// One person from the phone's address book, with an Indian mobile number.
class PhoneContact {
  const PhoneContact({required this.name, required this.phone});
  final String name;

  /// Normalised digits, e.g. "919876543210".
  final String phone;
}

/// Reads the owner's phone contacts so they can pick customers from them,
/// instead of preparing a CSV file.
abstract class ContactsSource {
  /// Asks for (or confirms) read access. True when granted.
  Future<bool> requestAccess();

  /// Everyone with at least one valid Indian mobile number, sorted by name,
  /// one entry per number (no duplicates).
  Future<List<PhoneContact>> load();

  /// Opens the system settings page for this app.
  Future<void> openSettings();
}

/// The real address book (flutter_contacts).
class DeviceContactsSource implements ContactsSource {
  const DeviceContactsSource();

  @override
  Future<bool> requestAccess() async {
    final status = await fc.FlutterContacts.permissions.request(
      fc.PermissionType.read,
    );
    return status == fc.PermissionStatus.granted ||
        status == fc.PermissionStatus.limited;
  }

  @override
  Future<List<PhoneContact>> load() async {
    final all = await fc.FlutterContacts.getAll(
      properties: {fc.ContactProperty.phone},
    );
    return dedupeContacts([
      for (final c in all)
        for (final p in c.phones) (c.displayName ?? '', p.number),
    ]);
  }

  @override
  Future<void> openSettings() => fc.FlutterContacts.permissions.openSettings();
}

/// Keeps entries with a valid Indian mobile (a business only ever calls
/// those), drops repeats of the same number and sorts by name. Contacts
/// without a name show their number instead.
List<PhoneContact> dedupeContacts(Iterable<(String, String)> raw) {
  final seen = <String>{};
  final out = <PhoneContact>[];
  for (final (name, number) in raw) {
    final n = PhoneUtils.normalize(number);
    if (n == null || !n.startsWith('91') || !seen.add(n)) continue;
    final clean = name.trim();
    out.add(
      PhoneContact(
        name: clean.isEmpty ? PhoneUtils.display(n) : clean,
        phone: n,
      ),
    );
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

final contactsSourceProvider = Provider<ContactsSource>(
  (_) => const DeviceContactsSource(),
);
