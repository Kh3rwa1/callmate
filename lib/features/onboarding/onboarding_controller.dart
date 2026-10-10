import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/models.dart';
import '../../data/templates/templates.dart';

class OnboardingDraft {
  const OnboardingDraft({
    this.category,
    this.skills = const {},
    this.businessName = '',
    this.address = '',
    this.offerings = '',
    this.pricing = '',
    this.hours = '',
    this.location = '',
    this.whatsapp = '',
    this.humanNumber = '',
    this.knowledge = const [],
    this.employeeName,
    this.employeeRole,
    this.employeeVoice,
  });

  final BusinessCategory? category;
  final Set<EmployeeSkill> skills;
  final String businessName;
  final String address;
  final String offerings;
  final String pricing;
  final String hours;
  final String location;
  final String whatsapp;
  final String humanNumber;
  final List<KnowledgeInput> knowledge;

  /// Owner overrides on the "Meet your AI employee" screen.
  final String? employeeName;
  final String? employeeRole;

  /// The owner's pick of a man's or woman's voice; template default if null.
  final String? employeeVoice;

  BusinessTemplate get template => templateFor(category);

  /// Suggested employee for the chosen business type + skills.
  AgentTemplate get suggestedAgent => agentForSkills(template, skills);

  OnboardingDraft copyWith({
    BusinessCategory? category,
    Set<EmployeeSkill>? skills,
    String? businessName,
    String? address,
    String? offerings,
    String? pricing,
    String? hours,
    String? location,
    String? whatsapp,
    String? humanNumber,
    List<KnowledgeInput>? knowledge,
    String? employeeName,
    String? employeeRole,
    String? employeeVoice,
  }) => OnboardingDraft(
    category: category ?? this.category,
    skills: skills ?? this.skills,
    businessName: businessName ?? this.businessName,
    address: address ?? this.address,
    offerings: offerings ?? this.offerings,
    pricing: pricing ?? this.pricing,
    hours: hours ?? this.hours,
    location: location ?? this.location,
    whatsapp: whatsapp ?? this.whatsapp,
    humanNumber: humanNumber ?? this.humanNumber,
    knowledge: knowledge ?? this.knowledge,
    employeeName: employeeName ?? this.employeeName,
    employeeRole: employeeRole ?? this.employeeRole,
    employeeVoice: employeeVoice ?? this.employeeVoice,
  );
}

final onboardingProvider =
    NotifierProvider<OnboardingController, OnboardingDraft>(
      OnboardingController.new,
    );

class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() => const OnboardingDraft();

  void update(OnboardingDraft Function(OnboardingDraft) f) => state = f(state);

  void selectCategory(BusinessCategory c) {
    // Pre-select sensible skills for this business type (owner can change).
    final defaults = templateFor(c).agent.defaultSkills.toSet();
    state = state.copyWith(
      category: c,
      skills: state.category == c && state.skills.isNotEmpty
          ? state.skills
          : defaults,
    );
  }

  void toggleSkill(EmployeeSkill s) {
    final next = {...state.skills};
    next.contains(s) ? next.remove(s) : next.add(s);
    state = state.copyWith(skills: next);
  }

  void addKnowledge(KnowledgeInput k) =>
      state = state.copyWith(knowledge: [...state.knowledge, k]);
  void removeKnowledge(KnowledgeInput k) => state = state.copyWith(
    knowledge: state.knowledge.where((e) => e != k).toList(),
  );

  /// Persists business + knowledge (called before "Meet your AI employee").
  Future<void> saveBusiness() async {
    final d = state;
    final repo = ref.read(businessRepoProvider);
    final existing = await repo.getBusiness();
    String? n(String v) => v.trim().isEmpty ? null : v.trim();
    final offerings = d.offerings
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final biz =
        (existing ??
                Business(
                  id: 'biz_new',
                  name: d.businessName,
                  category: d.category ?? BusinessCategory.other,
                ))
            .copyWith(
              name: n(d.businessName) ?? existing?.name,
              category: d.category,
              address: n(d.address),
              offerings: offerings.isEmpty ? null : offerings,
              pricing: n(d.pricing),
              openingHours: n(d.hours),
              location: n(d.location),
              whatsappNumber: n(d.whatsapp),
              humanNumber: n(d.humanNumber),
            );
    await repo.saveBusiness(biz);
    final kRepo = ref.read(knowledgeRepoProvider);
    for (final k in d.knowledge) {
      await kRepo.add(k).drain<void>();
    }
    state = state.copyWith(knowledge: const []);
  }

  /// Creates/updates the AI employee from the template + owner choices.
  Future<Agent> activateEmployee() async {
    final d = state;
    final at = d.suggestedAgent;
    final repo = ref.read(businessRepoProvider);
    final current = await repo.getAgent();
    final role = (d.employeeRole ?? '').trim().isEmpty
        ? at.role
        : d.employeeRole!.trim();
    final name = (d.employeeName ?? '').trim().isEmpty
        ? at.defaultName
        : d.employeeName!.trim();
    final skills = (d.skills.isEmpty ? at.defaultSkills.toSet() : d.skills)
        .map((e) => e.wire)
        .toList();
    final base =
        current ??
        Agent(
          id: 'agent_new',
          name: name,
          role: role,
          status: AgentStatus.active,
          templateId: at.id,
        );
    final agent = base.copyWith(
      name: name,
      role: role,
      status: AgentStatus.active,
      templateId: at.id,
      languages: at.languages,
      goal: at.goal,
      roleKind: EmployeeRoleKind.fromRole(role).name,
      voice: d.employeeVoice ?? at.voice,
      skills: skills,
      capabilities: _capabilitiesFor(skills, at),
      callsToday: current == null ? 0 : null,
    );
    return repo.saveAgent(agent);
  }

  static List<String> _capabilitiesFor(List<String> skills, AgentTemplate at) {
    final caps = <String>[
      'Calling',
      'Lead Qualification',
      'Follow-up',
      'Customer Questions',
    ];
    for (final w in skills) {
      final s = EmployeeSkill.parse(w);
      if (s == null) continue;
      final label = switch (s) {
        EmployeeSkill.bookAppointments => 'Appointment Booking',
        EmployeeSkill.sales => 'Sales Conversations',
        EmployeeSkill.customerSupport => 'Customer Support',
        EmployeeSkill.admissions => 'Admissions Guidance',
        EmployeeSkill.enquiryHandling => 'Enquiry Handling',
        _ => null,
      };
      if (label != null && !caps.contains(label)) caps.add(label);
    }
    caps.addAll(['Callback Scheduling', 'Hot Lead Alerts']);
    return caps;
  }
}
