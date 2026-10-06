import 'enums.dart';
import 'json.dart';

/// Structured post-call output the backend asks the AI to produce
/// (via Sarvam agent output variables). Mirrors backend/schemas/call_output.schema.json.
///
/// The backend validates this, then normalises it into Call / Lead / FollowUp.
/// The mobile UI reads ONLY the normalised entities – this class exists so the
/// mock engine follows the exact same pipeline the real backend does.
class AiCallOutput {
  const AiCallOutput({
    required this.leadScore,
    required this.intent,
    required this.temperature,
    required this.summary,
    required this.nextAction,
    required this.whatsappFollowupRequired,
    this.courseInterest,
    this.preferredBatch,
    this.budget,
    this.objections = const [],
    this.positiveSignals = const [],
    this.callbackAt,
    this.whatsappMessage,
    this.language,
  });

  final int leadScore;
  final LeadIntent intent;
  final LeadTemperature temperature;
  final String? courseInterest;
  final String? preferredBatch;
  final String? budget;
  final List<String> objections;
  final List<String> positiveSignals;
  final String summary;
  final NextAction nextAction;
  final DateTime? callbackAt;
  final bool whatsappFollowupRequired;
  final String? whatsappMessage;
  final String? language;

  factory AiCallOutput.fromJson(Json j) {
    final score = jInt(j, 'lead_score').clamp(0, 100);
    return AiCallOutput(
      leadScore: score,
      intent: LeadIntent.parse(jStrN(j, 'intent')),
      temperature: j['temperature'] == null ? LeadTemperature.fromScore(score) : LeadTemperature.parse(jStrN(j, 'temperature')),
      courseInterest: jStrN(j, 'course_interest'),
      preferredBatch: jStrN(j, 'preferred_batch'),
      budget: jStrN(j, 'budget'),
      objections: jStrList(j, 'objections'),
      positiveSignals: jStrList(j, 'positive_signals'),
      summary: jStr(j, 'summary'),
      nextAction: NextAction.parse(jStrN(j, 'next_action')),
      callbackAt: jDate(j, 'callback_at'),
      whatsappFollowupRequired: jBool(j, 'whatsapp_followup_required'),
      whatsappMessage: jStrN(j, 'whatsapp_message'),
      language: jStrN(j, 'language'),
    );
  }

  Json toJson() => {
    'lead_score': leadScore,
    'intent': intent.wire,
    'temperature': temperature.wire,
    'course_interest': courseInterest,
    'preferred_batch': preferredBatch,
    'budget': budget,
    'objections': objections,
    'positive_signals': positiveSignals,
    'summary': summary,
    'next_action': nextAction.wire,
    'callback_at': dateOut(callbackAt),
    'whatsapp_followup_required': whatsappFollowupRequired,
    'whatsapp_message': whatsappMessage,
    'language': language,
  };
}
