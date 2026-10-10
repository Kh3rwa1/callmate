import '../data/models/models.dart';
import 's.dart';

/// Notifications, callbacks, teaching the AI, demo controls and splash.
extension SMisc on S {
  // ------------------------------------------------------------ Notifications
  String get nothingNeedsYou => pick(
    'Nothing needs you right now.',
    'अभी आपके लिए कुछ नहीं है।',
    'এখন আপনার কিছু করার নেই।',
  );
  String get unread => pick('Unread', 'नहीं पढ़ा', 'পড়া হয়নি');
  String get open => pick('Open', 'खोलें', 'খুলুন');

  /// Notification titles in the UI language (backend titles are English).
  String notificationTitle(NotificationType t) => switch (t) {
    NotificationType.hotLead => pick(
      'Hot lead detected',
      'हॉट लीड मिली',
      'হট লিড পাওয়া গেছে',
    ),
    NotificationType.followUpReady => pick(
      'Follow-up ready',
      'फ़ॉलो-अप तैयार',
      'ফলো-আপ তৈরি',
    ),
    NotificationType.callback => pick(
      'Callback requested',
      'कॉलबैक माँगा गया',
      'কলব্যাক চাওয়া হয়েছে',
    ),
    NotificationType.campaign => pick(
      'Campaign update',
      'कैंपेन अपडेट',
      'ক্যাম্পেন আপডেট',
    ),
  };

  // ------------------------------------------------------------ Callbacks
  String get noCallbacksYet =>
      pick('No callbacks yet', 'अभी कोई कॉलबैक नहीं', 'এখনও কোনো কলব্যাক নেই');
  String get requestedCallbacksAppear => pick(
    'Requested callbacks show up here.',
    'माँगे गए कॉलबैक यहाँ दिखेंगे।',
    'চাওয়া কলব্যাক এখানে দেখা যাবে।',
  );
  String get upcoming => pick('Upcoming', 'आने वाले', 'আসন্ন');
  String get swipeLeftDone => pick(
    'Swipe left to mark done',
    'पूरा मार्क करने के लिए बाईं ओर स्वाइप करें',
    'শেষ হিসেবে চিহ্নিত করতে বাঁ দিকে সোয়াইপ করুন',
  );
  String markedCallbackDone(String first) => pick(
    'Marked $first\'s callback as done ✓',
    '$first का कॉलबैक पूरा हुआ ✓',
    '$first-এর কলব্যাক শেষ ✓',
  );
  String get scheduleCallbackTitle =>
      pick('Schedule callback', 'कॉलबैक तय करें', 'কলব্যাক ঠিক করুন');
  String suggestedBy(String name) =>
      pick('Suggested by $name', '$name का सुझाव', '$name-এর পরামর্শ');
  String get todaySixPm => pick('Today, 6 PM', 'आज, 6 PM', 'আজ, 6 PM');
  String get tomorrowElevenAm =>
      pick('Tomorrow, 11 AM', 'कल, 11 AM', 'আগামীকাল, 11 AM');
  String get tomorrowSixPm =>
      pick('Tomorrow, 6 PM', 'कल, 6 PM', 'আগামীকাল, 6 PM');
  String get pickDateTime =>
      pick('Pick date & time', 'तारीख और समय चुनें', 'তারিখ ও সময় বাছুন');
  String get chooseAnySlot =>
      pick('Choose any slot', 'कोई भी समय चुनें', 'যেকোনো সময় বাছুন');
  String callbackSetFor(String when) => pick(
    'Callback set for $when',
    'कॉलबैक तय: $when',
    'কলব্যাক ঠিক হয়েছে: $when',
  );

  // ------------------------------------------------------------ Teach AI
  String get addInformation =>
      pick('Add information', 'जानकारी जोड़ें', 'তথ্য যোগ করুন');
  String get plusAddInformation =>
      pick('+ Add information', '+ जानकारी जोड़ें', '+ তথ্য যোগ করুন');
  String get uploadPdf =>
      pick('Upload PDF', 'PDF अपलोड करें', 'PDF আপলোড করুন');
  String get addWebsite =>
      pick('Add website', 'वेबसाइट जोड़ें', 'ওয়েবসাইট যোগ করুন');
  String get pasteText =>
      pick('Paste text', 'टेक्स्ट पेस्ट करें', 'লেখা পেস্ট করুন');
  String get addFaq =>
      pick('Add FAQ', 'सवाल-जवाब जोड़ें', 'প্রশ্নোত্তর যোগ করুন');
  String get addBusinessInfo => pick(
    'Add business information',
    'कारोबार की जानकारी जोड़ें',
    'ব্যবসার তথ্য যোগ করুন',
  );
  String get pasteInformation =>
      pick('Paste information', 'जानकारी पेस्ट करें', 'তথ্য পেস্ট করুন');
  String get titleOptional =>
      pick('Title (optional)', 'शीर्षक (ज़रूरी नहीं)', 'শিরোনাম (ঐচ্ছিক)');
  String get pleaseAddSomething =>
      pick('Please add something', 'कुछ लिखें', 'কিছু লিখুন');
  String get enterValidWebsite =>
      pick('Enter a valid website', 'सही वेबसाइट डालें', 'সঠিক ওয়েবসাইট দিন');
  String get addMoreDetail =>
      pick('Add a little more detail', 'थोड़ा और लिखें', 'আরেকটু লিখুন');
  String get addToKnowledge => pick(
    'Add to your AI\'s knowledge',
    'AI की जानकारी में जोड़ें',
    'AI-এর জ্ঞানে যোগ করুন',
  );
  String get hintServices => pick(
    'Services, pricing, policies…',
    'सेवाएँ, कीमतें, नियम…',
    'পরিষেবা, দাম, নিয়ম…',
  );
  String get hintBusinessInfo => pick(
    'Hours, location, payments…',
    'समय, पता, भुगतान…',
    'সময়, ঠিকানা, পেমেন্ট…',
  );
  String get hintFaq => pick(
    'Q: Do you accept UPI?\nA: Yes.',
    'सवाल: क्या आप UPI लेते हैं?\nजवाब: हाँ।',
    'প্রশ্ন: UPI নেন?\nউত্তর: হ্যাঁ।',
  );
  String get faqTitle => pick('FAQ', 'सवाल-जवाब', 'প্রশ্নোত্তর');
  String get notesTitle => pick('Notes', 'नोट्स', 'নোট');
  String get websiteTitle => pick('Website', 'वेबसाइट', 'ওয়েবসাইট');
  String learned(String name, String title) => pick(
    '$name learned “$title” ✓',
    '$name ने “$title” सीख लिया ✓',
    '$name “$title” শিখে নিয়েছে ✓',
  );
  String removedSource(String title) =>
      pick('Removed “$title”', '“$title” हटाया', '“$title” সরানো হয়েছে');
  String removeSourceQ(String title) =>
      pick('Remove “$title”?', '“$title” हटाएँ?', '“$title” সরাবেন?');
  String get removeSourceBody => pick(
    'Your AI employee will stop using this information.',
    'आपका AI कर्मचारी यह जानकारी इस्तेमाल करना बंद कर देगा।',
    'আপনার AI কর্মী এই তথ্য আর ব্যবহার করবে না।',
  );
  String get nothingLearnedYet => pick(
    'Your AI employee hasn\'t learned anything yet',
    'आपके AI कर्मचारी ने अभी कुछ नहीं सीखा',
    'আপনার AI কর্মী এখনও কিছু শেখেনি',
  );
  String get addServicesPricingFaqs => pick(
    'Add services, pricing or FAQs.',
    'सेवाएँ, कीमतें या सवाल-जवाब जोड़ें।',
    'পরিষেবা, দাম বা প্রশ্নোত্তর যোগ করুন।',
  );
  String lastUpdated(String when) =>
      pick('Last updated $when', 'आख़िरी बदलाव $when', 'শেষ আপডেট $when');
  String uploadingPct(int pct) =>
      pick('Uploading $pct%', 'अपलोड $pct%', 'আপলোড $pct%');
  String get learning => pick('Learning…', 'सीखना जारी…', 'শিখছে…');
  String get learnedLabel => pick('Learned', 'सीख लिया', 'শেখা হয়েছে');
  String get couldntRead =>
      pick('Couldn\'t read this', 'यह पढ़ा नहीं जा सका', 'এটা পড়া গেল না');

  // ------------------------------------------------------------ Demo
  String get mockOnly =>
      pick('Mock mode only', 'सिर्फ़ मॉक मोड में', 'শুধু মক মোডে');
  String get mockBackend => 'Mock backend';
  String get simulate => pick('Simulate', 'सिमुलेट करें', 'সিমুলেট');
  String get resetLabel => pick('Reset', 'रीसेट', 'রিসেট');
  String get replayOnboarding =>
      pick('Replay onboarding', 'ऑनबोर्डिंग दोबारा', 'অনবোর্ডিং আবার');
}
