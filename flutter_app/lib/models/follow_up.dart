enum FollowUpType { call, whatsapp, reminder }

extension FollowUpTypeX on FollowUpType {
  String get wire => switch (this) {
        FollowUpType.call => 'call',
        FollowUpType.whatsapp => 'whatsapp',
        FollowUpType.reminder => 'reminder',
      };

  String get label => switch (this) {
        FollowUpType.call => 'Call',
        FollowUpType.whatsapp => 'WhatsApp',
        FollowUpType.reminder => 'Reminder',
      };

  static FollowUpType fromWire(String value) => switch (value) {
        'whatsapp' => FollowUpType.whatsapp,
        'reminder' => FollowUpType.reminder,
        _ => FollowUpType.call,
      };
}

class FollowUp {
  const FollowUp({
    required this.id,
    required this.contactId,
    required this.dateTime,
    required this.type,
    required this.message,
    required this.status,
  });

  final String id;
  final String contactId;
  final DateTime dateTime;
  final FollowUpType type;
  final String message;
  final String status;

  bool get isPending => status == 'pending';

  static FollowUp fromJson(Map<String, dynamic> json) => FollowUp(
        id: json['id'] as String,
        contactId: json['contact_id'] as String,
        dateTime:
            DateTime.tryParse(json['date_time'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        type: FollowUpTypeX.fromWire(json['type'] as String? ?? 'call'),
        message: json['message'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
      );
}
