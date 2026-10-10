import 's.dart';

/// Home hero ("Your employee today"), the weekly funnel and sparkline, and
/// the ready-to-buy celebration.
///
/// Hindi copy avoids verbs that would give the AI employee a gender.
extension SDesign on S {
  // ------------------------------------------------------------ Hero
  String get heroEyebrow =>
      pick('Your employee today', 'आज आपका कर्मचारी', 'আজ আপনার কর্মী');
  String heroCalling(String name) => pick(
    'Calling $name…',
    '$name को कॉल हो रही है…',
    '$name-কে কল করা হচ্ছে…',
  );
  String get heroCallingAny => pick(
    'Calling your customers…',
    'आपके ग्राहकों को कॉल हो रही है…',
    'আপনার গ্রাহকদের কল করা হচ্ছে…',
  );
  String heroHot(int n) => plural(
    n,
    '$n ready to buy',
    '$n ready to buy',
    '$n खरीदने को तैयार',
    '$n জন কিনতে তৈরি',
  );
  String heroResting(String time) => pick(
    'Resting – calls start at $time',
    'आराम का समय – कॉल $time से शुरू',
    'বিশ্রামে – কল শুরু $time থেকে',
  );
  String get heroReady => pick(
    'Ready to call your customers',
    'आपके ग्राहकों को कॉल करने के लिए तैयार',
    'আপনার গ্রাহকদের কল করতে তৈরি',
  );
  String get heroSeeLive =>
      pick('See live calls', 'चल रही कॉल देखें', 'চলতি কল দেখুন');
  String get heroSeeReady =>
      pick('See who is ready', 'देखें कौन तैयार है', 'দেখুন কে তৈরি');
  String heroSendMessages(int n) => plural(
    n,
    'Send $n message',
    'Send $n messages',
    '$n मैसेज भेजें',
    '$n টি মেসেজ পাঠান',
  );
  String get heroAddCustomers =>
      pick('Add customers', 'ग्राहक जोड़ें', 'গ্রাহক যোগ করুন');

  // ------------------------------------------------------------ Checklist
  String get gsAllSet => pick("You're all set", 'सब तैयार है', 'সব তৈরি');
  String get gsAllSetBody => pick(
    'Your employee is ready to call your customers.',
    'आपका कर्मचारी ग्राहकों को कॉल करने के लिए तैयार है।',
    'আপনার কর্মী গ্রাহকদের কল করতে তৈরি।',
  );

  // ------------------------------------------------------------ This week
  String get funnelTalked => pick('Talked', 'बात हुई', 'কথা হয়েছে');
  String get vsLastWeek =>
      pick('vs last week', 'पिछले हफ़्ते से', 'গত সপ্তাহের তুলনায়');
  String get weekCallsLabel =>
      pick('Calls, last 7 days', 'पिछले 7 दिन की कॉल', 'গত 7 দিনের কল');
  String weekCallsSemantics(int n) => plural(
    n,
    '$n call in the last 7 days',
    '$n calls in the last 7 days',
    'पिछले 7 दिन में $n कॉल',
    'গত 7 দিনে $n টি কল',
  );
  String worthCaption(int n) => plural(
    n,
    'could come from $n ready buyer',
    'could come from $n ready buyers',
    '$n खरीदने को तैयार ग्राहकों से आ सकते हैं',
    '$n জন কিনতে তৈরি গ্রাহক থেকে আসতে পারে',
  );

  // ------------------------------------------------------------ Celebration
  String celebrateReady(String name) => pick(
    '$name is ready to buy!',
    '$name खरीदने को तैयार हैं!',
    '$name কিনতে তৈরি!',
  );
  String get celebrateReadyAny => pick(
    'A customer is ready to buy!',
    'एक ग्राहक खरीदने को तैयार है!',
    'একজন গ্রাহক কিনতে তৈরি!',
  );
}
