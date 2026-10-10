import 's.dart';

/// Bottom navigation and the Home tab.
extension SHome on S {
  // ------------------------------------------------------------ Navigation
  String get navHome => pick('Home', 'होम', 'হোম');
  String get navLeads => pick('Leads', 'लीड्स', 'লিড');
  String get navCalls => pick('Calls', 'कॉल्स', 'কল');
  String get navFollowUps => pick('Follow-ups', 'फ़ॉलो-अप', 'ফলো-আপ');
  String get navAgent => pick('Agent', 'एजेंट', 'এজেন্ট');
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
  String get statHot => pick('Hot', 'हॉट', 'হট');
  String get needsAttention =>
      pick('Needs your attention', 'आपका ध्यान चाहिए', 'আপনার নজর দরকার');
  String get hotLeadsLabel => pick('hot leads', 'हॉट लीड्स', 'হট লিড');
  String get noHotLeadsYet =>
      pick('No hot leads yet', 'अभी कोई हॉट लीड नहीं', 'এখনও কোনো হট লিড নেই');
  String get callNewLeadsShort =>
      pick('Call new leads', 'नई लीड्स को कॉल करें', 'নতুন লিডে কল করুন');
  String get followUpsReadyLabel =>
      pick('follow-ups ready', 'फ़ॉलो-अप तैयार', 'ফলো-আপ তৈরি');
  String callbacksLabel(int n) =>
      plural(n, 'callback', 'callbacks', 'कॉलबैक', 'কলব্যাক');
  String get upcomingCallback =>
      pick('Upcoming callback', 'अगला कॉलबैक', 'পরের কলব্যাক');
  String nextCallback(String name, String when) =>
      pick('$name · $when', '$name · $when', '$name · $when');
  String get todaysActivity =>
      pick('Today\'s AI activity', 'आज AI ने क्या किया', 'আজ AI যা করেছে');
  String get noCallsYet =>
      pick('No calls yet', 'अभी कोई कॉल नहीं', 'এখনও কোনো কল হয়নি');
}
