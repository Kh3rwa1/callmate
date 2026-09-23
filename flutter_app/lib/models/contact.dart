/// Customer pipeline stage. Mirrors the backend's `contacts.status` values.
enum ContactStatus { newLead, calling, followUp, booked, recovered, noResponse, notInterested }

extension ContactStatusX on ContactStatus {
  String get wire => switch (this) {
        ContactStatus.newLead => 'new',
        ContactStatus.calling => 'calling',
        ContactStatus.followUp => 'followUp',
        ContactStatus.booked => 'booked',
        ContactStatus.recovered => 'recovered',
        ContactStatus.noResponse => 'noResponse',
        ContactStatus.notInterested => 'notInterested',
      };

  String get label => switch (this) {
        ContactStatus.newLead => 'New',
        ContactStatus.calling => 'Calling',
        ContactStatus.followUp => 'Follow up',
        ContactStatus.booked => 'Booked',
        ContactStatus.recovered => 'Recovered',
        ContactStatus.noResponse => 'No answer',
        ContactStatus.notInterested => 'Not interested',
      };

  /// The short label shown inside the pipeline stage selector.
  String get short => switch (this) {
        ContactStatus.newLead => 'New',
        ContactStatus.calling => 'Calling',
        ContactStatus.followUp => 'Follow up',
        ContactStatus.booked => 'Booked',
        ContactStatus.recovered => 'Recovered',
        ContactStatus.noResponse => 'No answer',
        ContactStatus.notInterested => 'Not interested',
      };

  static ContactStatus fromWire(String value) => switch (value) {
        'calling' => ContactStatus.calling,
        'followUp' => ContactStatus.followUp,
        'booked' => ContactStatus.booked,
        'recovered' => ContactStatus.recovered,
        'noResponse' => ContactStatus.noResponse,
        'notInterested' => ContactStatus.notInterested,
        _ => ContactStatus.newLead,
      };
}

class Appointment {
  const Appointment({
    required this.date,
    required this.time,
    required this.service,
    required this.status,
  });

  final String date;
  final String time;
  final String service;
  final String status;

  static Appointment? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return Appointment(
      date: json['date'] as String? ?? '',
      time: json['time'] as String? ?? '',
      service: json['service'] as String? ?? '',
      status: json['status'] as String? ?? 'scheduled',
    );
  }
}

class TimelineEntry {
  const TimelineEntry({
    required this.id,
    required this.label,
    this.detail,
    required this.at,
    required this.kind,
  });

  final String id;
  final String label;
  final String? detail;
  final DateTime at;
  final String kind;

  static TimelineEntry fromJson(Map<String, dynamic> json) => TimelineEntry(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        detail: json['detail'] as String?,
        at: DateTime.tryParse(json['at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        kind: json['kind'] as String? ?? 'status',
      );
}

class Contact {
  const Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.avatarColor,
    required this.service,
    required this.status,
    this.lastCallAt,
    this.lastCallOutcome,
    this.nextFollowUpAt,
    this.appointment,
    required this.tags,
    required this.notes,
    this.recoveredAmount,
    required this.createdAt,
    required this.timeline,
  });

  final String id;
  final String name;
  final String phone;
  final String avatarColor;
  final String service;
  final ContactStatus status;
  final DateTime? lastCallAt;
  final String? lastCallOutcome;
  final DateTime? nextFollowUpAt;
  final Appointment? appointment;
  final List<String> tags;
  final String notes;
  final double? recoveredAmount;
  final DateTime createdAt;
  final List<TimelineEntry> timeline;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  static Contact fromJson(Map<String, dynamic> json, List<TimelineEntry> timeline) => Contact(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Customer',
        phone: json['phone'] as String? ?? '',
        avatarColor: json['avatar_color'] as String? ?? '#18C97A',
        service: json['service'] as String? ?? 'Enquiry',
        status: ContactStatusX.fromWire(json['status'] as String? ?? 'new'),
        lastCallAt: DateTime.tryParse(json['last_call_at'] as String? ?? '')?.toLocal(),
        lastCallOutcome: json['last_call_outcome'] as String?,
        nextFollowUpAt: DateTime.tryParse(json['next_follow_up_at'] as String? ?? '')?.toLocal(),
        appointment: Appointment.fromJson(json['appointment'] as Map<String, dynamic>?),
        tags: (json['tags'] as List<dynamic>? ?? const []).map((t) => '$t').toList(),
        notes: json['notes'] as String? ?? '',
        recoveredAmount: (json['recovered_amount'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        timeline: timeline,
      );
}
