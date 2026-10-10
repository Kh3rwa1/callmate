import 's.dart';

/// Bottom navigation and the Home tab.
extension SHome on S {
  // ------------------------------------------------------------ Navigation
  String get navHome => pick('Home', 'होम', 'হোম');
  String get navLeads => pick('Customers', 'ग्राहक', 'গ্রাহক');
  String get navCalls => pick('Calls', 'कॉल्स', 'কল');
  String get navFollowUps => pick('Messages', 'मैसेज', 'মেসেজ');
  String get navAgent => pick('My employee', 'मेरा कर्मचारी', 'আমার কর্মী');
  String navPending(String tab, int n) =>
      pick('$tab, $n pending', '$tab, $n बाकी', '$tab, $n বাকি');

  // ------------------------------------------------------------ Header
  String get homeWelcome => pick('Welcome', 'स्वागत है', 'স্বাগতম');
  String get demoControls =>
      pick('Demo controls', 'डेमो कंट्रोल', 'ডেমো কন্ট্রোল');
  String get notifications => pick('Notifications', 'सूचनाएँ', 'নোটিফিকেশন');
  String newNotifications(int n) =>
      pick('$n new notifications', '$n नई सूचनाएँ', '$n টি নতুন নোটিফিকেশন');

  // ------------------------------------------------------------ Hero card
  String get callsToday => pick('calls today', 'आज की कॉल', 'আজকের কল');
  String heroSemantics(String name, String role, String status, int? calls) =>
      pick(
        '$name, $role, $status${calls == null ? '' : ', $calls calls today'}',
        '$name, $role, $status${calls == null ? '' : ', आज $calls कॉल'}',
        '$name, $role, $status${calls == null ? '' : ', আজ $calls টি কল'}',
      );

  // ------------------------------------------------------------ Sections
  String get todaysResults =>
      pick('Today\'s results', 'आज के नतीजे', 'আজকের ফলাফল');
  String get statCalls => pick('Calls', 'कॉल', 'কল');
  String get statConnected => pick('Connected', 'बात हुई', 'কথা হয়েছে');
  String get statInterested => pick('Interested', 'रुचि है', 'আগ্রহী');
  String get statHot => pick('Ready to buy', 'खरीदने को तैयार', 'কিনতে তৈরি');
  String get needsAttention =>
      pick('Needs your attention', 'आपका ध्यान चाहिए', 'আপনার নজর দরকার');
  String get hotLeadsLabel =>
      pick('ready to buy', 'खरीदने को तैयार ग्राहक', 'কিনতে তৈরি গ্রাহক');
  String get noHotLeadsYet => pick(
    'No one ready to buy yet',
    'अभी कोई खरीदने को तैयार ग्राहक नहीं',
    'এখনও কোনো কিনতে তৈরি গ্রাহক নেই',
  );
  String get callNewLeadsShort => pick(
    'Call new customers',
    'नए ग्राहकों को कॉल करें',
    'নতুন গ্রাহকে কল করুন',
  );
  String get followUpsReadyLabel =>
      pick('messages ready', 'मैसेज तैयार', 'মেসেজ তৈরি');
  String callbacksLabel(int n) =>
      plural(n, 'call back', 'call backs', 'कॉल बैक', 'কল ব্যাক');
  String get upcomingCallback =>
      pick('Next call back', 'अगला कॉल बैक', 'পরের কল ব্যাক');
  String nextCallback(String name, String when) =>
      pick('$name · $when', '$name · $when', '$name · $when');
  String get todaysActivity =>
      pick('Today\'s AI activity', 'आज AI ने क्या किया', 'আজ AI যা করেছে');
  String get noCallsYet =>
      pick('No calls yet', 'अभी कोई कॉल नहीं', 'এখনও কোনো কল হয়নি');
}
