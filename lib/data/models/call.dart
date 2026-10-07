import 'enums.dart';
import 'json.dart';
import 'lead.dart';

class TranscriptLine {
  const TranscriptLine({
    required this.speaker,
    required this.text,
    this.offset,
  });
  final TranscriptSpeaker speaker;
  final String text;
  final Duration? offset;

  factory TranscriptLine.fromJson(Json j) => TranscriptLine(
    speaker: TranscriptSpeaker.parse(jStrN(j, 'speaker')),
    text: jStr(j, 'text'),
    offset: jIntN(j, 'offset_ms') == null
        ? null
        : Duration(milliseconds: jInt(j, 'offset_ms')),
  );

  Json toJson() => {
    'speaker': speaker.wire,
    'text': text,
    'offset_ms': offset?.inMilliseconds,
  };
}

class CallTranscript {
  const CallTranscript({this.lines = const [], this.language});
  final List<TranscriptLine> lines;
  final String? language;

  bool get isEmpty => lines.isEmpty;

  factory CallTranscript.fromJson(Json j) => CallTranscript(
    lines: jList(j, 'lines', TranscriptLine.fromJson),
    language: jStrN(j, 'language'),
  );

  Json toJson() => {
    'lines': lines.map((e) => e.toJson()).toList(),
    'language': language,
  };
}

/// Normalized call record. The backend maps Sarvam webhook payloads into this
/// shape; `rawMetadata` is kept opaque and is never used to drive UI state.
class Call {
  const Call({
    required this.id,
    required this.leadId,
    required this.leadName,
    required this.leadPhone,
    required this.agentId,
    required this.status,
    required this.startedAt,
    this.campaignId,
    this.duration = Duration.zero,
    this.endedAt,
    this.transcript = const CallTranscript(),
    this.summary,
    this.outcome,
    this.leadScore,
    this.nextAction = NextAction.none,
    this.callbackAt,
    this.interest,
    this.objections = const [],
    this.followUpId,
    this.interactionId,
    this.rawMetadata = const {},
  });

  final String id;
  final String leadId;
  final String leadName;
  final String leadPhone;
  final String? campaignId;
  final String agentId;
  final CallStatus status;
  final Duration duration;
  final DateTime startedAt;
  final DateTime? endedAt;
  final CallTranscript transcript;
  final String? summary;
  final String? outcome;
  final LeadScore? leadScore;
  final NextAction nextAction;
  final DateTime? callbackAt;
  final String? interest;
  final List<String> objections;
  final String? followUpId;
  final String? interactionId;
  final Map<String, dynamic> rawMetadata;

  bool get isHot => leadScore?.temperature == LeadTemperature.hot;

  factory Call.fromJson(Json j) => Call(
    id: jStr(j, 'id'),
    leadId: jStr(j, 'lead_id'),
    leadName: jStr(j, 'lead_name', 'Lead'),
    leadPhone: jStr(j, 'lead_phone'),
    campaignId: jStrN(j, 'campaign_id'),
    agentId: jStr(j, 'agent_id'),
    status: CallStatus.parse(jStrN(j, 'status')),
    duration: Duration(seconds: jInt(j, 'duration_sec')),
    startedAt: jDate(j, 'started_at') ?? DateTime.now(),
    endedAt: jDate(j, 'ended_at'),
    transcript: jObj(j, 'transcript') == null
        ? const CallTranscript()
        : CallTranscript.fromJson(jObj(j, 'transcript')!),
    summary: jStrN(j, 'summary'),
    outcome: jStrN(j, 'outcome'),
    leadScore: jObj(j, 'lead_score') == null
        ? null
        : LeadScore.fromJson(jObj(j, 'lead_score')!),
    nextAction: NextAction.parse(jStrN(j, 'next_action')),
    callbackAt: jDate(j, 'callback_at'),
    interest: jStrN(j, 'interest') ?? jStrN(j, 'course_interest'),
    objections: jStrList(j, 'objections'),
    followUpId: jStrN(j, 'followup_id'),
    interactionId: jStrN(j, 'interaction_id'),
    rawMetadata: jObj(j, 'raw_metadata') ?? const {},
  );

  Json toJson() => {
    'id': id,
    'lead_id': leadId,
    'lead_name': leadName,
    'lead_phone': leadPhone,
    'campaign_id': campaignId,
    'agent_id': agentId,
    'status': status.wire,
    'duration_sec': duration.inSeconds,
    'started_at': dateOut(startedAt),
    'ended_at': dateOut(endedAt),
    'transcript': transcript.toJson(),
    'summary': summary,
    'outcome': outcome,
    'lead_score': leadScore?.toJson(),
    'next_action': nextAction.wire,
    'callback_at': dateOut(callbackAt),
    'interest': interest,
    'objections': objections,
    'followup_id': followUpId,
    'interaction_id': interactionId,
    'raw_metadata': rawMetadata,
  };
}
