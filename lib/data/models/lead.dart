import 'enums.dart';
import 'json.dart';

/// Structured lead score – produced by the backend from the AI's structured
/// output (never parsed from free text on device).
class LeadScore {
  const LeadScore({
    required this.value,
    required this.temperature,
    required this.intent,
    this.positiveSignals = const [],
    this.concerns = const [],
  });

  final int value; // 0-100
  final LeadTemperature temperature;
  final LeadIntent intent;
  final List<String> positiveSignals;
  final List<String> concerns;

  String get intentLabel => switch (temperature) {
    LeadTemperature.hot => 'HIGH INTENT',
    LeadTemperature.warm => 'MEDIUM INTENT',
    LeadTemperature.cold => 'LOW INTENT',
    LeadTemperature.unknown => 'NOT SCORED',
  };

  factory LeadScore.fromJson(Json j) {
    final v = jInt(j, 'value');
    return LeadScore(
      value: v,
      temperature: j['temperature'] == null
          ? LeadTemperature.fromScore(v)
          : LeadTemperature.parse(jStrN(j, 'temperature')),
      intent: LeadIntent.parse(jStrN(j, 'intent')),
      positiveSignals: jStrList(j, 'positive_signals'),
      concerns: jStrList(j, 'concerns'),
    );
  }

  Json toJson() => {
    'value': value,
    'temperature': temperature.wire,
    'intent': intent.wire,
    'positive_signals': positiveSignals,
    'concerns': concerns,
  };
}

/// Generic lead. Business-specific data (batch, budget, property type…) lives
/// in [attributes], keyed by the WorkflowTemplate – never as global fields.
class Lead {
  const Lead({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.source,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.interest,
    this.attributes = const {},
    this.score,
    this.summary,
    this.objections = const [],
    this.nextAction = NextAction.none,
    this.callbackAt,
    this.lastCallId,
    this.language,
    this.consent = 'unknown',
    this.doNotCall = false,
  });

  final String id;
  final String businessId;
  final String name;
  final String phone;
  final String source;

  /// What the lead is interested in (course, property, service, model…).
  final String? interest;

  /// Optional, template-defined custom attributes.
  final Map<String, String> attributes;
  final LeadStatus status;
  final LeadScore? score;
  final String? summary;
  final List<String> objections;
  final NextAction nextAction;
  final DateTime? callbackAt;
  final String? lastCallId;
  final String? language;
  final String consent;
  final bool doNotCall;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasConsent => consent != 'unknown' && consent != 'opt_out';
  LeadTemperature get temperature =>
      score?.temperature ?? LeadTemperature.unknown;
  bool get isHot => temperature == LeadTemperature.hot;
  bool get isWarm => temperature == LeadTemperature.warm;
  bool get hasBeenCalled => lastCallId != null;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  /// "NEET · Evening" / "3 BHK · Site visit" – interest plus the first attribute.
  String get interestLine {
    final first = attributes.entries
        .where((e) => e.key != 'budget')
        .map((e) => e.value)
        .firstOrNull;
    final parts = [
      interest,
      first,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? 'Interest not known yet' : parts.join(' · ');
  }

  Lead copyWith({
    String? name,
    String? phone,
    String? interest,
    Map<String, String>? attributes,
    LeadStatus? status,
    LeadScore? score,
    String? summary,
    List<String>? objections,
    NextAction? nextAction,
    DateTime? callbackAt,
    bool clearCallback = false,
    String? lastCallId,
    String? language,
    String? consent,
    bool? doNotCall,
    DateTime? updatedAt,
  }) => Lead(
    id: id,
    businessId: businessId,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    source: source,
    interest: interest ?? this.interest,
    attributes: attributes ?? this.attributes,
    status: status ?? this.status,
    score: score ?? this.score,
    summary: summary ?? this.summary,
    objections: objections ?? this.objections,
    nextAction: nextAction ?? this.nextAction,
    callbackAt: clearCallback ? null : (callbackAt ?? this.callbackAt),
    lastCallId: lastCallId ?? this.lastCallId,
    language: language ?? this.language,
    consent: consent ?? this.consent,
    doNotCall: doNotCall ?? this.doNotCall,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  factory Lead.fromJson(Json j) {
    final attrs = <String, String>{
      for (final e in (jObj(j, 'attributes') ?? const {}).entries)
        if (e.value != null) e.key: e.value.toString(),
    };
    // Back-compat with v0 coaching payloads.
    final legacyBatch = jStrN(j, 'preferred_batch');
    final legacyBudget = jStrN(j, 'budget');
    if (legacyBatch != null) attrs.putIfAbsent('batch', () => legacyBatch);
    if (legacyBudget != null) attrs.putIfAbsent('budget', () => legacyBudget);
    return Lead(
      id: jStr(j, 'id'),
      businessId: jStr(j, 'business_id'),
      name: jStr(j, 'name', 'Unknown'),
      phone: jStr(j, 'phone'),
      source: jStr(j, 'source', 'Manual'),
      interest: jStrN(j, 'interest') ?? jStrN(j, 'course_interest'),
      attributes: attrs,
      status: LeadStatus.parse(jStrN(j, 'status')),
      score: jObj(j, 'score') == null
          ? null
          : LeadScore.fromJson(jObj(j, 'score')!),
      summary: jStrN(j, 'summary'),
      objections: jStrList(j, 'objections'),
      nextAction: NextAction.parse(jStrN(j, 'next_action')),
      callbackAt: jDate(j, 'callback_at'),
      lastCallId: jStrN(j, 'last_call_id'),
      language: jStrN(j, 'language'),
      consent: jStr(j, 'consent', 'unknown'),
      doNotCall: jBool(j, 'do_not_call'),
      createdAt: jDate(j, 'created_at') ?? DateTime.now(),
      updatedAt: jDate(j, 'updated_at') ?? DateTime.now(),
    );
  }

  Json toJson() => {
    'id': id,
    'business_id': businessId,
    'name': name,
    'phone': phone,
    'source': source,
    'interest': interest,
    'attributes': attributes,
    'status': status.wire,
    'score': score?.toJson(),
    'summary': summary,
    'objections': objections,
    'next_action': nextAction.wire,
    'callback_at': dateOut(callbackAt),
    'last_call_id': lastCallId,
    'language': language,
    'consent': consent,
    'do_not_call': doNotCall,
    'created_at': dateOut(createdAt),
    'updated_at': dateOut(updatedAt),
  };
}

/// Input used when creating/importing leads.
class NewLeadInput {
  const NewLeadInput({
    required this.name,
    required this.phone,
    this.interest,
    this.source = 'Manual',
    this.attributes = const {},
    this.consent = 'unknown',
  });
  final String name;
  final String phone;
  final String? interest;
  final String source;
  final Map<String, String> attributes;
  final String consent;

  Json toJson() => {
    'name': name,
    'phone': phone,
    if (interest != null) 'interest': interest,
    'source': source,
    'attributes': attributes,
    'consent': consent,
  };
}

class LeadImportResult {
  const LeadImportResult({
    required this.imported,
    required this.skipped,
    this.errors = const [],
  });
  final int imported;
  final int skipped;
  final List<String> errors;

  factory LeadImportResult.fromJson(Json j) => LeadImportResult(
    imported: jInt(j, 'imported'),
    skipped: jInt(j, 'skipped'),
    errors: jStrList(j, 'errors'),
  );
}

/// One entry of a lead's consent evidence trail
/// (`GET /leads/:id/consent-history`).
class ConsentEvent {
  const ConsentEvent({
    required this.id,
    required this.consentValue,
    required this.source,
    required this.createdAt,
    this.textVersion,
  });
  final String id;

  /// `explicit_opt_in`, `inquiry`, `existing_customer`, `unknown`, `opt_out`,
  /// `owner_attested`, `do_not_call` or `do_not_call_removed`.
  final String consentValue;

  /// `form`, `webhook`, `import_attestation`, `manual`, `in_call_opt_out`,
  /// `google_ads`, `indiamart` or `meta_lead_ads`.
  final String source;
  final String? textVersion;
  final DateTime createdAt;

  factory ConsentEvent.fromJson(Json j) => ConsentEvent(
    id: jStr(j, 'id'),
    consentValue: jStr(j, 'consent_value', 'unknown'),
    source: jStr(j, 'source', 'manual'),
    textVersion: jStrN(j, 'text_version'),
    createdAt: jDate(j, 'created_at') ?? DateTime.now(),
  );
}
