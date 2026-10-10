import 'enums.dart';
import 'json.dart';

/// Which call playbook a business gets (`backend/src/services/playbooks.ts`).
enum PlaybookVertical {
  education('education'),
  healthcare('healthcare'),
  realEstate('real_estate'),
  salon('salon'),
  fitness('fitness'),
  general('general');

  const PlaybookVertical(this.wire);
  final String wire;

  static PlaybookVertical parse(String? v) => values.firstWhere(
    (e) => e.wire == v,
    orElse: () => PlaybookVertical.general,
  );
}

/// The playbook the backend picks for [c] (same mapping as the server).
PlaybookVertical playbookVerticalFor(BusinessCategory? c) => switch (c) {
  BusinessCategory.coaching => PlaybookVertical.education,
  BusinessCategory.clinic ||
  BusinessCategory.diagnostic => PlaybookVertical.healthcare,
  BusinessCategory.realEstate => PlaybookVertical.realEstate,
  BusinessCategory.salon => PlaybookVertical.salon,
  BusinessCategory.gym => PlaybookVertical.fitness,
  _ => PlaybookVertical.general,
};

/// Outcome a WhatsApp follow-up template is for.
enum FollowupOutcome {
  hot('hot'),
  warm('warm'),
  callback('callback'),
  notInterested('not_interested');

  const FollowupOutcome(this.wire);
  final String wire;
}

class PlaybookObjection {
  const PlaybookObjection({required this.objection, required this.hint});
  final String objection;
  final String hint;

  factory PlaybookObjection.fromJson(Json j) =>
      PlaybookObjection(objection: jStr(j, 'objection'), hint: jStr(j, 'hint'));
}

/// `GET /playbooks/current`: what the AI employee asks, what "ready to buy"
/// means, objection hints, default WhatsApp follow-ups and callback timing.
/// Read-only in the app (v1).
class CallPlaybook {
  const CallPlaybook({
    required this.vertical,
    required this.name,
    required this.qualifyingQuestions,
    required this.readyToBuy,
    required this.objections,
    required this.followupTemplates,
    required this.callbackHint,
    this.category,
    this.language = 'en',
    this.businessName = '',
    this.minScore = 75,
    this.callbackStartHour,
    this.callbackEndHour,
  });

  final PlaybookVertical vertical;
  final String? category;
  final String language;
  final String name;
  final String businessName;
  final List<String> qualifyingQuestions;
  final String readyToBuy;

  /// Lead score at or above which a hot, interested lead counts as ready.
  final int minScore;
  final List<PlaybookObjection> objections;

  /// Templates with `{name}` and `{business}` placeholders.
  final Map<FollowupOutcome, String> followupTemplates;
  final String callbackHint;
  final int? callbackStartHour;
  final int? callbackEndHour;

  /// [outcome]'s template with `{business}` filled and `{name}` shown as
  /// [namePlaceholder] (e.g. "[Name]"); empty if the template is missing.
  String preview(FollowupOutcome outcome, {required String namePlaceholder}) {
    final t = followupTemplates[outcome] ?? '';
    final business = businessName.trim().isEmpty ? '…' : businessName.trim();
    return t
        .replaceAll('{name}', namePlaceholder)
        .replaceAll('{business}', business);
  }

  factory CallPlaybook.fromJson(Json j) {
    final ready = jObj(j, 'ready_to_buy') ?? const {};
    final timing = jObj(j, 'callback_timing') ?? const {};
    final templates = jObj(j, 'followup_templates') ?? const {};
    return CallPlaybook(
      vertical: PlaybookVertical.parse(jStrN(j, 'id')),
      category: jStrN(j, 'category'),
      language: jStr(j, 'language', 'en'),
      name: jStr(j, 'name'),
      businessName: jStr(j, 'business_name'),
      qualifyingQuestions: jStrList(j, 'qualifying_questions'),
      readyToBuy: jStr(ready, 'description'),
      minScore: jInt(ready, 'min_score', 75),
      objections: jList(j, 'objections', PlaybookObjection.fromJson),
      followupTemplates: {
        for (final o in FollowupOutcome.values)
          if (jStrN(templates, o.wire) != null) o: jStr(templates, o.wire),
      },
      callbackHint: jStr(timing, 'hint'),
      callbackStartHour: jIntN(timing, 'start_hour'),
      callbackEndHour: jIntN(timing, 'end_hour'),
    );
  }
}
