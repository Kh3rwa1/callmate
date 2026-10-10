import 's.dart';

/// Calling campaigns: the "Call new leads" button, setup and progress.
extension SCampaign on S {
  // ------------------------------------------------------------ CTA
  String callNewLeadsCount(int n) => n > 0
      ? pick(
          'Call $n New Leads',
          '$n नई लीड्स को कॉल करें',
          '$n টি নতুন লিডে কল করুন',
        )
      : pick('Call New Leads', 'नई लीड्स को कॉल करें', 'নতুন লিডে কল করুন');
  String callNewCompact(int n) => n > 0
      ? pick('Call $n new', '$n नई कॉल करें', '$n নতুন কল')
      : pick('Call new', 'नई कॉल', 'নতুন কল');
  String callNewSemantics(int n) => n > 0
      ? pick(
          'Call $n new leads',
          '$n नई लीड्स को कॉल करें',
          '$n টি নতুন লিডে কল করুন',
        )
      : pick('Call new leads', 'नई लीड्स को कॉल करें', 'নতুন লিডে কল করুন');

  // ------------------------------------------------------------ Live banner
  String isCallingYourLeads(String name) => pick(
    '$name is calling your leads…',
    '$name की कॉल्स जारी हैं…',
    '$name আপনার লিডদের কল করছে…',
  );
  String campaignBannerStats(int done, int total, int hot) => pick(
    '$done of $total done · $hot hot',
    '$total में से $done पूरी · $hot हॉट',
    '$total-এর মধ্যে $done শেষ · $hot হট',
  );

  // ------------------------------------------------------------ Setup
  String get campaignSetupTitle =>
      pick('Call New Leads', 'नई लीड्स को कॉल', 'নতুন লিডে কল');
  String get leadsReady => pick('leads ready', 'लीड्स तैयार', 'লিড তৈরি');
  String get campaignCaller => pick('Caller', 'कॉल करने वाला', 'কে কল করবে');
  String get campaignPurpose => pick('Purpose', 'मकसद', 'উদ্দেশ্য');
  String get campaignLanguage => pick('Language', 'भाषा', 'ভাষা');
  String get autoDetect =>
      pick('Auto detect', 'अपने-आप पहचानें', 'নিজে থেকে বুঝে নেবে');
  String get callingHours => pick('Calling hours', 'कॉल का समय', 'কলের সময়');
  String get afterEachCall =>
      pick('After each call', 'हर कॉल के बाद', 'প্রতিটি কলের পরে');
  String get optScoreLead =>
      pick('Score lead', 'लीड को स्कोर करें', 'লিডের স্কোর দিন');
  String get optWhatsapp => pick(
    'Generate WhatsApp follow-up',
    'WhatsApp फ़ॉलो-अप बनाएँ',
    'WhatsApp ফলো-আপ তৈরি করুন',
  );
  String get optCallback => pick(
    'Recommend callback',
    'कॉलबैक का सुझाव दें',
    'কলব্যাকের পরামর্শ দিন',
  );
  String get optNotifyHot => pick(
    'Notify me for hot leads',
    'हॉट लीड पर मुझे बताएँ',
    'হট লিড হলে আমাকে জানান',
  );
  String get estimatedUsage =>
      pick('Estimated usage', 'अनुमानित खर्च', 'আনুমানিক খরচ');
  String get connectedMinutesOnly => pick(
    'Connected minutes only',
    'सिर्फ़ जुड़ी हुई कॉल के मिनट',
    'শুধু কথা হওয়া কলের মিনিট',
  );
  String get startCampaign =>
      pick('Start Campaign', 'कैंपेन शुरू करें', 'ক্যাম্পেন শুরু করুন');
  String get noNewLeadsToCall => pick(
    'No new leads to call',
    'कॉल करने के लिए कोई नई लीड नहीं',
    'কল করার মতো নতুন লিড নেই',
  );
  String get addLeadsToStart => pick(
    'Add leads to start calling.',
    'कॉल शुरू करने के लिए लीड्स जोड़ें।',
    'কল শুরু করতে লিড যোগ করুন।',
  );
  String get addLeads => pick('Add leads', 'लीड्स जोड़ें', 'লিড যোগ করুন');

  // ------------------------------------------------------------ Confirm sheet
  String get noLeadsToCallYet => pick(
    'No leads to call yet',
    'अभी कॉल करने के लिए लीड नहीं',
    'এখনও কল করার মতো লিড নেই',
  );
  String startCallingN(int n) => pick(
    'Start calling $n leads?',
    '$n लीड्स को कॉल शुरू करें?',
    '$n টি লিডে কল শুরু করবেন?',
  );

  /// Disclosure line in the confirm sheet. Gender-neutral on purpose.
  String campaignDisclosure(String hours, String name) => pick(
    '$hours · $name introduces itself as an AI assistant',
    '$hours · हर कॉल में बताया जाएगा कि $name AI असिस्टेंट है',
    '$hours · $name নিজেকে AI সহকারী হিসেবে পরিচয় দেবে',
  );
  String noConsentSkipped(int n) => pick(
    '$n leads will be skipped (no consent recorded)',
    '$n लीड्स छोड़ दी जाएँगी (सहमति दर्ज नहीं)',
    '$n টি লিড বাদ যাবে (সম্মতি নথিভুক্ত নেই)',
  );
  String noConsentWarn(int n) => pick(
    '$n leads have no consent recorded',
    '$n लीड्स की सहमति दर्ज नहीं है',
    '$n টি লিডের সম্মতি নথিভুক্ত নেই',
  );
  String get consentAttest => pick(
    'I confirm these contacts asked to be contacted',
    'पुष्टि: इन लोगों ने ख़ुद संपर्क के लिए कहा था',
    'আমি নিশ্চিত করছি যে এঁরা যোগাযোগ করতে বলেছিলেন',
  );
  String get yesStartCalling =>
      pick('Yes, start calling', 'हाँ, कॉल शुरू करें', 'হ্যাঁ, কল শুরু করুন');
  String isOnIt(String name) => pick(
    '$name is on it',
    '$name ने काम शुरू कर दिया',
    '$name কাজ শুরু করেছে',
  );

  // ------------------------------------------------------------ Progress
  String get campaignTitle => pick('Campaign', 'कैंपेन', 'ক্যাম্পেন');
  String get stop => pick('Stop', 'रोकें', 'থামান');
  String get pauseCallingQ =>
      pick('Pause calling?', 'कॉल रोकें?', 'কল থামাবেন?');
  String stopsAfterCurrent(String name) => pick(
    '$name stops after the current call.',
    'अभी वाली कॉल के बाद कॉल्स रुक जाएँगी।',
    'এখনকার কলের পরে $name থামবে।',
  );
  String get keepGoing => pick('Keep going', 'चलने दें', 'চলতে দিন');
  String finishedCalling(String name) => pick(
    '$name finished calling',
    '$name की कॉल्स पूरी हुईं',
    '$name-এর কল শেষ',
  );
  String isCalling(String name) =>
      pick('$name is calling', '$name की कॉल्स जारी हैं', '$name কল করছে');
  String get campaignStopped =>
      pick('Campaign stopped', 'कैंपेन रोका गया', 'ক্যাম্পেন থামানো হয়েছে');
  String leadsCalled(int done, int total) => pick(
    '$done of $total leads called',
    '$total में से $done लीड्स को कॉल हुई',
    '$total-এর মধ্যে $done টি লিডে কল হয়েছে',
  );
  String nLeft(int n) => pick('$n left', '$n बाकी', '$n বাকি');
  String get latestResults =>
      pick('Latest results', 'ताज़ा नतीजे', 'সর্বশেষ ফলাফল');
  String get reviewFollowUps =>
      pick('Review follow-ups', 'फ़ॉलो-अप देखें', 'ফলো-আপ দেখুন');
  String get viewHotLeads =>
      pick('View hot leads', 'हॉट लीड्स देखें', 'হট লিড দেখুন');
}
