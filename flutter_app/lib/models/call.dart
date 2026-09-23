/// Call status. Mirrors the backend's `calls.status` values.
enum CallStatus { calling, connected, completed, missed, failed }

extension CallStatusX on CallStatus {
  String get label => switch (this) {
        CallStatus.calling => 'Calling',
        CallStatus.connected => 'Connected',
        CallStatus.completed => 'Completed',
        CallStatus.missed => 'Missed',
        CallStatus.failed => 'Failed',
      };

  static CallStatus fromWire(String value) => switch (value) {
        'connected' => CallStatus.connected,
        'completed' => CallStatus.completed,
        'missed' => CallStatus.missed,
        'failed' => CallStatus.failed,
        _ => CallStatus.calling,
      };
}

/// A call's business outcome. The backend decides this — the app only displays it.
enum CallOutcome { interested, booked, followUp, recovered, notInterested, noResponse }

extension CallOutcomeX on CallOutcome {
  String get wire => switch (this) {
        CallOutcome.interested => 'interested',
        CallOutcome.booked => 'booked',
        CallOutcome.followUp => 'followUp',
        CallOutcome.recovered => 'recovered',
        CallOutcome.notInterested => 'notInterested',
        CallOutcome.noResponse => 'noResponse',
      };

  String get label => switch (this) {
        CallOutcome.interested => 'Interested',
        CallOutcome.booked => 'Appointment booked',
        CallOutcome.followUp => 'Follow-up needed',
        CallOutcome.recovered => 'Payment recovered',
        CallOutcome.notInterested => 'Not interested',
        CallOutcome.noResponse => 'No answer',
      };

  static CallOutcome? fromWire(String? value) => switch (value) {
        'interested' => CallOutcome.interested,
        'booked' => CallOutcome.booked,
        'followUp' => CallOutcome.followUp,
        'recovered' => CallOutcome.recovered,
        'notInterested' => CallOutcome.notInterested,
        'noResponse' => CallOutcome.noResponse,
        _ => null,
      };
}

class Call {
  const Call({
    required this.id,
    required this.contactId,
    this.campaignId,
    required this.direction,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.durationSeconds,
    this.outcome,
    required this.summary,
    required this.insight,
  });

  final String id;
  final String contactId;
  final String? campaignId;
  final String direction;
  final CallStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final CallOutcome? outcome;
  final String summary;
  final String insight;

  bool get isLive => status == CallStatus.calling || status == CallStatus.connected;

  static Call fromJson(Map<String, dynamic> json) => Call(
        id: json['id'] as String,
        contactId: json['contact_id'] as String,
        campaignId: json['campaign_id'] as String?,
        direction: json['direction'] as String? ?? 'outbound',
        status: CallStatusX.fromWire(json['status'] as String? ?? 'completed'),
        startedAt: DateTime.tryParse(json['started_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        endedAt: DateTime.tryParse(json['ended_at'] as String? ?? '')?.toLocal(),
        durationSeconds: json['duration_seconds'] as int? ?? 0,
        outcome: CallOutcomeX.fromWire(json['outcome'] as String?),
        summary: json['summary'] as String? ?? '',
        insight: json['insight'] as String? ?? '',
      );
}

/// The transcript of one call, loaded on demand.
class TranscriptTurn {
  const TranscriptTurn({required this.speaker, required this.text});

  final String speaker;
  final String text;

  bool get isAi => speaker != 'customer';

  static TranscriptTurn fromJson(Map<String, dynamic> json) => TranscriptTurn(
        speaker: json['speaker'] as String? ?? 'ai',
        text: json['text'] as String? ?? '',
      );
}

class Transcript {
  const Transcript({required this.callId, required this.turns});

  final String callId;
  final List<TranscriptTurn> turns;

  static Transcript fromJson(Map<String, dynamic> json) => Transcript(
        callId: json['callId'] as String? ?? '',
        turns: (json['turns'] as List<dynamic>? ?? const [])
            .map((t) => TranscriptTurn.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}
