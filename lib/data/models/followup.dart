import 'enums.dart';
import 'json.dart';

class FollowUp {
  const FollowUp({
    required this.id,
    required this.leadId,
    required this.leadName,
    required this.leadPhone,
    required this.message,
    required this.status,
    required this.createdAt,
    this.callId,
    this.channel = FollowUpChannel.whatsapp,
    this.callSummary,
    this.scoreValue,
    this.openedAt,
  });

  final String id;
  final String leadId;
  final String leadName;
  final String leadPhone;
  final String? callId;
  final FollowUpChannel channel;
  final String message;
  final FollowUpStatus status;
  final String? callSummary;
  final int? scoreValue;
  final DateTime createdAt;
  final DateTime? openedAt;

  bool get isPending => status == FollowUpStatus.ready;

  FollowUp copyWith({
    String? message,
    FollowUpStatus? status,
    DateTime? openedAt,
  }) => FollowUp(
    id: id,
    leadId: leadId,
    leadName: leadName,
    leadPhone: leadPhone,
    callId: callId,
    channel: channel,
    message: message ?? this.message,
    status: status ?? this.status,
    callSummary: callSummary,
    scoreValue: scoreValue,
    createdAt: createdAt,
    openedAt: openedAt ?? this.openedAt,
  );

  factory FollowUp.fromJson(Json j) => FollowUp(
    id: jStr(j, 'id'),
    leadId: jStr(j, 'lead_id'),
    leadName: jStr(j, 'lead_name', 'Lead'),
    leadPhone: jStr(j, 'lead_phone'),
    callId: jStrN(j, 'call_id'),
    channel: FollowUpChannel.parse(jStrN(j, 'channel')),
    message: jStr(j, 'message'),
    status: FollowUpStatus.parse(jStrN(j, 'status')),
    callSummary: jStrN(j, 'call_summary'),
    scoreValue: jIntN(j, 'score_value'),
    createdAt: jDate(j, 'created_at') ?? DateTime.now(),
    openedAt: jDate(j, 'opened_at'),
  );

  Json toJson() => {
    'id': id,
    'lead_id': leadId,
    'lead_name': leadName,
    'lead_phone': leadPhone,
    'call_id': callId,
    'channel': channel.wire,
    'message': message,
    'status': status.wire,
    'call_summary': callSummary,
    'score_value': scoreValue,
    'created_at': dateOut(createdAt),
    'opened_at': dateOut(openedAt),
  };
}

class Callback {
  const Callback({
    required this.id,
    required this.leadId,
    required this.leadName,
    required this.scheduledAt,
    this.status = CallbackStatus.scheduled,
    this.note,
  });

  final String id;
  final String leadId;
  final String leadName;
  final DateTime scheduledAt;
  final CallbackStatus status;
  final String? note;

  Callback copyWith({CallbackStatus? status, DateTime? scheduledAt}) =>
      Callback(
        id: id,
        leadId: leadId,
        leadName: leadName,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        status: status ?? this.status,
        note: note,
      );

  factory Callback.fromJson(Json j) => Callback(
    id: jStr(j, 'id'),
    leadId: jStr(j, 'lead_id'),
    leadName: jStr(j, 'lead_name'),
    scheduledAt: jDate(j, 'scheduled_at') ?? DateTime.now(),
    status: CallbackStatus.parse(jStrN(j, 'status')),
    note: jStrN(j, 'note'),
  );

  Json toJson() => {
    'id': id,
    'lead_id': leadId,
    'lead_name': leadName,
    'scheduled_at': dateOut(scheduledAt),
    'status': status.wire,
    'note': note,
  };
}
