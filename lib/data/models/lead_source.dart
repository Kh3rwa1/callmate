import 'json.dart';

/// How enquiries reach the business automatically (speed-to-lead).
enum LeadSourceKind {
  /// Hosted enquiry form at `/f/<slug>` (link, QR code).
  form('form'),

  /// `POST /hooks/leads/<slug>` with a bearer token (website, Google Forms).
  webhook('webhook'),

  /// Google Ads lead form webhook (`/hooks/google-ads/<slug>` + key).
  googleAds('google_ads'),

  /// IndiaMART Lead Manager: the server pulls new enquiries with the
  /// owner's CRM key (and accepts IndiaMART's push webhook).
  indiaMart('indiamart'),

  /// Meta (Facebook & Instagram) Lead Ads via the owner's Meta app.
  meta('meta');

  const LeadSourceKind(this.wire);
  final String wire;

  /// Lead-source integrations the owner connects from an ad / marketplace.
  bool get isIntegration =>
      this == googleAds || this == indiaMart || this == meta;

  static LeadSourceKind parse(String? v) =>
      values.where((k) => k.wire == v).firstOrNull ?? LeadSourceKind.form;
}

/// A form, webhook or integration that turns enquiries into leads and, with
/// [autoCall], gets them an AI call within about a minute.
/// Contract: backend/API.md §10b.
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
    this.pushUrl,
    this.lastError,
    this.lastSyncedAt,
  });

  final String id;
  final LeadSourceKind kind;
  final String slug;

  /// Public form link, or the endpoint the provider sends leads to.
  final String url;
  final bool autoCall;
  final int leadsCount;
  final DateTime createdAt;

  /// The secret to paste into the provider (webhook bearer token, Google Ads
  /// key, Meta verify token): only present right after creation (shown once).
  final String? token;

  /// IndiaMART only, right after creation: the full push-listener URL.
  final String? pushUrl;

  /// Last problem the owner should fix (e.g. `invalid_key`), null when fine.
  final String? lastError;

  /// IndiaMART: when new enquiries were last fetched.
  final DateTime? lastSyncedAt;

  bool get isForm => kind == LeadSourceKind.form;
  bool get hasProblem => lastError != null && lastError!.isNotEmpty;

  factory LeadSource.fromJson(Json j) => LeadSource(
    id: jStr(j, 'id'),
    kind: LeadSourceKind.parse(jStrN(j, 'kind')),
    slug: jStr(j, 'slug'),
    url: jStr(j, 'url'),
    autoCall: jBool(j, 'auto_call', true),
    leadsCount: jInt(j, 'leads_count'),
    createdAt: jDate(j, 'created_at') ?? DateTime.now(),
    token: jStrN(j, 'token'),
    pushUrl: jStrN(j, 'push_url'),
    lastError: jStrN(j, 'last_error'),
    lastSyncedAt: jDate(j, 'last_synced_at'),
  );

  /// The stored view: never carries the one-time secrets.
  LeadSource copyWith({
    bool? autoCall,
    int? leadsCount,
    String? lastError,
    bool clearError = false,
    DateTime? lastSyncedAt,
  }) => LeadSource(
    id: id,
    kind: kind,
    slug: slug,
    url: url,
    autoCall: autoCall ?? this.autoCall,
    leadsCount: leadsCount ?? this.leadsCount,
    createdAt: createdAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
}

/// Secrets an integration needs when it is connected (POST /lead-sources).
/// Sent once; the server stores them encrypted and never returns them.
class LeadSourceSecrets {
  const LeadSourceSecrets({this.crmKey, this.appSecret, this.pageAccessToken});

  /// IndiaMART Lead Manager CRM (Pull API) key.
  final String? crmKey;

  /// Meta app secret (App settings → Basic).
  final String? appSecret;

  /// Meta page access token with `leads_retrieval`.
  final String? pageAccessToken;

  /// Request fields, omitting empty ones (the backend rejects `null`).
  Map<String, String> toJson() => {
    if (crmKey != null && crmKey!.trim().isNotEmpty) 'crm_key': crmKey!.trim(),
    if (appSecret != null && appSecret!.trim().isNotEmpty)
      'app_secret': appSecret!.trim(),
    if (pageAccessToken != null && pageAccessToken!.trim().isNotEmpty)
      'page_access_token': pageAccessToken!.trim(),
  };
}
