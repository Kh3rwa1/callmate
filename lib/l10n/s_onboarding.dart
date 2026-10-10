import 's.dart';

/// Shared first-run strings (step counter, business name, voice choice).
/// The three steps' own copy lives in `s_easy.dart`.
///
/// Hindi copy avoids verbs that would give the AI employee (or the owner) a
/// gender: passive voice, noun phrases and subjunctive forms instead.
extension SOnboarding on S {
  // ----------------------------------------------------------- Scaffold
  String obStepOf(int step, int total) => pick(
    'Step $step of $total',
    'स्टेप $step / $total',
    'ধাপ $step / $total',
  );

  // ------------------------------------------------------ Business name
  String get obBizNameHint =>
      pick('e.g. Smile Dental', 'जैसे Smile Dental', 'যেমন Smile Dental');
  String get obBizNameRequired => pick(
    'Please enter your business name',
    'अपने कारोबार का नाम डालें',
    'আপনার ব্যবসার নাম দিন',
  );

  // -------------------------------------------------------------- Voice
  String get obVoiceFemale =>
      pick("Woman's voice", 'महिला की आवाज़', 'মহিলার কণ্ঠ');
  String get obVoiceMale =>
      pick("Man's voice", 'पुरुष की आवाज़', 'পুরুষের কণ্ঠ');
}
