import 's.dart';

/// Short lines for the coloured tops of each tab ("worlds").
extension SWorlds on S {
  String onYourList(int n) =>
      pick('$n on your list', 'सूची में $n ग्राहक', 'তালিকায় $n জন গ্রাহক');
  String get callsEyebrow => pick(
    'Every call, and what was said',
    'हर कॉल, और क्या बात हुई',
    'প্রতিটি কল, আর কী কথা হল',
  );
  String get talkedToday =>
      pick('talked today', 'से आज बात हुई', 'জনের সঙ্গে আজ কথা');
  String get readyToSendShort =>
      pick('ready to send', 'भेजने को तैयार', 'পাঠানোর জন্য তৈরি');
  String get allSentToday => pick(
    'All sent. Nice work.',
    'सब भेज दिए। बढ़िया।',
    'সব পাঠানো হয়েছে। দারুণ।',
  );
  String get minutesLeftShort => pick('minutes left', 'मिनट बचे', 'মিনিট বাকি');
}
