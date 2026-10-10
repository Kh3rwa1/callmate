import '../models/enums.dart';
import '../../services/voice/voice_persona.dart';

/// ---------------------------------------------------------------------------
/// CallPilot template architecture.
///
///   BusinessTemplate  – one per business type (vocabulary, defaults, flows)
///     ├─ AgentTemplate     – suggested AI employee (name, role, goal, skills)
///     └─ WorkflowTemplate  – what happens per call (fields, outcomes, follow-up)
///
/// The UI reads ONLY from these + the live Agent/Business. Adding a vertical =
/// adding a template here (and its backend agent config), never a redesign.
/// Coaching Centre is simply the first, fully tuned template.
/// ---------------------------------------------------------------------------

/// What an AI employee can be hired to do (onboarding step 3).
enum EmployeeSkill {
  makeCalls('make_calls', 'Make Calls', '📞'),
  qualifyLeads('qualify_leads', 'Qualify Leads', '🎯'),
  followUp('follow_up', 'Follow Up', '💬'),
  bookAppointments('book_appointments', 'Book Appointments', '📅'),
  sales('sales', 'Sales', '💼'),
  customerSupport('customer_support', 'Customer Support', '🎧'),
  admissions('admissions', 'Admissions', '🎓'),
  enquiryHandling('enquiry_handling', 'Enquiry Handling', '❓');

  const EmployeeSkill(this.wire, this.label, this.emoji);
  final String wire;
  final String label;
  final String emoji;

  static EmployeeSkill? parse(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }
}

/// Visual role of the mascot – drives accessory/badge, not identity.
enum EmployeeRoleKind {
  sales('💼', 'Sales'),
  appointments('📅', 'Appointments'),
  support('💬', 'Support'),
  admissions('📚', 'Admissions'),
  reception('🛎️', 'Reception'),
  general('📞', 'Calling');

  const EmployeeRoleKind(this.badge, this.label);
  final String badge;
  final String label;

  static EmployeeRoleKind parse(String? v) => EmployeeRoleKind.values
      .firstWhere((e) => e.name == v, orElse: () => EmployeeRoleKind.general);

  static EmployeeRoleKind fromRole(String role) {
    final r = role.toLowerCase();
    if (r.contains('admission')) return EmployeeRoleKind.admissions;
    if (r.contains('appointment') || r.contains('booking')) {
      return EmployeeRoleKind.appointments;
    }
    if (r.contains('support')) return EmployeeRoleKind.support;
    if (r.contains('reception') || r.contains('enquiry')) {
      return EmployeeRoleKind.reception;
    }
    if (r.contains('sales')) return EmployeeRoleKind.sales;
    return EmployeeRoleKind.general;
  }
}

class AgentTemplate {
  const AgentTemplate({
    required this.id,
    required this.defaultName,
    required this.role,
    required this.roleKind,
    required this.goal,
    required this.languages,
    required this.capabilities,
    required this.callPurpose,
    this.defaultSkills = const [],
    this.voice = femaleVoice,
  });
  final String id;
  final String defaultName;

  /// Default voice; matches [defaultName] (Arjun speaks as a man).
  final String voice;
  final String role;
  final EmployeeRoleKind roleKind;
  final String goal;
  final List<String> languages;
  final List<String> capabilities;
  final String callPurpose;
  final List<EmployeeSkill> defaultSkills;
}

/// Business-specific lead attribute (stored in Lead.attributes, never global).
class LeadAttributeDef {
  const LeadAttributeDef(this.key, this.label, {this.emoji = '•'});
  final String key;
  final String label;
  final String emoji;
}

class WorkflowTemplate {
  const WorkflowTemplate({
    required this.id,
    required this.customerNoun,
    required this.interestLabel,
    required this.interestOptions,
    required this.offeringsLabel,
    required this.offeringsHint,
    required this.humanLabel,
    required this.knowledgeHint,
    required this.sampleLeadName,
    required this.sampleLeadInterest,
    required this.sampleLeadQuote,
    required this.testCallerHint,
    this.attributes = const [],
    this.estimatedMinutesPerCall = 2.2,
  });

  /// "customer" / "student" / "patient" / "buyer"
  final String customerNoun;

  /// Label of Lead.interest in this vertical ("Interest", "Course", "Property").
  final String interestLabel;
  final List<String> interestOptions;
  final String offeringsLabel;
  final String offeringsHint;

  /// Who does the human follow-up ("Team member", "Counsellor", "Agent").
  final String humanLabel;
  final String knowledgeHint;
  final String sampleLeadName;
  final String sampleLeadInterest;
  final String sampleLeadQuote;
  final String testCallerHint;
  final List<LeadAttributeDef> attributes;
  final double estimatedMinutesPerCall;
  final String id;
}

class BusinessTemplate {
  const BusinessTemplate({
    required this.category,
    required this.agent,
    required this.workflow,
    this.tuned = false,
  });
  final BusinessCategory category;
  final AgentTemplate agent;
  final WorkflowTemplate workflow;

  /// Fully tuned conversation design (V1: coaching). Others use the generic
  /// sales/enquiry flow and are still fully usable.
  final bool tuned;
}

// ===================================================================== Agents

const _langs = ['English', 'Hindi', 'Bengali'];

const genericCapabilities = [
  'Calling',
  'Lead Qualification',
  'Follow-up',
  'Customer Questions',
  'Callback Scheduling',
  'Hot Lead Alerts',
];

const salesAgentTemplate = AgentTemplate(
  id: 'generic_sales_v1',
  defaultName: 'Maya',
  role: 'Sales Assistant',
  roleKind: EmployeeRoleKind.sales,
  goal: 'Convert enquiries into qualified opportunities',
  languages: _langs,
  capabilities: genericCapabilities,
  callPurpose: 'Enquiry follow-up',
  defaultSkills: [
    EmployeeSkill.makeCalls,
    EmployeeSkill.qualifyLeads,
    EmployeeSkill.followUp,
    EmployeeSkill.sales,
  ],
);

const coachingAgentTemplate = AgentTemplate(
  id: 'coaching_admissions_v1',
  defaultName: 'Riya',
  role: 'Admissions Assistant',
  roleKind: EmployeeRoleKind.admissions,
  goal: 'Convert enquiries into counselling appointments',
  languages: _langs,
  capabilities: [...genericCapabilities, 'Admissions guidance'],
  callPurpose: 'Admission enquiry follow-up',
  defaultSkills: [
    EmployeeSkill.makeCalls,
    EmployeeSkill.qualifyLeads,
    EmployeeSkill.followUp,
    EmployeeSkill.admissions,
  ],
);

const appointmentAgentTemplate = AgentTemplate(
  id: 'generic_appointments_v1',
  defaultName: 'Arjun',
  voice: maleVoice,
  role: 'Appointment Assistant',
  roleKind: EmployeeRoleKind.appointments,
  goal: 'Turn enquiries into booked appointments',
  languages: _langs,
  capabilities: [...genericCapabilities, 'Appointment Booking'],
  callPurpose: 'Appointment enquiry follow-up',
  defaultSkills: [
    EmployeeSkill.makeCalls,
    EmployeeSkill.bookAppointments,
    EmployeeSkill.followUp,
    EmployeeSkill.enquiryHandling,
  ],
);

// ================================================================= Workflows

const genericWorkflow = WorkflowTemplate(
  id: 'generic_enquiry_v1',
  customerNoun: 'customer',
  interestLabel: 'Interest',
  interestOptions: [
    'Product enquiry',
    'Service enquiry',
    'Pricing',
    'Demo / visit',
    'Other',
  ],
  offeringsLabel: 'Products / services',
  offeringsHint: 'e.g. Home cleaning, AC repair, Pest control',
  humanLabel: 'Team member',
  knowledgeHint: 'Services, pricing, opening hours, location, policies, FAQs',
  sampleLeadName: 'Rahul Kumar',
  sampleLeadInterest: 'Asked about pricing',
  sampleLeadQuote:
      '“Hi, I saw your ad. Can you tell me the price and how soon you can start?”',
  testCallerHint: 'Pretend you\'re a customer asking about your services.',
);

const coachingWorkflow = WorkflowTemplate(
  id: 'coaching_admissions_workflow_v1',
  customerNoun: 'student',
  interestLabel: 'Course',
  interestOptions: [
    'NEET',
    'JEE Main',
    'JEE Advanced',
    'WBJEE',
    'Class 10 Boards',
    'Class 12 Science',
    'Foundation (Class 9)',
  ],
  offeringsLabel: 'Courses',
  offeringsHint: 'e.g. NEET, JEE Main, Class 10 Boards',
  humanLabel: 'Counsellor',
  knowledgeHint: 'Courses, fees, batch timings, faculty, results, FAQs',
  sampleLeadName: 'Rahul Kumar',
  sampleLeadInterest: 'NEET · Evening batch',
  sampleLeadQuote:
      '“Hi, I filled a form for NEET coaching. What are the fees?”',
  testCallerHint: 'Pretend you\'re a parent asking about admission.',
  attributes: [
    LeadAttributeDef('batch', 'Batch', emoji: '🕒'),
    LeadAttributeDef('budget', 'Budget', emoji: '💰'),
  ],
);

const realEstateWorkflow = WorkflowTemplate(
  id: 'real_estate_enquiry_v1',
  customerNoun: 'buyer',
  interestLabel: 'Property',
  interestOptions: ['2 BHK', '3 BHK', 'Villa', 'Plot', 'Commercial'],
  offeringsLabel: 'Projects / properties',
  offeringsHint: 'e.g. Green Valley 2 & 3 BHK, Lake View Plots',
  humanLabel: 'Sales agent',
  knowledgeHint: 'Projects, prices, possession dates, amenities, location',
  sampleLeadName: 'Rahul Kumar',
  sampleLeadInterest: '3 BHK · Site visit',
  sampleLeadQuote: '“I saw the Green Valley ad. What\'s the price of a 3 BHK?”',
  testCallerHint: 'Pretend you\'re a buyer enquiring about a property.',
  attributes: [
    LeadAttributeDef('budget', 'Budget', emoji: '💰'),
    LeadAttributeDef('location', 'Preferred area', emoji: '📍'),
  ],
);

const clinicWorkflow = WorkflowTemplate(
  id: 'clinic_appointments_v1',
  customerNoun: 'patient',
  interestLabel: 'Service',
  interestOptions: [
    'Consultation',
    'Follow-up visit',
    'Health check-up',
    'Procedure enquiry',
  ],
  offeringsLabel: 'Services / departments',
  offeringsHint: 'e.g. General physician, Dental, Dermatology',
  humanLabel: 'Front desk',
  knowledgeHint: 'Doctors, timings, consultation fees, location, policies',
  sampleLeadName: 'Rahul Kumar',
  sampleLeadInterest: 'Consultation · Evening',
  sampleLeadQuote:
      '“I want to book a consultation. Is the doctor available this evening?”',
  testCallerHint: 'Pretend you\'re a patient wanting an appointment.',
  attributes: [LeadAttributeDef('slot', 'Preferred slot', emoji: '🕒')],
);

const automobileWorkflow = WorkflowTemplate(
  id: 'automobile_sales_v1',
  customerNoun: 'buyer',
  interestLabel: 'Model',
  interestOptions: ['Hatchback', 'Sedan', 'SUV', 'EV', 'Service booking'],
  offeringsLabel: 'Models / services',
  offeringsHint: 'e.g. City, Amaze, Elevate, Servicing',
  humanLabel: 'Sales executive',
  knowledgeHint: 'Models, on-road prices, offers, test drives, service plans',
  sampleLeadName: 'Rahul Kumar',
  sampleLeadInterest: 'SUV · Test drive',
  sampleLeadQuote:
      '“What\'s the on-road price of the SUV? Can I book a test drive?”',
  testCallerHint: 'Pretend you\'re a buyer asking about a car.',
  attributes: [LeadAttributeDef('budget', 'Budget', emoji: '💰')],
);

const salonWorkflow = WorkflowTemplate(
  id: 'salon_appointments_v1',
  customerNoun: 'client',
  interestLabel: 'Service',
  interestOptions: ['Haircut', 'Hair colour', 'Facial', 'Bridal', 'Spa'],
  offeringsLabel: 'Services',
  offeringsHint: 'e.g. Haircut, Colour, Facial, Bridal makeup',
  humanLabel: 'Stylist',
  knowledgeHint: 'Services, price list, timings, offers, location',
  sampleLeadName: 'Rahul Kumar',
  sampleLeadInterest: 'Haircut · Saturday',
  sampleLeadQuote: '“Do you have a slot on Saturday for a haircut?”',
  testCallerHint: 'Pretend you\'re a client booking an appointment.',
  attributes: [LeadAttributeDef('slot', 'Preferred slot', emoji: '🕒')],
);

// ================================================================= Templates

const businessTemplates = <BusinessTemplate>[
  BusinessTemplate(
    category: BusinessCategory.coaching,
    agent: coachingAgentTemplate,
    workflow: coachingWorkflow,
    tuned: true,
  ),
  BusinessTemplate(
    category: BusinessCategory.realEstate,
    agent: salesAgentTemplate,
    workflow: realEstateWorkflow,
  ),
  BusinessTemplate(
    category: BusinessCategory.clinic,
    agent: appointmentAgentTemplate,
    workflow: clinicWorkflow,
  ),
  BusinessTemplate(
    category: BusinessCategory.diagnostic,
    agent: appointmentAgentTemplate,
    workflow: clinicWorkflow,
  ),
  BusinessTemplate(
    category: BusinessCategory.automobile,
    agent: salesAgentTemplate,
    workflow: automobileWorkflow,
  ),
  BusinessTemplate(
    category: BusinessCategory.salon,
    agent: appointmentAgentTemplate,
    workflow: salonWorkflow,
  ),
  BusinessTemplate(
    category: BusinessCategory.restaurant,
    agent: appointmentAgentTemplate,
    workflow: genericWorkflow,
  ),
  BusinessTemplate(
    category: BusinessCategory.retail,
    agent: salesAgentTemplate,
    workflow: genericWorkflow,
  ),
  BusinessTemplate(
    category: BusinessCategory.localServices,
    agent: salesAgentTemplate,
    workflow: genericWorkflow,
  ),
  BusinessTemplate(
    category: BusinessCategory.other,
    agent: salesAgentTemplate,
    workflow: genericWorkflow,
  ),
];

BusinessTemplate templateFor(BusinessCategory? c) => businessTemplates
    .firstWhere((t) => t.category == c, orElse: () => businessTemplates.last);

/// Suggests a role + mascot kind from the chosen skills (onboarding step 3).
AgentTemplate agentForSkills(BusinessTemplate base, Set<EmployeeSkill> skills) {
  if (skills.isEmpty) return base.agent;
  if (skills.contains(EmployeeSkill.admissions)) return coachingAgentTemplate;
  if (skills.contains(EmployeeSkill.bookAppointments) &&
      !skills.contains(EmployeeSkill.sales)) {
    return appointmentAgentTemplate;
  }
  if (skills.contains(EmployeeSkill.customerSupport) &&
      !skills.contains(EmployeeSkill.sales)) {
    return const AgentTemplate(
      id: 'generic_support_v1',
      defaultName: 'Maya',
      role: 'Support Assistant',
      roleKind: EmployeeRoleKind.support,
      goal: 'Answer customer questions and resolve enquiries quickly',
      languages: _langs,
      capabilities: genericCapabilities,
      callPurpose: 'Customer support follow-up',
    );
  }
  if (skills.contains(EmployeeSkill.sales) ||
      skills.contains(EmployeeSkill.qualifyLeads)) {
    return salesAgentTemplate;
  }
  return base.agent;
}
