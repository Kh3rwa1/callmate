enum CampaignStatus { draft, running, completed, stopped }

extension CampaignStatusX on CampaignStatus {
  String get label => switch (this) {
        CampaignStatus.draft => 'Scheduled',
        CampaignStatus.running => 'Calling now',
        CampaignStatus.completed => 'Finished',
        CampaignStatus.stopped => 'Stopped',
      };

  static CampaignStatus fromWire(String value) => switch (value) {
        'running' => CampaignStatus.running,
        'completed' => CampaignStatus.completed,
        'stopped' => CampaignStatus.stopped,
        _ => CampaignStatus.draft,
      };
}

const List<String> kCampaignPurposes = [
  'appointment',
  'newLead',
  'followUp',
  'payment',
  'other',
];

const Map<String, String> kCampaignPurposeLabels = {
  'appointment': 'Appointment',
  'newLead': 'New lead',
  'followUp': 'Follow-up',
  'payment': 'Payment',
  'other': 'Other',
};

const Map<String, String> kCampaignPurposeHints = {
  'appointment': 'Confirm or book slots',
  'newLead': 'First call to new leads',
  'followUp': 'Check back with waiting customers',
  'payment': 'Collect pending payments',
  'other': 'Anything else you need',
};

class Campaign {
  const Campaign({
    required this.id,
    required this.name,
    required this.purpose,
    required this.contactIds,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.total,
    required this.completed,
    required this.booked,
    required this.interested,
    required this.followUps,
    required this.noAnswer,
  });

  final String id;
  final String name;
  final String purpose;
  final List<String> contactIds;
  final CampaignStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int total;
  final int completed;
  final int booked;
  final int interested;
  final int followUps;
  final int noAnswer;

  String get purposeLabel => kCampaignPurposeLabels[purpose] ?? purpose;

  static Campaign fromJson(Map<String, dynamic> json, List<String> contactIds) => Campaign(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Calling round',
        purpose: json['purpose'] as String? ?? 'other',
        contactIds: contactIds,
        status: CampaignStatusX.fromWire(json['status'] as String? ?? 'draft'),
        startedAt: DateTime.tryParse(json['started_at'] as String? ?? '')?.toLocal(),
        endedAt: DateTime.tryParse(json['ended_at'] as String? ?? '')?.toLocal(),
        total: json['total'] as int? ?? 0,
        completed: json['completed'] as int? ?? 0,
        booked: json['booked'] as int? ?? 0,
        interested: json['interested'] as int? ?? 0,
        followUps: json['follow_ups'] as int? ?? 0,
        noAnswer: json['no_answer'] as int? ?? 0,
      );
}

class CampaignDraft {
  const CampaignDraft({
    required this.purpose,
    required this.contactIds,
    this.scheduledFor,
  });

  final String purpose;
  final List<String> contactIds;
  final DateTime? scheduledFor;

  bool get isScheduled => scheduledFor != null;
}
