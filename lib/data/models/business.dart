import 'enums.dart';
import 'json.dart';

class Business {
  const Business({
    required this.id,
    required this.name,
    required this.category,
    this.address,
    this.offerings = const [],
    this.pricing,
    this.openingHours,
    this.location,
    this.whatsappNumber,
    this.humanNumber,
    this.ownerName,
  });

  final String id;
  final String name;
  final BusinessCategory category;
  final String? address;
  final List<String> offerings;
  final String? pricing;
  final String? openingHours;
  final String? location;
  final String? whatsappNumber;

  /// Number of the human who closes (counsellor / agent / front desk).
  final String? humanNumber;
  final String? ownerName;

  Business copyWith({
    String? name,
    BusinessCategory? category,
    String? address,
    List<String>? offerings,
    String? pricing,
    String? openingHours,
    String? location,
    String? whatsappNumber,
    String? humanNumber,
  }) => Business(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    address: address ?? this.address,
    offerings: offerings ?? this.offerings,
    pricing: pricing ?? this.pricing,
    openingHours: openingHours ?? this.openingHours,
    location: location ?? this.location,
    whatsappNumber: whatsappNumber ?? this.whatsappNumber,
    humanNumber: humanNumber ?? this.humanNumber,
    ownerName: ownerName,
  );

  factory Business.fromJson(Json j) => Business(
    id: jStr(j, 'id'),
    name: jStr(j, 'name'),
    category: BusinessCategory.parse(jStrN(j, 'category')),
    address: jStrN(j, 'address'),
    offerings: jStrList(j, 'offerings'),
    pricing: jStrN(j, 'pricing') ?? jStrN(j, 'fees'),
    openingHours: jStrN(j, 'opening_hours'),
    location: jStrN(j, 'location'),
    whatsappNumber: jStrN(j, 'whatsapp_number'),
    humanNumber: jStrN(j, 'human_number') ?? jStrN(j, 'counsellor_number'),
    ownerName: jStrN(j, 'owner_name'),
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'category': category.wire,
    'address': address,
    'offerings': offerings,
    'pricing': pricing,
    'opening_hours': openingHours,
    'location': location,
    'whatsapp_number': whatsappNumber,
    'human_number': humanNumber,
    'owner_name': ownerName,
  };
}

/// A configurable AI employee. Name, role, mascot and languages are data,
/// so a different persona can be shipped without touching layouts.
class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    required this.templateId,
    this.languages = const ['English', 'Hindi', 'Bengali'],
    this.formality = 0.35,
    this.goal = 'Convert enquiries into qualified opportunities',
    this.mascotSet = 'default',
    this.roleKind = 'general',
    this.skills = const [],
    this.voice = 'Warm · Female',
    this.callsToday = 0,
    this.capabilities = const [],
    this.transferNumber,
    this.callingHoursStart = 10,
    this.callingHoursEnd = 19,
  });

  final String id;
  final String name;
  final String role;
  final AgentStatus status;
  final String templateId;
  final List<String> languages;

  /// 0 = very friendly, 1 = very formal.
  final double formality;
  final String goal;
  final String mascotSet;

  /// Visual role (EmployeeRoleKind.name) – drives mascot accessory/badge.
  final String roleKind;

  /// EmployeeSkill wire values chosen during onboarding.
  final List<String> skills;
  final String voice;
  final int callsToday;
  final List<String> capabilities;
  final String? transferNumber;
  final int callingHoursStart;
  final int callingHoursEnd;

  String get personalityLabel {
    if (formality < 0.3) return 'Warm · Friendly';
    if (formality < 0.6) return 'Friendly · Professional';
    return 'Formal · Professional';
  }

  Agent copyWith({
    String? name,
    String? role,
    AgentStatus? status,
    List<String>? languages,
    double? formality,
    String? goal,
    String? roleKind,
    List<String>? skills,
    String? voice,
    String? templateId,
    List<String>? capabilities,
    int? callsToday,
    String? transferNumber,
    int? callingHoursStart,
    int? callingHoursEnd,
  }) => Agent(
    id: id,
    name: name ?? this.name,
    role: role ?? this.role,
    status: status ?? this.status,
    templateId: templateId ?? this.templateId,
    languages: languages ?? this.languages,
    formality: formality ?? this.formality,
    goal: goal ?? this.goal,
    mascotSet: mascotSet,
    roleKind: roleKind ?? this.roleKind,
    skills: skills ?? this.skills,
    voice: voice ?? this.voice,
    callsToday: callsToday ?? this.callsToday,
    capabilities: capabilities ?? this.capabilities,
    transferNumber: transferNumber ?? this.transferNumber,
    callingHoursStart: callingHoursStart ?? this.callingHoursStart,
    callingHoursEnd: callingHoursEnd ?? this.callingHoursEnd,
  );

  factory Agent.fromJson(Json j) => Agent(
    id: jStr(j, 'id'),
    name: jStr(j, 'name', 'AI Employee'),
    role: jStr(j, 'role', 'Sales Assistant'),
    status: AgentStatus.parse(jStrN(j, 'status')),
    templateId: jStr(j, 'template_id', 'generic_sales_v1'),
    languages: jStrList(j, 'languages'),
    formality: jDouble(j, 'formality', 0.35),
    goal: jStr(j, 'goal'),
    mascotSet: jStr(j, 'mascot_set', 'default'),
    roleKind: jStr(j, 'role_kind', 'general'),
    skills: jStrList(j, 'skills'),
    voice: jStr(j, 'voice', 'Warm · Female'),
    callsToday: jInt(j, 'calls_today'),
    capabilities: jStrList(j, 'capabilities'),
    transferNumber: jStrN(j, 'transfer_number'),
    callingHoursStart: jInt(j, 'calling_hours_start', 10),
    callingHoursEnd: jInt(j, 'calling_hours_end', 19),
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'status': status.wire,
    'template_id': templateId,
    'languages': languages,
    'formality': formality,
    'goal': goal,
    'mascot_set': mascotSet,
    'role_kind': roleKind,
    'skills': skills,
    'voice': voice,
    'calls_today': callsToday,
    'capabilities': capabilities,
    'transfer_number': transferNumber,
    'calling_hours_start': callingHoursStart,
    'calling_hours_end': callingHoursEnd,
  };
}

class KnowledgeSource {
  const KnowledgeSource({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    required this.updatedAt,
    this.detail,
    this.progress = 1,
  });

  final String id;
  final KnowledgeType type;
  final String title;
  final String? detail;
  final KnowledgeStatus status;
  final double progress;
  final DateTime updatedAt;

  KnowledgeSource copyWith({KnowledgeStatus? status, double? progress}) =>
      KnowledgeSource(
        id: id,
        type: type,
        title: title,
        detail: detail,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        updatedAt: DateTime.now(),
      );

  factory KnowledgeSource.fromJson(Json j) => KnowledgeSource(
    id: jStr(j, 'id'),
    type: KnowledgeType.parse(jStrN(j, 'type')),
    title: jStr(j, 'title'),
    detail: jStrN(j, 'detail'),
    status: KnowledgeStatus.parse(jStrN(j, 'status')),
    progress: jDouble(j, 'progress', 1),
    updatedAt: jDate(j, 'updated_at') ?? DateTime.now(),
  );

  Json toJson() => {
    'id': id,
    'type': type.wire,
    'title': title,
    'detail': detail,
    'status': status.wire,
    'progress': progress,
    'updated_at': dateOut(updatedAt),
  };
}

/// Input for adding knowledge. File bytes are uploaded to our backend which
/// extracts text and syncs it to the Sarvam agent's knowledge base.
class KnowledgeInput {
  const KnowledgeInput({
    required this.type,
    required this.title,
    this.content,
    this.url,
    this.fileName,
    this.bytes,
  });
  final KnowledgeType type;
  final String title;
  final String? content;
  final String? url;
  final String? fileName;
  final List<int>? bytes;
}
