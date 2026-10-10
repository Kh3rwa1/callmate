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
  String get callbacksTitle => pick('Call backs', 'कॉल बैक', 'কল ব্যাক');
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
    'This cannot be undone. All customers, calls, transcripts and AI settings will be permanently deleted.',
    'इसे वापस नहीं लिया जा सकता। सारे ग्राहक, कॉल्स, बातचीत और AI सेटिंग्स हमेशा के लिए मिट जाएँगी।',
    'এটা আর ফেরানো যাবে না। সব গ্রাহক, কল, কথোপকথন আর AI সেটিংস চিরতরে মুছে যাবে।',
  );
  String get deletePermanently =>
      pick('Delete permanently', 'हमेशा के लिए डिलीट करें', 'চিরতরে মুছুন');
  String accountNotDeleted(String why) => pick(
    'Account not deleted: $why',
    'अकाउंट डिलीट नहीं हुआ: $why',
    'অ্যাকাউন্ট মোছা হয়নি: $why',
  );

  // ------------------------------------------------------------ Support
  String get helpSupport =>
      pick('Help & support', 'मदद और सहायता', 'সাহায্য ও সহায়তা');
  String get emailSupport =>
      pick('Email us', 'हमें ईमेल करें', 'আমাদের ইমেল করুন');
  String get termsOfService =>
      pick('Terms of Service', 'सेवा की शर्तें', 'পরিষেবার শর্তাবলি');
  String get deleteAccountHelp => pick(
    'How account deletion works',
    'अकाउंट डिलीट करने का तरीका',
    'অ্যাকাউন্ট মোছার নিয়ম',
  );
  String get supportEmailSubject =>
      pick('CallPilot support', 'CallPilot सहायता', 'CallPilot সহায়তা');
  String couldNotOpen(String what) =>
      pick('Could not open $what', '$what नहीं खुल सका', '$what খোলা গেল না');

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
    'Send ready-to-buy customers to',
    'खरीदने को तैयार ग्राहक किसे ट्रांसफ़र करें',
    'কিনতে তৈরি গ্রাহক কাকে ট্রান্সফার করবেন',
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
    'Only connected calls of 10 seconds or more count. Unanswered calls and voicemail are free.',
    'सिर्फ़ 10 सेकंड या उससे लंबी जुड़ी हुई कॉल गिनी जाती हैं। बिना उठाई कॉल और वॉइसमेल मुफ़्त हैं।',
    'শুধু 10 সেকেন্ড বা তার বেশি কথা হওয়া কল গোনা হয়। না-ধরা কল আর ভয়েসমেল ফ্রি।',
  );

  // ------------------------------------------------------------ Plans & top-ups
  String get choosePlan =>
      pick('Choose a plan', 'प्लान चुनें', 'প্ল্যান বেছে নিন');
  String get changePlan => pick('Change plan', 'प्लान बदलें', 'প্ল্যান বদলান');
  String get billingMonthly => pick('Monthly', 'मासिक', 'মাসিক');
  String get billingYearly => pick('Yearly', 'सालाना', 'বার্ষিক');
  String get twoMonthsFree =>
      pick('2 months free', '2 महीने मुफ़्त', '2 মাস ফ্রি');
  String minutesPerMonth(String n) =>
      pick('$n minutes / month', '$n मिनट / महीना', '$n মিনিট / মাস');
  String pricePerMonth(String price) =>
      pick('$price / month', '$price / महीना', '$price / মাস');
  String pricePerYear(String price) =>
      pick('$price / year', '$price / साल', '$price / বছর');
  String get priceLabel => pick('Price', 'कीमत', 'দাম');
  String gstLabel(String pct) =>
      pick('GST ($pct%)', 'GST ($pct%)', 'GST ($pct%)');
  String get totalToPay => pick('Total to pay', 'कुल भुगतान', 'মোট পেমেন্ট');
  String payAmount(String total) =>
      pick('Pay $total', '$total चुकाएँ', '$total পেমেন্ট করুন');
  String get currentPlanTag =>
      pick('Current plan', 'मौजूदा प्लान', 'বর্তমান প্ল্যান');
  String get buyMoreMinutes =>
      pick('Buy more minutes', 'और मिनट ख़रीदें', 'আরও মিনিট কিনুন');
  String get buyMinutes => pick('Buy minutes', 'मिनट ख़रीदें', 'মিনিট কিনুন');
  String topupMinutes(String n) => pick('+$n minutes', '+$n मिनट', '+$n মিনিট');
  String get topupValidity => pick(
    'Extra minutes stay valid until your plan renews.',
    'अतिरिक्त मिनट प्लान रिन्यू होने तक चलेंगे।',
    'অতিরিক্ত মিনিট প্ল্যান রিনিউ হওয়া পর্যন্ত থাকবে।',
  );
  String get topupNeedsActivePlan => pick(
    'Extra minutes can be added to an active plan. Buy or renew a plan first.',
    'अतिरिक्त मिनट सिर्फ़ चालू प्लान में जुड़ते हैं। पहले प्लान ख़रीदें या रिन्यू करें।',
    'অতিরিক্ত মিনিট শুধু চালু প্ল্যানে যোগ হয়। আগে প্ল্যান কিনুন বা রিনিউ করুন।',
  );
  String get topupAdded => pick(
    'Extra minutes added ✓',
    'अतिरिक्त मिनट जुड़ गए ✓',
    'অতিরিক্ত মিনিট যোগ হয়েছে ✓',
  );
  String get addedMinutes =>
      pick('Added minutes', 'जोड़े गए मिनट', 'যোগ করা মিনিট');
  String get bonusMinutesLabel =>
      pick('Bonus minutes', 'बोनस मिनट', 'বোনাস মিনিট');
  String get yearlyPlanUntil =>
      pick('Yearly plan until', 'सालाना प्लान तक', 'বার্ষিক প্ল্যান পর্যন্ত');
  String bannerPaidLow(String n) => pick(
    'Only $n calling minutes left this month.',
    'इस महीने सिर्फ़ $n कॉल मिनट बचे हैं।',
    'এই মাসে মাত্র $n কলের মিনিট বাকি।',
  );
  String get planTrial => pick('Free trial', 'फ़्री ट्रायल', 'ফ্রি ট্রায়াল');
  String get planActive => pick('Active', 'चालू', 'চালু');
  String get planPaymentDue =>
      pick('Payment due', 'भुगतान बाकी', 'পেমেন্ট বাকি');
  String get planCancelled => pick('Cancelled', 'रद्द', 'বাতিল');
  String get renewPlan =>
      pick('Renew plan', 'प्लान रिन्यू करें', 'প্ল্যান রিনিউ করুন');
  String get paymentDueOn =>
      pick('Payment was due on', 'भुगतान की तारीख थी', 'পেমেন্টের তারিখ ছিল');
  String get trialMinutesNote => pick(
    'Free trial minutes do not renew. Upgrade to keep calling.',
    'फ़्री ट्रायल के मिनट दोबारा नहीं मिलते। कॉल जारी रखने के लिए अपग्रेड करें।',
    'ফ্রি ট্রায়ালের মিনিট আবার পাওয়া যায় না। কল চালিয়ে যেতে আপগ্রেড করুন।',
  );
  String planOffer(String name, String price, String minutes) => pick(
    '$name: $price / month · $minutes minutes',
    '$name: $price / महीना · $minutes मिनट',
    '$name: $price / মাস · $minutes মিনিট',
  );
  String get paymentPageFailed => pick(
    "Couldn't open the payment page. Please try again.",
    'पेमेंट पेज नहीं खुला। फिर से कोशिश करें।',
    'পেমেন্ট পেজ খোলা গেল না। আবার চেষ্টা করুন।',
  );
  String get paymentReceived => pick(
    'Payment received. Your plan is active ✓',
    'भुगतान मिल गया। आपका प्लान चालू है ✓',
    'পেমেন্ট পাওয়া গেছে। আপনার প্ল্যান চালু ✓',
  );
  String get bannerPastDue => pick(
    'Payment due – calls are paused. Renew your plan to keep calling.',
    'भुगतान बाकी है – कॉल रुकी हैं। कॉल जारी रखने के लिए प्लान रिन्यू करें।',
    'পেমেন্ট বাকি – কল বন্ধ আছে। কল চালিয়ে যেতে প্ল্যান রিনিউ করুন।',
  );
  String get bannerTrialUsedUp => pick(
    'Your free trial minutes are used up. Upgrade to keep calling.',
    'आपके फ़्री ट्रायल के मिनट ख़त्म हो गए। कॉल जारी रखने के लिए अपग्रेड करें।',
    'আপনার ফ্রি ট্রায়ালের মিনিট শেষ। কল চালিয়ে যেতে আপগ্রেড করুন।',
  );
  String bannerTrialLow(String n) => pick(
    'Only $n free trial minutes left.',
    'फ़्री ट्रायल के सिर्फ़ $n मिनट बचे हैं।',
    'ফ্রি ট্রায়ালের মাত্র $n মিনিট বাকি।',
  );
  String get bannerMinutesUsedUp => pick(
    'All calling minutes are used up for this month.',
    'इस महीने के सभी कॉल मिनट ख़त्म हो गए।',
    'এই মাসের সব কলের মিনিট শেষ।',
  );
  String get viewPlan => pick('View plan', 'प्लान देखें', 'প্ল্যান দেখুন');
}
