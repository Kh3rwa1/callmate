import 'dart:math';

import '../../models/ai_output.dart';
import '../../models/models.dart';

/// Course catalogue used by the demo coaching centre.
class MockCourse {
  const MockCourse(this.name, this.fee, this.batches);
  final String name;
  final int fee;
  final List<String> batches;
}

const mockCourses = [
  MockCourse('NEET', 52000, ['Evening', 'Morning', 'Weekend']),
  MockCourse('JEE Main', 56000, ['Evening', 'Weekend']),
  MockCourse('JEE Advanced', 68000, ['Morning', 'Evening']),
  MockCourse('WBJEE', 38000, ['Evening', 'Weekend']),
  MockCourse('Class 10 Boards', 24000, ['Evening', 'Morning']),
  MockCourse('Class 12 Science', 32000, ['Evening', 'Morning']),
  MockCourse('Foundation (Class 9)', 21000, ['Weekend', 'Evening']),
];

MockCourse courseNamed(String? name) =>
    mockCourses.firstWhere((c) => name != null && name.startsWith(c.name), orElse: () => mockCourses.first);

const _positivePool = [
  'Asked about pricing',
  'Asked about admission date',
  'Requested details on WhatsApp',
  'Agreed to follow-up',
  'Asked about batch timing',
  'Asked for a demo class',
  'Mentioned target exam year',
];

const _concernPool = [
  'Parent approval needed',
  'Fees feel slightly high',
  'Centre is a bit far',
  'Comparing with another coaching',
  'Wants an online option',
];

/// Deterministic-ish "AI" that produces the same structured output the real
/// backend would receive from Sarvam's agent output variables.
class MockBrain {
  MockBrain(this.random);
  final Random random;

  T pick<T>(List<T> l) => l[random.nextInt(l.length)];

  DateTime nextEvening({DateTime? from, int hour = 18}) {
    final n = from ?? DateTime.now();
    final t = DateTime(n.year, n.month, n.day, hour).add(const Duration(days: 1));
    return t;
  }

  AiCallOutput think({
    required Lead lead,
    required LeadTemperature temperature,
    required Business business,
    required Agent agent,
    int? forcedScore,
  }) {
    final course = courseNamed(lead.courseInterest);
    final String batch = lead.preferredBatch ?? pick(course.batches);
    final first = lead.firstName;

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
        positives = ['Asked about pricing', 'Asked about admission date', 'Requested details', 'Agreed to follow-up'];
        concerns = [
          pick(['Parent approval needed', 'Parent approval needed', 'Fees feel slightly high']),
        ];
        final parentNote = concerns.first.startsWith('Parent')
            ? 'wants to discuss admission with $_their parents'
            : 'felt the fees are slightly high but is keen';
        summary =
            '$first is interested in the ${course.name} ${batch.toLowerCase()} batch. $_they asked about fees and the admission date and $parentNote.';
        next = NextAction.whatsappAndCallback;
        callbackAt = nextEvening();
        message =
            'Hi $first 👋\n\n'
            'Great speaking with you today. As discussed, I\'m sharing the ${course.name} ${batch.toLowerCase()} batch details:\n\n'
            '📚 ${course.name} – $batch batch\n'
            '💰 ₹${_inr(course.fee)} / year (easy instalments)\n'
            '🗓 New batch starts soon – limited seats\n\n'
            'Please let me know if you\'d like to schedule a counselling session with your parents.\n\n'
            '– ${business.name}';
      case LeadTemperature.warm:
        score = forcedScore ?? 48 + random.nextInt(24);
        intent = LeadIntent.exploring;
        positives = [
          pick(['Asked about batch timing', 'Asked for a demo class']),
          'Requested details on WhatsApp',
        ];
        concerns = [pick(_concernPool.sublist(1))];
        summary =
            '$first is exploring options for ${course.name}. $_they liked the $batch batch timing and asked for details on WhatsApp, but ${concerns.first.toLowerCase()}.';
        next = NextAction.sendWhatsapp;
        if (random.nextBool()) callbackAt = nextEvening(hour: 17);
        message =
            'Hi $first 👋\n\n'
            'Thanks for your time today! Here are the ${course.name} details you asked for:\n\n'
            '📚 $batch batch\n'
            '💰 ₹${_inr(course.fee)} / year\n\n'
            'You\'re welcome to attend a free demo class this week – just reply here and we\'ll book a slot.\n\n'
            '– ${business.name}';
      case LeadTemperature.cold:
      case LeadTemperature.unknown:
        score = forcedScore ?? 10 + random.nextInt(30);
        intent = LeadIntent.notInterested;
        positives = const [];
        concerns = [
          pick(['Already joined another coaching', 'Not planning this year', 'Enquired by mistake']),
        ];
        summary = '$first is not looking right now – ${concerns.first.toLowerCase()}. Riya thanked them and closed politely.';
        next = NextAction.none;
        message = null;
    }

    return AiCallOutput(
      leadScore: score,
      intent: intent,
      temperature: LeadTemperature.fromScore(score),
      courseInterest: course.name,
      preferredBatch: batch,
      budget: temperature == LeadTemperature.hot ? '${course.fee}' : null,
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
    final first = lead.firstName;
    final course = courseNamed(out.courseInterest);
    final batch = out.preferredBatch ?? 'Evening';
    final lines = <(TranscriptSpeaker, String)>[
      (
        TranscriptSpeaker.agent,
        'Hello, am I speaking with $first? This is ${agent.name}, an AI admissions assistant from ${business.name}. '
            'You had enquired about our ${course.name} course – is this a good time for two minutes?',
      ),
      (TranscriptSpeaker.lead, pick(['Haan, yes, tell me.', 'Yes, go ahead.', 'Ji, boliye.'])),
      (TranscriptSpeaker.agent, 'Great! Would you prefer a morning, evening or weekend batch?'),
    ];
    switch (out.temperature) {
      case LeadTemperature.hot:
        lines.addAll([
          (TranscriptSpeaker.lead, '$batch would be better for me.'),
          (
            TranscriptSpeaker.agent,
            'Our ${course.name} $batch batch has small groups and weekly mock tests. Would you like to know about the fees?',
          ),
          (TranscriptSpeaker.lead, 'Yes, what are the fees? And when does admission start?'),
          (
            TranscriptSpeaker.agent,
            'The fee is ₹${_inr(course.fee)} per year, payable in three instalments. Admissions for the new batch are open now.',
          ),
          (TranscriptSpeaker.lead, 'Okay, that sounds good. I\'ll need to discuss it with my parents once.'),
          (
            TranscriptSpeaker.agent,
            'Of course! Shall I ask our counsellor to call tomorrow around 6 PM, when your parents are also available?',
          ),
          (TranscriptSpeaker.lead, 'Yes, that works. Please send the details on WhatsApp too.'),
          (TranscriptSpeaker.agent, 'Perfect – I\'ll share everything on WhatsApp. Thank you, $first, have a lovely day!'),
        ]);
      case LeadTemperature.warm:
        lines.addAll([
          (TranscriptSpeaker.lead, 'I\'m still exploring options, but $batch might work.'),
          (TranscriptSpeaker.agent, 'That\'s completely fine. We also offer a free demo class so you can experience the teaching first.'),
          (TranscriptSpeaker.lead, 'Okay. Can you send the details on WhatsApp?'),
          (TranscriptSpeaker.agent, 'Absolutely, I\'ll send them right after this call. Thank you, $first!'),
        ]);
      case LeadTemperature.cold:
      case LeadTemperature.unknown:
        lines.addAll([
          (TranscriptSpeaker.lead, 'Actually, not right now. ${out.objections.isEmpty ? '' : out.objections.first}.'),
          (
            TranscriptSpeaker.agent,
            'No problem at all, thank you for letting me know. If anything changes, we\'re always happy to help. Have a great day!',
          ),
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
    LeadTemperature.hot => 'Interested – wants counsellor callback',
    LeadTemperature.warm => 'Exploring – details requested',
    _ => 'Not interested right now',
  };

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

  // Gender-neutral phrasing in summaries.
  static const _they = 'They';
  static const _their = 'their';
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

List<String> positivePool() => _positivePool;
