import 's.dart';

/// The AI employee tab, editing it, app settings and plan usage.
extension SAgent on S {
  // ------------------------------------------------------------ Agent tab
  String get noAgentYet => pick(
    'No AI employee yet',
    'अभी कोई AI कर्मचारी नहीं',
    'এখনও কোনো AI কর্মী নেই',
  );
  String get createMyAiEmployee => pick(
    'Create My AI Employee',
    'मेरा AI कर्मचारी बनाएँ',
    'আমার AI কর্মী তৈরি করুন',
  );
  String talkTo(String name) =>
      pick('Talk to $name', '$name से बात करें', '$name-এর সঙ্গে কথা বলুন');
  String get editAiEmployee =>
      pick('Edit AI Employee', 'AI कर्मचारी बदलें', 'AI কর্মী এডিট করুন');
  String get profile => pick('Profile', 'प्रोफ़ाइल', 'প্রোফাইল');
  String get languagesLabel => pick('Languages', 'भाषाएँ', 'ভাষা');
  String get voice => pick('Voice', 'आवाज़', 'কণ্ঠ');
  String get personality => pick('Personality', 'स्वभाव', 'স্বভাব');
  String get goal => pick('Goal', 'लक्ष्य', 'লক্ষ্য');
  String get capabilities => pick('Capabilities', 'क्षमताएँ', 'দক্ষতা');
  String get teachYourAi =>
      pick('Teach Your AI', 'AI को सिखाएँ', 'AI-কে শেখান');
  String nSources(int n) => pick('$n sources', '$n स्रोत', '$n টি সূত্র');
  String minLeft(String n) =>
      pick('$n min left', '$n मिनट बचे', '$n মিনিট বাকি');
  String get callbacksTitle => pick('Callbacks', 'कॉलबैक', 'কলব্যাক');
  String get allowAlerts =>
      pick('Allow alerts', 'अलर्ट चालू करें', 'অ্যালার্ট চালু করুন');
  String get alertsOn =>
      pick('Alerts are on', 'अलर्ट चालू हैं', 'অ্যালার্ট চালু আছে');
  String get signOut => pick('Sign out', 'साइन आउट', 'সাইন আউট');
  String get signOutQ => pick('Sign out?', 'साइन आउट करें?', 'সাইন আউট করবেন?');
  String get signInAgainNeeded => pick(
    'You will need to sign in again.',
    'आपको फिर से साइन इन करना होगा।',
    'আপনাকে আবার সাইন ইন করতে হবে।',
  );
  String get deleteAccount =>
      pick('Delete account', 'अकाउंट डिलीट करें', 'অ্যাকাউন্ট মুছুন');
  String get deleteAccountQ =>
      pick('Delete account?', 'अकाउंट डिलीट करें?', 'অ্যাকাউন্ট মুছবেন?');
  String get deleteAccountBody => pick(
    'This cannot be undone. All leads, calls, transcripts and AI settings will be permanently deleted.',
    'इसे वापस नहीं लिया जा सकता। सारी लीड्स, कॉल्स, बातचीत और AI सेटिंग्स हमेशा के लिए मिट जाएँगी।',
    'এটা আর ফেরানো যাবে না। সব লিড, কল, কথোপকথন আর AI সেটিংস চিরতরে মুছে যাবে।',
  );
  String get deletePermanently =>
      pick('Delete permanently', 'हमेशा के लिए डिलीट करें', 'চিরতরে মুছুন');
  String accountNotDeleted(String why) => pick(
    'Account not deleted: $why',
    'अकाउंट डिलीट नहीं हुआ: $why',
    'অ্যাকাউন্ট মোছা হয়নি: $why',
  );

  // ------------------------------------------------------------ Settings
  String get settings => pick('Settings', 'सेटिंग्स', 'সেটিংস');
  String get appLanguage => pick('App language', 'ऐप की भाषा', 'অ্যাপের ভাষা');
  String get phoneDefault =>
      pick('Phone default', 'फ़ोन के अनुसार', 'ফোন অনুযায়ী');
  String get appearance => pick('Appearance', 'दिखावट', 'চেহারা');
  String get themeSystem => pick('Automatic', 'अपने-आप', 'নিজে থেকে');
  String get themeLight => pick('Light', 'लाइट', 'লাইট');
  String get themeDark => pick('Dark', 'डार्क', 'ডার্ক');
  String get themeSystemHint => pick(
    'Follows your phone\'s setting',
    'फ़ोन की सेटिंग के अनुसार',
    'ফোনের সেটিং অনুযায়ী',
  );

  // ------------------------------------------------------------ Edit agent
  String get identity => pick('Identity', 'पहचान', 'পরিচয়');
  String get nameLabel => pick('Name', 'नाम', 'নাম');
  String get roleLabel => pick('Role', 'भूमिका', 'ভূমিকা');
  String get nameRequired => pick(
    'Give your AI employee a name',
    'अपने AI कर्मचारी का नाम लिखें',
    'আপনার AI কর্মীর একটা নাম দিন',
  );
  String get voiceAndLanguage =>
      pick('Voice & language', 'आवाज़ और भाषा', 'কণ্ঠ ও ভাষা');
  String get behaviour => pick('Behaviour', 'व्यवहार', 'আচরণ');
  String get friendly => pick('Friendly', 'दोस्ताना', 'বন্ধুসুলভ');
  String get formal => pick('Formal', 'औपचारिक', 'আনুষ্ঠানিক');
  String get moreFriendly =>
      pick('More friendly', 'ज़्यादा दोस्ताना', 'আরও বন্ধুসুলভ');
  String get moreFormal =>
      pick('More formal', 'ज़्यादा औपचारिक', 'আরও আনুষ্ঠানিক');
  String get callsSection => pick('Calls', 'कॉल्स', 'কল');
  String get transferHotLeadsTo => pick(
    'Transfer hot leads to',
    'हॉट लीड्स किसे ट्रांसफ़र करें',
    'হট লিড কাকে ট্রান্সফার করবেন',
  );
  String humanNumberHint(String human) =>
      pick('$human number', '$human का नंबर', '$human-এর নম্বর');
  String isActiveNamed(String name) =>
      pick('$name is active', '$name चालू है', '$name চালু আছে');
  String isPausedNamed(String name) =>
      pick('$name is paused', '$name अभी बंद है', '$name থেমে আছে');
  String get checkTransferNumber => pick(
    'Check the transfer number',
    'ट्रांसफ़र नंबर जाँचें',
    'ট্রান্সফার নম্বরটি দেখুন',
  );
  String nameUpdated(String name) =>
      pick('$name updated ✓', '$name अपडेट हुआ ✓', '$name আপডেট হয়েছে ✓');

  // ------------------------------------------------------------ Usage
  String get planAndUsage =>
      pick('Plan & usage', 'प्लान और इस्तेमाल', 'প্ল্যান ও ব্যবহার');
  String get minutesRemaining =>
      pick('minutes remaining', 'मिनट बचे', 'মিনিট বাকি');
  String nUsed(String n) => pick('$n used', '$n इस्तेमाल', '$n ব্যবহার হয়েছে');
  String ofTotal(String n) => pick('of $n', '$n में से', '$n-এর মধ্যে');
  String get callsMade => pick('Calls made', 'कुल कॉल', 'মোট কল');
  String get renewsOn => pick('Renews on', 'रिन्यू होगा', 'রিনিউ হবে');
  String get extraMinutes =>
      pick('Extra minutes', 'अतिरिक्त मिनट', 'অতিরিক্ত মিনিট');
  String perMin(String price) =>
      pick('$price / min', '$price / मिनट', '$price / মিনিট');
  String get upgrade => pick('Upgrade', 'अपग्रेड करें', 'আপগ্রেড করুন');
  String get upgradeContact => pick(
    'Our team will reach out on WhatsApp to upgrade your plan.',
    'प्लान अपग्रेड करने के लिए हमारी टीम WhatsApp पर संपर्क करेगी।',
    'প্ল্যান আপগ্রেড করতে আমাদের টিম WhatsApp-এ যোগাযোগ করবে।',
  );
  String get onlyConnectedCount => pick(
    'Only connected minutes count.',
    'सिर्फ़ जुड़ी हुई कॉल के मिनट गिने जाते हैं।',
    'শুধু কথা হওয়া কলের মিনিট গোনা হয়।',
  );
  String get foundingPlan =>
      pick('Founding Plan', 'फ़ाउंडिंग प्लान', 'ফাউন্ডিং প্ল্যান');
}
