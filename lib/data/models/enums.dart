/// Enums shared across the normalized domain model.
///
/// Every enum has a stable wire value (`wire`) so the backend contract is
/// independent from Dart identifiers, and unknown values degrade gracefully.
library;

T _parse<T extends Enum>(
  List<T> values,
  String? raw,
  T fallback,
  String Function(T) wire,
) {
  if (raw == null) return fallback;
  for (final v in values) {
    if (wire(v) == raw) return v;
  }
  return fallback;
}

enum LeadStatus {
  newLead('new', 'New'),
  queued('queued', 'Queued'),
  calling('calling', 'Calling'),
  called('called', 'Called'),
  callback('callback', 'Callback'),
  noAnswer('no_answer', 'No answer'),
  converted('converted', 'Converted'),
  notInterested('not_interested', 'Not interested');

  const LeadStatus(this.wire, this.label);
  final String wire;
  final String label;
  static LeadStatus parse(String? v) =>
      _parse(values, v, LeadStatus.newLead, (e) => e.wire);
}

enum LeadTemperature {
  hot('hot', 'HOT'),
  warm('warm', 'WARM'),
  cold('cold', 'COLD'),
  unknown('unknown', 'NOT SCORED');

  const LeadTemperature(this.wire, this.label);
  final String wire;
  final String label;
  static LeadTemperature parse(String? v) =>
      _parse(values, v, LeadTemperature.unknown, (e) => e.wire);

  static LeadTemperature fromScore(int? score) {
    if (score == null) return LeadTemperature.unknown;
    if (score >= 75) return LeadTemperature.hot;
    if (score >= 45) return LeadTemperature.warm;
    return LeadTemperature.cold;
  }
}

enum LeadIntent {
  interested('interested', 'Interested'),
  exploring('exploring', 'Exploring'),
  notInterested('not_interested', 'Not interested'),
  callbackRequested('callback_requested', 'Wants callback'),
  unknown('unknown', 'Unknown');

  const LeadIntent(this.wire, this.label);
  final String wire;
  final String label;
  static LeadIntent parse(String? v) =>
      _parse(values, v, LeadIntent.unknown, (e) => e.wire);
}

enum CallStatus {
  queued('queued', 'Queued'),
  ringing('ringing', 'Ringing'),
  inProgress('in_progress', 'On call'),
  completed('completed', 'Connected'),
  noAnswer('no_answer', 'No answer'),
  busy('busy', 'Busy'),
  failed('failed', 'Failed');

  const CallStatus(this.wire, this.label);
  final String wire;
  final String label;
  static CallStatus parse(String? v) =>
      _parse(values, v, CallStatus.failed, (e) => e.wire);

  bool get isConnected => this == CallStatus.completed;
  bool get isLive =>
      this == CallStatus.ringing || this == CallStatus.inProgress;
}

enum NextAction {
  humanFollowUp('human_followup', 'Human follow-up'),
  sendWhatsapp('send_whatsapp', 'Send WhatsApp'),
  whatsappAndCallback('whatsapp_and_callback', 'WhatsApp + call back'),
  bookAppointment('book_appointment', 'Book appointment / visit'),
  retryCall('retry_call', 'Try calling again'),
  none('none', 'No action needed');

  const NextAction(this.wire, this.label);
  final String wire;
  final String label;
  static NextAction parse(String? v) => switch (v) {
    // legacy wire values from older backend builds
    'counsellor_callback' => NextAction.humanFollowUp,
    'schedule_visit' => NextAction.bookAppointment,
    _ => _parse(values, v, NextAction.none, (e) => e.wire),
  };
}

enum FollowUpStatus {
  ready('ready', 'Ready to send'),
  opened('opened', 'WhatsApp opened'),
  done('done', 'Marked as sent by you'),
  dismissed('dismissed', 'Dismissed');

  const FollowUpStatus(this.wire, this.label);
  final String wire;
  final String label;
  static FollowUpStatus parse(String? v) =>
      _parse(values, v, FollowUpStatus.ready, (e) => e.wire);
}

enum FollowUpChannel {
  whatsapp('whatsapp');

  const FollowUpChannel(this.wire);
  final String wire;
  static FollowUpChannel parse(String? v) => FollowUpChannel.whatsapp;
}

enum CampaignStatus {
  draft('draft', 'Draft'),
  running('running', 'Running'),
  paused('paused', 'Paused'),
  completed('completed', 'Completed'),
  stopped('stopped', 'Stopped');

  const CampaignStatus(this.wire, this.label);
  final String wire;
  final String label;
  static CampaignStatus parse(String? v) =>
      _parse(values, v, CampaignStatus.draft, (e) => e.wire);
}

enum KnowledgeType {
  pdf('pdf', 'PDF'),
  website('website', 'Website'),
  faq('faq', 'FAQ'),
  text('text', 'Notes'),
  businessInfo('business_info', 'Business information');

  const KnowledgeType(this.wire, this.label);
  final String wire;
  final String label;
  static KnowledgeType parse(String? v) => v == 'centre_info'
      ? KnowledgeType.businessInfo
      : _parse(values, v, KnowledgeType.text, (e) => e.wire);
}

enum KnowledgeStatus {
  uploading('uploading'),
  processing('processing'),
  ready('ready'),
  failed('failed');

  const KnowledgeStatus(this.wire);
  final String wire;
  static KnowledgeStatus parse(String? v) =>
      _parse(values, v, KnowledgeStatus.ready, (e) => e.wire);
}

enum NotificationType {
  hotLead('hot_lead'),
  followUpReady('followup_ready'),
  callback('callback'),
  campaign('campaign'),

  /// A new enquiry arrived through the hosted form or webhook (speed-to-lead).
  newLead('new_lead');

  const NotificationType(this.wire);
  final String wire;
  static NotificationType parse(String? v) =>
      _parse(values, v, NotificationType.campaign, (e) => e.wire);
}

enum AgentStatus {
  active('active', 'Active'),
  paused('paused', 'Paused'),
  inactive('inactive', 'Inactive'),
  training('training', 'Learning');

  const AgentStatus(this.wire, this.label);
  final String wire;
  final String label;
  static AgentStatus parse(String? v) =>
      _parse(values, v, AgentStatus.active, (e) => e.wire);
}

enum CallbackStatus {
  scheduled('scheduled'),
  done('done'),
  missed('missed');

  const CallbackStatus(this.wire);
  final String wire;
  static CallbackStatus parse(String? v) =>
      _parse(values, v, CallbackStatus.scheduled, (e) => e.wire);
}

enum BusinessCategory {
  coaching('coaching', 'Coaching Centre', '🎓'),
  realEstate('real_estate', 'Real Estate', '🏠'),
  clinic('clinic', 'Clinic', '🩺'),
  diagnostic('diagnostic', 'Diagnostic Centre', '🧪'),
  automobile('automobile', 'Automobile', '🚗'),
  salon('salon', 'Salon', '💇'),
  gym('gym', 'Gym & Fitness', '🏋️'),
  restaurant('restaurant', 'Restaurant', '🍽️'),
  retail('retail', 'Retail', '🛍️'),
  localServices('local_services', 'Local Services', '🛠️'),
  other('other', 'Other', '✨');

  const BusinessCategory(this.wire, this.label, this.emoji);
  final String wire;
  final String label;
  final String emoji;
  static BusinessCategory parse(String? v) =>
      _parse(values, v, BusinessCategory.other, (e) => e.wire);
}

enum TranscriptSpeaker {
  agent('agent'),
  lead('lead');

  const TranscriptSpeaker(this.wire);
  final String wire;
  static TranscriptSpeaker parse(String? v) => v == 'lead' || v == 'user'
      ? TranscriptSpeaker.lead
      : TranscriptSpeaker.agent;
}
