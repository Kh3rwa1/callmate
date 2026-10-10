import 's.dart';

/// Calling campaigns: the "Call new customers" button, setup and progress.
extension SCampaign on S {
  // ------------------------------------------------------------ CTA
  String callNewLeadsCount(int n) => n > 0
      ? pick(
          'Call $n New Customers',
          '$n नए ग्राहकों को कॉल करें',
          '$n টি নতুন গ্রাহকে কল করুন',
        )
      : pick(
          'Call New Customers',
          'नए ग्राहकों को कॉल करें',
          'নতুন গ্রাহকে কল করুন',
        );
  String callNewCompact(int n) => n > 0
      ? pick('Call $n new', '$n नई कॉल करें', '$n নতুন কল')
      : pick('Call new', 'नई कॉल', 'নতুন কল');
  String callNewSemantics(int n) => n > 0
      ? pick(
          'Call $n new customers',
          '$n नए ग्राहकों को कॉल करें',
          '$n টি নতুন গ্রাহকে কল করুন',
        )
      : pick(
          'Call new customers',
          'नए ग्राहकों को कॉल करें',
          'নতুন গ্রাহকে কল করুন',
        );

  // ------------------------------------------------------------ Live banner
  String isCallingYourLeads(String name) => pick(
    '$name is calling your customers…',
    '$name की कॉल्स जारी हैं…',
    '$name আপনার গ্রাহকদের কল করছে…',
  );
  String campaignBannerStats(int done, int total, int hot) => pick(
    '$done of $total done · $hot ready to buy',
    '$total में से $done पूरी · $hot खरीदने को तैयार',
    '$total-এর মধ্যে $done শেষ · $hot কিনতে তৈরি',
  );

  // ------------------------------------------------------------ Setup
  String get campaignSetupTitle =>
      pick('Call New Customers', 'नए ग्राहकों को कॉल', 'নতুন গ্রাহকে কল');
  String get leadsReady =>
      pick('customers ready', 'ग्राहक तैयार', 'গ্রাহক তৈরি');
  String get campaignCaller => pick('Caller', 'कॉल करने वाला', 'কে কল করবে');
  String get campaignPurpose => pick('Purpose', 'मकसद', 'উদ্দেশ্য');
  String get campaignLanguage => pick('Language', 'भाषा', 'ভাষা');
  String get autoDetect =>
      pick('Auto detect', 'अपने-आप पहचानें', 'নিজে থেকে বুঝে নেবে');
  String get callingHours => pick('Calling hours', 'कॉल का समय', 'কলের সময়');
  String get afterEachCall =>
      pick('After each call', 'हर कॉल के बाद', 'প্রতিটি কলের পরে');
  String get optScoreLead => pick(
    'Rate how likely they are to buy',
    'बताएँ कि उनके खरीदने की कितनी संभावना है',
    'ওঁদের কেনার সম্ভাবনা কতটা, তা জানান',
  );
  String get optWhatsapp => pick(
    'Write a WhatsApp message',
    'WhatsApp मैसेज बनाएँ',
    'WhatsApp মেসেজ তৈরি করুন',
  );
  String get optCallback => pick(
    'Suggest a call back',
    'कॉल बैक का सुझाव दें',
    'কল ব্যাকের পরামর্শ দিন',
  );
  String get optNotifyHot => pick(
    'Tell me who is ready to buy',
    'खरीदने को तैयार ग्राहक पर मुझे बताएँ',
    'কিনতে তৈরি গ্রাহক হলে আমাকে জানান',
  );
  String get estimatedUsage =>
      pick('Estimated usage', 'अनुमानित खर्च', 'আনুমানিক খরচ');
  String get connectedMinutesOnly => pick(
    'Connected minutes only',
    'सिर्फ़ जुड़ी हुई कॉल के मिनट',
    'শুধু কথা হওয়া কলের মিনিট',
  );
  String get startCampaign =>
      pick('Start Calling', 'कॉलिंग शुरू करें', 'কলিং শুরু করুন');
  String get noNewLeadsToCall => pick(
    'No new customers to call',
    'कॉल करने के लिए कोई नया ग्राहक नहीं',
    'কল করার মতো নতুন গ্রাহক নেই',
  );
  String get addLeadsToStart => pick(
    'Add customers to start calling.',
    'कॉल शुरू करने के लिए ग्राहक जोड़ें।',
    'কল শুরু করতে গ্রাহক যোগ করুন।',
  );
  String get addLeads =>
      pick('Add customers', 'ग्राहक जोड़ें', 'গ্রাহক যোগ করুন');

  // ------------------------------------------------------------ Confirm sheet
  String get noLeadsToCallYet => pick(
    'No customers to call yet',
    'अभी कॉल करने के लिए ग्राहक नहीं',
    'এখনও কল করার মতো গ্রাহক নেই',
  );
  String startCallingN(int n) => pick(
    'Start calling $n customers?',
    '$n ग्राहकों को कॉल शुरू करें?',
    '$n টি গ্রাহকে কল শুরু করবেন?',
  );

  /// Disclosure line in the confirm sheet. Gender-neutral on purpose.
  String campaignDisclosure(String hours, String name) => pick(
    '$hours · $name introduces itself as an AI assistant',
    '$hours · हर कॉल में बताया जाएगा कि $name AI असिस्टेंट है',
    '$hours · $name নিজেকে AI সহকারী হিসেবে পরিচয় দেবে',
  );
  String noConsentSkipped(int n) => pick(
    '$n customers won\'t be called: they haven\'t said yes to calls yet',
    '$n ग्राहकों को कॉल नहीं होगी: उन्होंने अभी कॉल के लिए हाँ नहीं कहा',
    '$n জন গ্রাহককে কল করা হবে না: ওঁরা এখনও কলে রাজি হননি',
  );
  String noConsentWarn(int n) => pick(
    '$n customers haven\'t said yes to calls yet',
    '$n ग्राहकों ने अभी कॉल के लिए हाँ नहीं कहा',
    '$n জন গ্রাহক এখনও কলে রাজি হননি',
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
  String get campaignTitle => pick('Calling', 'कॉलिंग', 'কলিং');
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
      pick('Calling stopped', 'कॉलिंग रोका गया', 'কলিং থামানো হয়েছে');
  String leadsCalled(int done, int total) => pick(
    '$done of $total customers called',
    '$total में से $done ग्राहकों को कॉल हुई',
    '$total-এর মধ্যে $done টি গ্রাহকে কল হয়েছে',
  );
  String nLeft(int n) => pick('$n left', '$n बाकी', '$n বাকি');
  String get latestResults =>
      pick('Latest results', 'ताज़ा नतीजे', 'সর্বশেষ ফলাফল');
  String get reviewFollowUps =>
      pick('Review messages', 'मैसेज देखें', 'মেসেজ দেখুন');
  String get viewHotLeads => pick(
    'See ready-to-buy customers',
    'खरीदने को तैयार ग्राहक देखें',
    'কিনতে তৈরি গ্রাহক দেখুন',
  );
}
