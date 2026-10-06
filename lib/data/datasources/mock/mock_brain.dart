import 'dart:math';

import '../../models/ai_output.dart';
import '../../models/models.dart';
import '../../templates/templates.dart';

/// An offering in a business catalogue (course, property, service, model…).
class MockOffering {
  const MockOffering(this.name, this.price, this.options, {this.unit = ''});
  final String name;
  final int price;

  /// Template attribute values (batch / slot / configuration…).
  final List<String> options;
  final String unit;
}

/// Vocabulary the simulated AI uses for one vertical. Real phrasing comes from
/// the backend agent template; this only powers demo / mock mode.
class MockVertical {
  const MockVertical({
    required this.offerings,
    required this.optionKey,
    required this.optionNoun,
    required this.positives,
    required this.concerns,
    required this.hotConcern,
    required this.nextStep,
    required this.coldReasons,
  });
  final List<MockOffering> offerings;

  /// Lead.attributes key for the option ("batch", "slot", "config").
  final String optionKey;
  final String optionNoun;
  final List<String> positives;
  final List<String> concerns;
  final String hotConcern;

  /// The single next step the follow-up message proposes.
  final String nextStep;
  final List<String> coldReasons;
}

const _coaching = MockVertical(
  offerings: [
    MockOffering('NEET', 52000, ['Evening', 'Morning', 'Weekend'], unit: '/ year'),
    MockOffering('JEE Main', 56000, ['Evening', 'Weekend'], unit: '/ year'),
    MockOffering('JEE Advanced', 68000, ['Morning', 'Evening'], unit: '/ year'),
    MockOffering('WBJEE', 38000, ['Evening', 'Weekend'], unit: '/ year'),
    MockOffering('Class 10 Boards', 24000, ['Evening', 'Morning'], unit: '/ year'),
    MockOffering('Class 12 Science', 32000, ['Evening', 'Morning'], unit: '/ year'),
  ],
  optionKey: 'batch',
  optionNoun: 'batch',
  positives: ['Asked about pricing', 'Asked about next steps', 'Requested details', 'Agreed to follow up'],
  concerns: ['Fees feel slightly high', 'Centre is a bit far', 'Comparing with another coaching', 'Wants an online option'],
  hotConcern: 'Parent approval needed',
  nextStep: 'schedule a counselling session',
  coldReasons: ['Already joined another coaching', 'Not planning this year', 'Enquired by mistake'],
);

const _generic = MockVertical(
  offerings: [
    MockOffering('Standard plan', 4999, ['This week', 'Next week', 'Weekend']),
    MockOffering('Premium plan', 9999, ['This week', 'Next week']),
    MockOffering('One-time service', 1499, ['Tomorrow', 'This week', 'Weekend']),
  ],
  optionKey: 'timing',
  optionNoun: 'timing',
  positives: ['Asked about pricing', 'Asked about next steps', 'Requested details', 'Agreed to follow up'],
  concerns: ['Price feels slightly high', 'Comparing with another provider', 'Wants to decide later'],
  hotConcern: 'Needs to confirm with family',
  nextStep: 'book a quick call with our team',
  coldReasons: ['Already bought elsewhere', 'Not needed right now', 'Enquired by mistake'],
);

MockVertical verticalFor(BusinessCategory c) => c == BusinessCategory.coaching ? _coaching : _generic;

const _positivePool = ['Asked about pricing', 'Asked about next steps', 'Requested details', 'Agreed to follow up'];

/// Deterministic-ish "AI" that produces the same structured output the real
/// backend would receive from Sarvam's agent output variables.
class MockBrain {
  MockBrain(this.random);
  final Random random;

  T pick<T>(List<T> l) => l[random.nextInt(l.length)];

  DateTime nextEvening({DateTime? from, int hour = 18}) {
    final n = from ?? DateTime.now();
    return DateTime(n.year, n.month, n.day, hour).add(const Duration(days: 1));
  }

  MockOffering offeringFor(MockVertical v, String? name) =>
      v.offerings.firstWhere((o) => name != null && name.startsWith(o.name), orElse: () => v.offerings.first);

  AiCallOutput think({
    required Lead lead,
    required LeadTemperature temperature,
    required Business business,
    required Agent agent,
    int? forcedScore,
  }) {
    final v = verticalFor(business.category);
    final o = offeringFor(v, lead.interest);
    final String option = lead.attributes[v.optionKey] ?? pick(o.options);
    final first = lead.firstName;
    final what = '${o.name} (${option.toLowerCase()} ${v.optionNoun})';

    late int score;
    late LeadIntent intent;
    late List<String> positives;
    late List<String> concerns;
    late String summary;
    late NextAction next;
    DateTime? callbackAt;
    String? message;

    switch (temperature) {
      case LeadTemperature.hot:
        score = forcedScore ?? 76 + random.nextInt(20);
        intent = LeadIntent.interested;
        positives = List.of(_positivePool);
        concerns = [random.nextInt(3) == 0 ? pick(v.concerns) : v.hotConcern];
        summary =
            '$first is interested in $what and wants more information. '
            'They asked about pricing and next steps – ${concerns.first.toLowerCase()}.';
        next = NextAction.whatsappAndCallback;
        callbackAt = nextEvening();
        message =
            'Hi $first 👋\n\n'
            'Great speaking with you today. As discussed, here are the details:\n\n'
            '📌 ${o.name} – $option\n'
            '💰 ${_price(o)}\n\n'
            'Would you like to ${v.nextStep}? Just reply here.\n\n'
            '– ${business.name}';
      case LeadTemperature.warm:
        score = forcedScore ?? 48 + random.nextInt(24);
        intent = LeadIntent.exploring;
        positives = [
          'Requested details',
          pick(['Asked about pricing', 'Asked about next steps']),
        ];
        concerns = [pick(v.concerns)];
        summary = '$first is exploring $what. They asked for details on WhatsApp, but ${concerns.first.toLowerCase()}.';
        next = NextAction.sendWhatsapp;
        if (random.nextBool()) callbackAt = nextEvening(hour: 17);
        message =
            'Hi $first 👋\n\n'
            'Thanks for your time today! Here are the details you asked for:\n\n'
            '📌 ${o.name} – $option\n'
            '💰 ${_price(o)}\n\n'
            'Happy to answer any questions – just reply here.\n\n'
            '– ${business.name}';
      case LeadTemperature.cold:
      case LeadTemperature.unknown:
        score = forcedScore ?? 10 + random.nextInt(30);
        intent = LeadIntent.notInterested;
        positives = const [];
        concerns = [pick(v.coldReasons)];
        summary = '$first is not looking right now – ${concerns.first.toLowerCase()}. ${agent.name} thanked them and closed politely.';
        next = NextAction.none;
        message = null;
    }

    return AiCallOutput(
      leadScore: score,
      intent: intent,
      temperature: LeadTemperature.fromScore(score),
      interest: o.name,
      attributes: {v.optionKey: option, if (temperature == LeadTemperature.hot) 'budget': '${o.price}'},
      objections: concerns,
      positiveSignals: positives,
      summary: summary,
      nextAction: next,
      callbackAt: callbackAt,
      whatsappFollowupRequired: message != null,
      whatsappMessage: message,
      language: pick(['English', 'Hindi', 'Bengali', 'English']),
    );
  }

  CallTranscript transcript({required Lead lead, required AiCallOutput out, required Business business, required Agent agent}) {
    final v = verticalFor(business.category);
    final first = lead.firstName;
    final o = offeringFor(v, out.interest);
    final option = out.attributes[v.optionKey] ?? o.options.first;
    final human = templateFor(business.category).workflow.humanLabel.toLowerCase();
    final lines = <(TranscriptSpeaker, String)>[
      (
        TranscriptSpeaker.agent,
        'Hello, am I speaking with $first? This is ${agent.name}, an AI assistant from ${business.name}. '
            'You had enquired about ${o.name} – is this a good time for two minutes?',
      ),
      (TranscriptSpeaker.lead, pick(['Haan, yes, tell me.', 'Yes, go ahead.', 'Ji, boliye.'])),
      (TranscriptSpeaker.agent, 'Great! Which ${v.optionNoun} would suit you best?'),
    ];
    switch (out.temperature) {
      case LeadTemperature.hot:
        lines.addAll([
          (TranscriptSpeaker.lead, '$option would be better for me. What is the price?'),
          (TranscriptSpeaker.agent, 'It is ${_price(o)}, and we can start right away.'),
          (TranscriptSpeaker.lead, 'Okay, that sounds good. What are the next steps?'),
          (TranscriptSpeaker.agent, 'I can have our $human call you tomorrow around 6 PM to take it forward. Does that work?'),
          (TranscriptSpeaker.lead, 'Yes, that works. Please send the details on WhatsApp too.'),
          (TranscriptSpeaker.agent, 'Perfect – I\'ll share everything on WhatsApp. Thank you, $first!'),
        ]);
      case LeadTemperature.warm:
        lines.addAll([
          (TranscriptSpeaker.lead, 'I\'m still exploring options, but $option might work.'),
          (TranscriptSpeaker.agent, 'That\'s completely fine. Shall I send you the details so you can decide at your pace?'),
          (TranscriptSpeaker.lead, 'Yes, please send them on WhatsApp.'),
          (TranscriptSpeaker.agent, 'Absolutely, I\'ll send them right after this call. Thank you, $first!'),
        ]);
      case LeadTemperature.cold:
      case LeadTemperature.unknown:
        lines.addAll([
          (TranscriptSpeaker.lead, 'Actually, not right now. ${out.objections.isEmpty ? '' : out.objections.first}.'),
          (TranscriptSpeaker.agent, 'No problem at all, thank you for letting me know. Have a great day!'),
        ]);
    }
    var t = 0;
    return CallTranscript(
      language: out.language,
      lines: [
        for (final l in lines)
          TranscriptLine(
            speaker: l.$1,
            text: l.$2,
            offset: Duration(seconds: t += 6 + random.nextInt(9)),
          ),
      ],
    );
  }

  String outcomeText(AiCallOutput out) => switch (out.temperature) {
    LeadTemperature.hot => 'Interested – wants a human follow-up',
    LeadTemperature.warm => 'Exploring – details requested',
    _ => 'Not interested right now',
  };

  static String _price(MockOffering o) => '₹${_inr(o.price)}${o.unit.isEmpty ? '' : ' ${o.unit}'}';

  static String _inr(int v) {
    final s = v.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }
}

const mockFirstNames = [
  'Aarav',
  'Aditi',
  'Ananya',
  'Arjun',
  'Debjani',
  'Dipankar',
  'Ishita',
  'Kabir',
  'Koushik',
  'Meghna',
  'Nikhil',
  'Pooja',
  'Rohan',
  'Sayan',
  'Shreya',
  'Soumya',
  'Tanmoy',
  'Tanya',
  'Vikram',
  'Zoya',
  'Rupam',
  'Payel',
  'Abhishek',
  'Moumita',
  'Sourav',
  'Neha',
  'Aman',
  'Sana',
  'Rajdeep',
  'Tithi',
  'Harsh',
  'Kriti',
  'Anirban',
  'Srijita',
  'Imran',
  'Farhan',
  'Ayesha',
  'Sudipta',
  'Bikram',
  'Laboni',
];

const mockLastNames = [
  'Sharma',
  'Ghosh',
  'Banerjee',
  'Chatterjee',
  'Mukherjee',
  'Das',
  'Roy',
  'Sen',
  'Gupta',
  'Verma',
  'Singh',
  'Yadav',
  'Mondal',
  'Saha',
  'Paul',
  'Biswas',
  'Khan',
  'Ahmed',
  'Dutta',
  'Bose',
  'Mishra',
  'Pandey',
  'Hansda',
  'Tudu',
  'Sarkar',
];

const mockSources = ['Facebook Ad', 'Website form', 'Google Ads', 'Referral', 'Walk-in enquiry', 'Instagram', 'JustDial'];
