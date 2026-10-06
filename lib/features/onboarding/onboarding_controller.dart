import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/models.dart';
import '../../data/templates/templates.dart';

class OnboardingDraft {
  const OnboardingDraft({
    this.category = BusinessCategory.coaching,
    this.businessName = '',
    this.address = '',
    this.offerings = '',
    this.fees = '',
    this.hours = '',
    this.location = '',
    this.whatsapp = '',
    this.counsellor = '',
    this.knowledge = const [],
  });

  final BusinessCategory category;
  final String businessName;
  final String address;
  final String offerings;
  final String fees;
  final String hours;
  final String location;
  final String whatsapp;
  final String counsellor;
  final List<KnowledgeInput> knowledge;

  OnboardingDraft copyWith({
    BusinessCategory? category,
    String? businessName,
    String? address,
    String? offerings,
    String? fees,
    String? hours,
    String? location,
    String? whatsapp,
    String? counsellor,
    List<KnowledgeInput>? knowledge,
  }) => OnboardingDraft(
    category: category ?? this.category,
    businessName: businessName ?? this.businessName,
    address: address ?? this.address,
    offerings: offerings ?? this.offerings,
    fees: fees ?? this.fees,
    hours: hours ?? this.hours,
    location: location ?? this.location,
    whatsapp: whatsapp ?? this.whatsapp,
    counsellor: counsellor ?? this.counsellor,
    knowledge: knowledge ?? this.knowledge,
  );
}

final onboardingProvider = NotifierProvider<OnboardingController, OnboardingDraft>(OnboardingController.new);

class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() => const OnboardingDraft();

  void update(OnboardingDraft Function(OnboardingDraft) f) => state = f(state);

  void addKnowledge(KnowledgeInput k) => state = state.copyWith(knowledge: [...state.knowledge, k]);
  void removeKnowledge(KnowledgeInput k) => state = state.copyWith(knowledge: state.knowledge.where((e) => e != k).toList());

  /// Persists business + agent + knowledge. Returns the created agent.
  Future<Agent> createAgent() async {
    final d = state;
    final tpl = templateFor(d.category);
    final repo = ref.read(businessRepoProvider);
    final existing = await repo.getBusiness();
    final offerings = d.offerings.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final biz = (existing ?? Business(id: 'biz_new', name: d.businessName, category: d.category)).copyWith(
      name: d.businessName.trim().isEmpty ? existing?.name : d.businessName.trim(),
      category: d.category,
      address: d.address.trim().isEmpty ? null : d.address.trim(),
      offerings: offerings.isEmpty ? null : offerings,
      fees: d.fees.trim().isEmpty ? null : d.fees.trim(),
      openingHours: d.hours.trim().isEmpty ? null : d.hours.trim(),
      location: d.location.trim().isEmpty ? null : d.location.trim(),
      whatsappNumber: d.whatsapp.trim().isEmpty ? null : d.whatsapp.trim(),
      counsellorNumber: d.counsellor.trim().isEmpty ? null : d.counsellor.trim(),
    );
    await repo.saveBusiness(biz);

    final kRepo = ref.read(knowledgeRepoProvider);
    for (final k in d.knowledge) {
      await kRepo.add(k).drain<void>();
    }

    final current = await repo.getAgent();
    final at = tpl.agent ?? coachingAgentTemplate;
    final agent = (current ?? Agent(id: 'agent_new', name: at.defaultName, role: at.role, status: AgentStatus.active, templateId: at.id))
        .copyWith(status: AgentStatus.active, languages: at.languages, goal: at.goal);
    return repo.saveAgent(agent);
  }
}
