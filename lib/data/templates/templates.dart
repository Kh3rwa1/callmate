import '../models/enums.dart';

/// Category templates. The app UI is category-agnostic: a new vertical ships
/// by adding a BusinessTemplate (+ backend agent config), not by redesigning.
///
/// The authoritative agent instructions / output schema live on the backend
/// (see backend/templates/coaching_admissions_v1.json). The app only holds the
/// human-readable parts needed for onboarding and the AI Employee screen.

class AgentTemplate {
  const AgentTemplate({
    required this.id,
    required this.defaultName,
    required this.role,
    required this.goal,
    required this.languages,
    required this.capabilities,
    required this.callPurpose,
  });
  final String id;
  final String defaultName;
  final String role;
  final String goal;
  final List<String> languages;
  final List<String> capabilities;
  final String callPurpose;
}

class WorkflowTemplate {
  const WorkflowTemplate({
    required this.id,
    required this.leadNoun,
    required this.interestLabel,
    required this.offeringsLabel,
    required this.offeringsHint,
    required this.counsellorLabel,
    required this.sampleLeadName,
    required this.sampleLeadInterest,
    required this.estimatedMinutesPerCall,
  });
  final String id;
  final String leadNoun; // "student"
  final String interestLabel; // "Course"
  final String offeringsLabel; // "Courses"
  final String offeringsHint;
  final String counsellorLabel; // "Counsellor"
  final String sampleLeadName;
  final String sampleLeadInterest;
  final double estimatedMinutesPerCall;
}

class BusinessTemplate {
  const BusinessTemplate({required this.category, required this.available, this.agent, this.workflow});
  final BusinessCategory category;
  final bool available;
  final AgentTemplate? agent;
  final WorkflowTemplate? workflow;
}

const coachingAgentTemplate = AgentTemplate(
  id: 'coaching_admissions_v1',
  defaultName: 'Riya',
  role: 'Admissions Assistant',
  goal: 'Convert enquiries into counselling appointments',
  languages: ['Bengali', 'Hindi', 'English'],
  callPurpose: 'Admission enquiry follow-up',
  capabilities: [
    'Call new leads',
    'Answer FAQs',
    'Qualify leads',
    'Collect information',
    'Recommend next actions',
    'Generate WhatsApp follow-ups',
    'Schedule callbacks',
    'Transfer hot leads',
  ],
);

const coachingWorkflowTemplate = WorkflowTemplate(
  id: 'coaching_admissions_workflow_v1',
  leadNoun: 'student',
  interestLabel: 'Course',
  offeringsLabel: 'Courses',
  offeringsHint: 'e.g. NEET, JEE Main, Class 10 Boards',
  counsellorLabel: 'Counsellor',
  sampleLeadName: 'Rahul Kumar',
  sampleLeadInterest: 'NEET · Evening Batch',
  estimatedMinutesPerCall: 2.2,
);

const businessTemplates = <BusinessTemplate>[
  BusinessTemplate(category: BusinessCategory.coaching, available: true, agent: coachingAgentTemplate, workflow: coachingWorkflowTemplate),
  BusinessTemplate(category: BusinessCategory.realEstate, available: false),
  BusinessTemplate(category: BusinessCategory.automobile, available: false),
  BusinessTemplate(category: BusinessCategory.salon, available: false),
  BusinessTemplate(category: BusinessCategory.localServices, available: false),
  BusinessTemplate(category: BusinessCategory.clinic, available: false),
  BusinessTemplate(category: BusinessCategory.other, available: false),
];

BusinessTemplate templateFor(BusinessCategory c) =>
    businessTemplates.firstWhere((t) => t.category == c, orElse: () => businessTemplates.first);
