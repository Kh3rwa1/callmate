import 'enums.dart';
import 'json.dart';

class Business {
  const Business({
    required this.id,
    required this.name,
    required this.category,
    this.address,
    this.offerings = const [],
    this.fees,
    this.openingHours,
    this.location,
    this.whatsappNumber,
    this.counsellorNumber,
    this.ownerName,
  });

  final String id;
  final String name;
  final BusinessCategory category;
  final String? address;
  final List<String> offerings;
  final String? fees;
  final String? openingHours;
  final String? location;
  final String? whatsappNumber;
  final String? counsellorNumber;
  final String? ownerName;

  Business copyWith({
    String? name,
    BusinessCategory? category,
    String? address,
    List<String>? offerings,
    String? fees,
    String? openingHours,
    String? location,
    String? whatsappNumber,
    String? counsellorNumber,
  }) => Business(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    address: address ?? this.address,
    offerings: offerings ?? this.offerings,
    fees: fees ?? this.fees,
    openingHours: openingHours ?? this.openingHours,
    location: location ?? this.location,
    whatsappNumber: whatsappNumber ?? this.whatsappNumber,
    counsellorNumber: counsellorNumber ?? this.counsellorNumber,
    ownerName: ownerName,
  );

  factory Business.fromJson(Json j) => Business(
    id: jStr(j, 'id'),
    name: jStr(j, 'name'),
    category: BusinessCategory.parse(jStrN(j, 'category')),
    address: jStrN(j, 'address'),
    offerings: jStrList(j, 'offerings'),
    fees: jStrN(j, 'fees'),
    openingHours: jStrN(j, 'opening_hours'),
    location: jStrN(j, 'location'),
    whatsappNumber: jStrN(j, 'whatsapp_number'),
    counsellorNumber: jStrN(j, 'counsellor_number'),
    ownerName: jStrN(j, 'owner_name'),
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'category': category.wire,
    'address': address,
    'offerings': offerings,
    'fees': fees,
    'opening_hours': openingHours,
    'location': location,
    'whatsapp_number': whatsappNumber,
    'counsellor_number': counsellorNumber,
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
    this.languages = const ['Bengali', 'Hindi', 'English'],
    this.formality = 0.35,
    this.goal = 'Convert enquiries into counselling appointments',
    this.mascotSet = 'riya',
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
    int? callsToday,
    String? transferNumber,
    int? callingHoursStart,
    int? callingHoursEnd,
  }) => Agent(
    id: id,
    name: name ?? this.name,
    role: role ?? this.role,
    status: status ?? this.status,
    templateId: templateId,
    languages: languages ?? this.languages,
    formality: formality ?? this.formality,
    goal: goal ?? this.goal,
    mascotSet: mascotSet,
    callsToday: callsToday ?? this.callsToday,
    capabilities: capabilities,
    transferNumber: transferNumber ?? this.transferNumber,
    callingHoursStart: callingHoursStart ?? this.callingHoursStart,
    callingHoursEnd: callingHoursEnd ?? this.callingHoursEnd,
  );

  factory Agent.fromJson(Json j) => Agent(
    id: jStr(j, 'id'),
    name: jStr(j, 'name', 'Riya'),
    role: jStr(j, 'role', 'Admissions Assistant'),
    status: AgentStatus.parse(jStrN(j, 'status')),
    templateId: jStr(j, 'template_id', 'coaching_admissions_v1'),
    languages: jStrList(j, 'languages'),
    formality: jDouble(j, 'formality', 0.35),
    goal: jStr(j, 'goal'),
    mascotSet: jStr(j, 'mascot_set', 'riya'),
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

  KnowledgeSource copyWith({KnowledgeStatus? status, double? progress}) => KnowledgeSource(
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
  const KnowledgeInput({required this.type, required this.title, this.content, this.url, this.fileName, this.bytes});
  final KnowledgeType type;
  final String title;
  final String? content;
  final String? url;
  final String? fileName;
  final List<int>? bytes;
}
