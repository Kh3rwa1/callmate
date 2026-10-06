import '../../data/models/lead.dart';
import 'phone.dart';

/// Minimal RFC-4180-ish CSV parser + lead sanitiser (no extra dependency).
class CsvLeadParser {
  const CsvLeadParser._();

  static const maxRows = 5000;
  static const _maxField = 120;

  static List<List<String>> parse(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',' || c == ';' || c == '\t') {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }
    row.add(field.toString());
    if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  /// Strip control chars, formula-injection prefixes and HTML-ish brackets.
  static String sanitize(String v) {
    var s = v.replaceAll(RegExp(r'[\x00-\x1F\x7F<>]'), ' ').trim();
    while (s.isNotEmpty && '=+-@'.contains(s[0])) {
      s = s.substring(1).trim();
    }
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.length > _maxField ? s.substring(0, _maxField) : s;
  }

  static CsvLeadParseResult toLeads(String csv) {
    final rows = parse(csv);
    if (rows.isEmpty) return const CsvLeadParseResult(leads: [], skipped: 0, errors: ['The file is empty.']);

    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    int find(List<String> keys) => header.indexWhere((h) => keys.any((k) => h.contains(k)));
    var nameIdx = find(['name', 'customer', 'student', 'client']);
    var phoneIdx = find(['phone', 'mobile', 'contact', 'number', 'whatsapp']);
    final interestIdx = find(['interest', 'course', 'service', 'product', 'property', 'model', 'program']);
    final sourceIdx = find(['source', 'channel', 'campaign']);

    var dataRows = rows.skip(1);
    if (nameIdx < 0 && phoneIdx < 0) {
      // No header row – assume name, phone, interest.
      nameIdx = 0;
      phoneIdx = 1;
      dataRows = rows;
    }

    final leads = <NewLeadInput>[];
    final seen = <String>{};
    final errors = <String>[];
    var skipped = 0;
    var line = 1;
    for (final r in dataRows.take(maxRows)) {
      line++;
      String at(int i) => i >= 0 && i < r.length ? sanitize(r[i]) : '';
      final phone = PhoneUtils.normalize(at(phoneIdx));
      final name = at(nameIdx);
      if (phone == null) {
        skipped++;
        if (errors.length < 5) errors.add('Row $line: invalid phone number');
        continue;
      }
      if (!seen.add(phone)) {
        skipped++;
        continue;
      }
      leads.add(
        NewLeadInput(
          name: name.isEmpty ? 'Lead ${PhoneUtils.masked(phone)}' : name,
          phone: phone,
          interest: at(interestIdx).isEmpty ? null : at(interestIdx),
          source: at(sourceIdx).isEmpty ? 'CSV import' : at(sourceIdx),
        ),
      );
    }
    return CsvLeadParseResult(leads: leads, skipped: skipped, errors: errors);
  }
}

class CsvLeadParseResult {
  const CsvLeadParseResult({required this.leads, required this.skipped, required this.errors});
  final List<NewLeadInput> leads;
  final int skipped;
  final List<String> errors;
}
