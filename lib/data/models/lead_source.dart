import 'json.dart';

/// How enquiries reach the business automatically (speed-to-lead).
enum LeadSourceKind {
  /// Hosted enquiry form at `/f/<slug>` (link, QR code).
  form('form'),

  /// `POST /hooks/leads/<slug>` with a bearer token (website, Google Forms).
  webhook('webhook');

  const LeadSourceKind(this.wire);
  final String wire;

  static LeadSourceKind parse(String? v) =>
      v == 'webhook' ? LeadSourceKind.webhook : LeadSourceKind.form;
}

/// A form or webhook that turns enquiries into leads and, with [autoCall],
/// gets them an AI call within about a minute. Contract: backend/API.md §10b.
class LeadSource {
  const LeadSource({
    required this.id,
    required this.kind,
    required this.slug,
    required this.url,
    required this.autoCall,
    required this.createdAt,
    this.leadsCount = 0,
    this.token,
  });

  final String id;
  final LeadSourceKind kind;
  final String slug;

  /// Public form link, or the webhook endpoint.
  final String url;
  final bool autoCall;
  final int leadsCount;
  final DateTime createdAt;

  /// Webhook bearer token: only present right after creation (shown once).
  final String? token;

  bool get isForm => kind == LeadSourceKind.form;

  factory LeadSource.fromJson(Json j) => LeadSource(
    id: jStr(j, 'id'),
    kind: LeadSourceKind.parse(jStrN(j, 'kind')),
    slug: jStr(j, 'slug'),
    url: jStr(j, 'url'),
    autoCall: jBool(j, 'auto_call', true),
    leadsCount: jInt(j, 'leads_count'),
    createdAt: jDate(j, 'created_at') ?? DateTime.now(),
    token: jStrN(j, 'token'),
  );

  LeadSource copyWith({bool? autoCall, int? leadsCount}) => LeadSource(
    id: id,
    kind: kind,
    slug: slug,
    url: url,
    autoCall: autoCall ?? this.autoCall,
    leadsCount: leadsCount ?? this.leadsCount,
    createdAt: createdAt,
  );
}
