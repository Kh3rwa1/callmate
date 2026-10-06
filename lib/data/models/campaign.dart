import 'enums.dart';
import 'json.dart';

class CampaignOptions {
  const CampaignOptions({this.scoreLead = true, this.generateWhatsapp = true, this.recommendCallback = true, this.notifyHot = true});
  final bool scoreLead;
  final bool generateWhatsapp;
  final bool recommendCallback;
  final bool notifyHot;

  CampaignOptions copyWith({bool? scoreLead, bool? generateWhatsapp, bool? recommendCallback, bool? notifyHot}) => CampaignOptions(
    scoreLead: scoreLead ?? this.scoreLead,
    generateWhatsapp: generateWhatsapp ?? this.generateWhatsapp,
    recommendCallback: recommendCallback ?? this.recommendCallback,
    notifyHot: notifyHot ?? this.notifyHot,
  );

  factory CampaignOptions.fromJson(Json j) => CampaignOptions(
    scoreLead: jBool(j, 'score_lead', true),
    generateWhatsapp: jBool(j, 'generate_whatsapp', true),
    recommendCallback: jBool(j, 'recommend_callback', true),
    notifyHot: jBool(j, 'notify_hot', true),
  );

  Json toJson() => {
    'score_lead': scoreLead,
    'generate_whatsapp': generateWhatsapp,
    'recommend_callback': recommendCallback,
    'notify_hot': notifyHot,
  };
}

class CampaignStats {
  const CampaignStats({this.total = 0, this.queued = 0, this.completed = 0, this.connected = 0, this.interested = 0, this.hot = 0});
  final int total;
  final int queued;
  final int completed;
  final int connected;
  final int interested;
  final int hot;

  int get remaining => (total - completed).clamp(0, total);
  double get progress => total == 0 ? 0 : completed / total;

  factory CampaignStats.fromJson(Json j) => CampaignStats(
    total: jInt(j, 'total'),
    queued: jInt(j, 'queued'),
    completed: jInt(j, 'completed'),
    connected: jInt(j, 'connected'),
    interested: jInt(j, 'interested'),
    hot: jInt(j, 'hot'),
  );

  Json toJson() => {'total': total, 'queued': queued, 'completed': completed, 'connected': connected, 'interested': interested, 'hot': hot};
}

class Campaign {
  const Campaign({
    required this.id,
    required this.agentId,
    required this.purpose,
    required this.status,
    required this.createdAt,
    this.leadIds = const [],
    this.languageMode = 'auto',
    this.callingHoursStart = 10,
    this.callingHoursEnd = 19,
    this.options = const CampaignOptions(),
    this.stats = const CampaignStats(),
    this.estimatedCostInr = 0,
    this.startedAt,
    this.recentCallIds = const [],
  });

  final String id;
  final String agentId;
  final String purpose;
  final CampaignStatus status;
  final List<String> leadIds;
  final String languageMode;
  final int callingHoursStart;
  final int callingHoursEnd;
  final CampaignOptions options;
  final CampaignStats stats;
  final int estimatedCostInr;
  final DateTime createdAt;
  final DateTime? startedAt;
  final List<String> recentCallIds;

  bool get isActive => status == CampaignStatus.running;

  Campaign copyWith({CampaignStatus? status, CampaignStats? stats, DateTime? startedAt, List<String>? recentCallIds}) => Campaign(
    id: id,
    agentId: agentId,
    purpose: purpose,
    status: status ?? this.status,
    leadIds: leadIds,
    languageMode: languageMode,
    callingHoursStart: callingHoursStart,
    callingHoursEnd: callingHoursEnd,
    options: options,
    stats: stats ?? this.stats,
    estimatedCostInr: estimatedCostInr,
    createdAt: createdAt,
    startedAt: startedAt ?? this.startedAt,
    recentCallIds: recentCallIds ?? this.recentCallIds,
  );

  factory Campaign.fromJson(Json j) => Campaign(
    id: jStr(j, 'id'),
    agentId: jStr(j, 'agent_id'),
    purpose: jStr(j, 'purpose'),
    status: CampaignStatus.parse(jStrN(j, 'status')),
    leadIds: jStrList(j, 'lead_ids'),
    languageMode: jStr(j, 'language_mode', 'auto'),
    callingHoursStart: jInt(j, 'calling_hours_start', 10),
    callingHoursEnd: jInt(j, 'calling_hours_end', 19),
    options: CampaignOptions.fromJson(jObj(j, 'options') ?? const {}),
    stats: CampaignStats.fromJson(jObj(j, 'stats') ?? const {}),
    estimatedCostInr: jInt(j, 'estimated_cost_inr'),
    createdAt: jDate(j, 'created_at') ?? DateTime.now(),
    startedAt: jDate(j, 'started_at'),
    recentCallIds: jStrList(j, 'recent_call_ids'),
  );

  Json toJson() => {
    'id': id,
    'agent_id': agentId,
    'purpose': purpose,
    'status': status.wire,
    'lead_ids': leadIds,
    'language_mode': languageMode,
    'calling_hours_start': callingHoursStart,
    'calling_hours_end': callingHoursEnd,
    'options': options.toJson(),
    'stats': stats.toJson(),
    'estimated_cost_inr': estimatedCostInr,
    'created_at': dateOut(createdAt),
    'started_at': dateOut(startedAt),
    'recent_call_ids': recentCallIds,
  };
}

class CampaignDraft {
  const CampaignDraft({
    required this.leadIds,
    required this.purpose,
    this.languageMode = 'auto',
    this.callingHoursStart = 10,
    this.callingHoursEnd = 19,
    this.options = const CampaignOptions(),
  });
  final List<String> leadIds;
  final String purpose;
  final String languageMode;
  final int callingHoursStart;
  final int callingHoursEnd;
  final CampaignOptions options;

  Json toJson() => {
    'lead_ids': leadIds,
    'purpose': purpose,
    'language_mode': languageMode,
    'calling_hours_start': callingHoursStart,
    'calling_hours_end': callingHoursEnd,
    'options': options.toJson(),
  };
}
