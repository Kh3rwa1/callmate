import 's.dart';
import 's_data.dart';

/// Leads list, lead detail, calling a lead and adding/importing leads.
extension SLeads on S {
  // ------------------------------------------------------------ List
  String get leadsTitle => pick('Customers', 'ग्राहक', 'গ্রাহক');
  String get addOrImportLeads =>
      pick('Add customers', 'ग्राहक जोड़ें', 'গ্রাহক যোগ করুন');
  String get searchLeadsHint => pick(
    'Search name, phone or interest',
    'नाम, फ़ोन या रुचि से खोजें',
    'নাম, ফোন বা আগ্রহ দিয়ে খুঁজুন',
  );
  String get filterAll => pick('All', 'सभी', 'সব');
  String get filterNew => pick('New', 'नई', 'নতুন');
  String get filterCalled => pick('Called', 'कॉल हुई', 'কল হয়েছে');
  String get filterHot => pick('Wants to buy', 'खरीदना चाहते हैं', 'কিনতে চান');
  String get filterWarm => pick('Thinking', 'सोच रहे हैं', 'ভাবছেন');
  String get filterCallback => pick('Call back', 'कॉल बैक', 'কল ব্যাক');
  String get noMatches =>
      pick('No matches', 'कुछ नहीं मिला', 'কিছু পাওয়া যায়নি');
  String noLeadsMatch(String q) => pick(
    'No customers match “$q”.',
    '“$q” से कोई ग्राहक नहीं मिला।',
    '“$q”-এর সঙ্গে কোনো গ্রাহক মিলল না।',
  );
  String get hotLeadsAppearAfterCalls => pick(
    'Customers ready to buy show up here after calls.',
    'कॉल के बाद खरीदने को तैयार ग्राहक यहाँ दिखेंगी।',
    'কলের পরে কিনতে তৈরি গ্রাহক এখানে দেখা যাবে।',
  );
  String get noLeadsHere => pick(
    'No customers here',
    'यहाँ कोई ग्राहक नहीं',
    'এখানে কোনো গ্রাহক নেই',
  );
  String get noLeadsForFilter => pick(
    'No customers match this filter yet.',
    'इस फ़िल्टर में अभी कोई ग्राहक नहीं।',
    'এই ফিল্টারে এখনও কোনো গ্রাহক নেই।',
  );
  String get interestUnknown => pick(
    'Interest not known yet',
    'रुचि अभी पता नहीं',
    'আগ্রহ এখনও জানা নেই',
  );
  String get onCall => pick('On call', 'कॉल पर', 'কলে আছেন');
  String get queued => pick('Queued', 'कतार में', 'লাইনে আছে');
  String get noAnswer => pick('No answer', 'जवाब नहीं', 'উত্তর নেই');

  /// Greeting pre-filled when there is no AI draft yet.
  String waGreeting(String firstName, String business) => pick(
    'Hi $firstName 👋\n\n${business.isEmpty ? '' : 'This is $business. '}',
    'नमस्ते $firstName 🙏\n\n${business.isEmpty ? '' : '$business से बात कर रहे हैं। '}',
    'নমস্কার $firstName 🙏\n\n${business.isEmpty ? '' : '$business থেকে বলছি। '}',
  );

  // ------------------------------------------------------------ Detail
  String get aiCallTooltip => pick('AI Call', 'AI कॉल', 'AI কল');
  String get callbackTooltip => pick('Call back', 'कॉल बैक', 'কল ব্যাক');
  String get aiSummary => pick('AI summary', 'AI सारांश', 'AI সারাংশ');
  String get fullCallResult =>
      pick('Full call result', 'कॉल का पूरा नतीजा', 'কলের পুরো ফলাফল');
  String get details => pick('Details', 'जानकारी', 'বিস্তারিত');
  String get notKnownYet =>
      pick('Not known yet', 'अभी पता नहीं', 'এখনও জানা নেই');
  String get language => pick('Language', 'भाषा', 'ভাষা');
  String get nextActionLabel => pick('Next action', 'अगला कदम', 'পরের পদক্ষেপ');
  String get callbackLabel => pick('Call back', 'कॉल बैक', 'কল ব্যাক');
  String get notScheduled => pick('Not scheduled', 'तय नहीं', 'ঠিক করা হয়নি');
  String get added => pick('Added', 'जोड़ी गई', 'যোগ হয়েছে');
  String get signals =>
      pick('What they said', 'उन्होंने क्या कहा', 'ওঁরা কী বললেন');
  String get positive => pick('Positive', 'अच्छा संकेत', 'ভালো সংকেত');
  String get concern => pick('Concern', 'चिंता', 'আপত্তি');
  String get followUpSection => pick('Message', 'मैसेज', 'মেসেজ');
  String get reviewAndSend =>
      pick('Review & send', 'देखें और भेजें', 'দেখে পাঠান');
  String get openAgain => pick('Open again', 'फिर से खोलें', 'আবার খুলুন');
  String get callHistory => pick('Call history', 'कॉल हिस्ट्री', 'কলের ইতিহাস');
  String notCalledYet(String agent, String lead) => pick(
    '$agent hasn\'t called $lead yet.',
    '$lead को अभी $agent की कॉल नहीं गई।',
    '$agent এখনও $lead-কে কল করেনি।',
  );
  String connectedFor(String duration) => pick(
    'Connected · $duration',
    'बात हुई · $duration',
    'কথা হয়েছে · $duration',
  );
  String get transcript =>
      pick('Full conversation', 'पूरी बातचीत', 'পুরো কথোপকথন');

  /// Label for a lead's extra detail (`attributes` key), e.g. `city` → "City".
  /// Keys added by the enquiry form and ad integrations are translated;
  /// anything else is humanised ("preferred_time" → "Preferred time").
  String attributeLabel(String key) => switch (key) {
    'email' => pick('Email', 'ईमेल', 'ইমেল'),
    'city' => pick('City', 'शहर', 'শহর'),
    'company' => pick('Company', 'कंपनी', 'কোম্পানি'),
    'google_campaign_id' => pick(
      'Google ad number',
      'Google विज्ञापन नंबर',
      'Google বিজ্ঞাপন নম্বর',
    ),
    'message' => pick('Their message', 'उनका संदेश', 'ওঁদের মেসেজ'),
    'notes' || 'note' => pick('Notes', 'नोट्स', 'নোট'),
    'budget' => pick('Budget', 'बजट', 'বাজেট'),
    'location' || 'area' => pick('Area', 'इलाक़ा', 'এলাকা'),
    'slot' ||
    'preferred_time' => pick('Preferred time', 'पसंद का समय', 'পছন্দের সময়'),
    'batch' => pick('Batch', 'बैच', 'ব্যাচ'),
    _ => _humanize(key),
  };

  String _humanize(String key) {
    final words = key.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (words.isEmpty) return key;
    return data(words[0].toUpperCase() + words.substring(1));
  }

  // ------------------------------------------------------------ Call sheet
  String callName(String name) =>
      pick('Call $name', '$name को कॉल करें', '$name-কে কল করুন');
  String aiCallBy(String agent) =>
      pick('AI call by $agent', '$agent से AI कॉल', '$agent-এর AI কল');
  String get callsTheirPhone =>
      pick('Calls their phone', 'उनके फ़ोन पर कॉल', 'ওঁর ফোনে কল যাবে');
  String talkInApp(String agent) => pick(
    'Talk in-app with $agent',
    'ऐप में $agent से बात करें',
    'অ্যাপে $agent-এর সঙ্গে কথা বলুন',
  );
  String get voiceTestInApp =>
      pick('Voice test in the app', 'ऐप में आवाज़ टेस्ट', 'অ্যাপে ভয়েস টেস্ট');
  String get callFromMyPhone =>
      pick('Call from my phone', 'मेरे फ़ोन से कॉल', 'আমার ফোন থেকে কল');
  String get usesYourSim =>
      pick('Uses your SIM', 'आपकी SIM से', 'আপনার SIM থেকে');
  String callingName(String name) => pick(
    'Calling $name…',
    '$name को कॉल लग रही है…',
    '$name-কে কল করা হচ্ছে…',
  );
  String agentIsCalling(String agent, String lead) => pick(
    '$agent is calling $lead',
    '$agent की कॉल $lead को जा रही है',
    '$agent এখন $lead-কে কল করছে',
  );
  String callNumber(String phone) =>
      pick('Call $phone', '$phone पर कॉल करें', '$phone-এ কল করুন');

  // ------------------------------------------------------------ Add / import
  String get addLeadsTitle =>
      pick('Add customers', 'ग्राहक जोड़ें', 'গ্রাহক যোগ করুন');
  String get importCsv => pick(
    'Add from Excel / file',
    'Excel / फ़ाइल से जोड़ें',
    'Excel / ফাইল থেকে যোগ করুন',
  );
  String get csvColumns => pick(
    'Name, Phone, Interest, Source',
    'नाम, फ़ोन, रुचि, स्रोत',
    'নাম, ফোন, আগ্রহ, উৎস',
  );
  String get chooseFile => pick('Choose file', 'फ़ाइल चुनें', 'ফাইল বাছুন');
  String get chooseAnotherFile =>
      pick('Choose another file', 'दूसरी फ़ाइल चुनें', 'অন্য ফাইল বাছুন');
  String get trySample => pick(
    'Try with sample customers',
    'नमूना ग्राहक से आज़माएँ',
    'নমুনা গ্রাহক দিয়ে দেখুন',
  );
  String get preview => pick('Preview', 'झलक', 'প্রিভিউ');
  String nReady(int n) => pick('$n ready', '$n तैयार', '$n টি তৈরি');
  String nSkipped(int n) =>
      pick('$n skipped', '$n छोड़ी गईं', '$n টি বাদ গেছে');
  String nMore(int n) => pick('+ $n more', '+ $n और', '+ আরও $n টি');
  String importN(int n) => pick(
    'Import $n customers',
    '$n ग्राहक इम्पोर्ट करें',
    '$n টি গ্রাহক ইমপোর্ট করুন',
  );
  String get orAddOne => pick(
    'Or add one customer',
    'या एक ग्राहक जोड़ें',
    'অথবা একটি গ্রাহক যোগ করুন',
  );
  String get customerNameHint =>
      pick('Customer name', 'ग्राहक का नाम', 'গ্রাহকের নাম');
  String get mobileNumberHint =>
      pick('Mobile number', 'मोबाइल नंबर', 'মোবাইল নম্বর');
  String optionalField(String label) =>
      pick('$label (optional)', '$label (ज़रूरी नहीं)', '$label (ঐচ্ছিক)');
  String get enterName => pick('Enter a name', 'नाम डालें', 'নাম লিখুন');
  String get addLead =>
      pick('Add customer', 'ग्राहक जोड़ें', 'গ্রাহক যোগ করুন');
  String get leadAdded =>
      pick('Customer added ✓', 'ग्राहक जुड़ गया ✓', 'গ্রাহক যোগ হয়েছে ✓');
  String get csvTooLarge => pick(
    'That file is over 2 MB. Split it and try again.',
    'फ़ाइल 2 MB से बड़ी है। उसे बाँटकर फिर कोशिश करें।',
    'ফাইলটি 2 MB-র বেশি। ভাগ করে আবার চেষ্টা করুন।',
  );
  String get csvUnreadable => pick(
    'Couldn\'t read that file. In Excel, use "Save as" → CSV and try again.',
    'फ़ाइल पढ़ी नहीं जा सकी। Excel में "Save as" → CSV चुनकर फिर कोशिश करें।',
    'ফাইলটি পড়া গেল না। Excel-এ "Save as" → CSV বেছে আবার চেষ্টা করুন।',
  );
  String get csvEmpty =>
      pick('The file is empty.', 'फ़ाइल खाली है।', 'ফাইলটি খালি।');
  String csvRowInvalid(String row) => pick(
    'Row $row: invalid phone number',
    'पंक्ति $row: फ़ोन नंबर गलत है',
    'সারি $row: ফোন নম্বর ভুল',
  );
  String nImported(int n) => pick(
    '$n customers imported',
    '$n ग्राहक इम्पोर्ट हुए',
    '$n টি গ্রাহক ইমপোর্ট হয়েছে',
  );
  String get callThemNow =>
      pick('Call them now', 'अभी कॉल करें', 'এখনই কল করুন');

  // ------------------------------------------------------ Phone contacts
  String get ctFromContacts =>
      pick('From phone contacts', 'फ़ोन कॉन्टैक्ट्स से', 'ফোনের কন্টাক্ট থেকে');
  String get ctFromContactsSub => pick(
    'Pick customers already saved in your phone. Easiest way to start.',
    'फ़ोन में सेव ग्राहक चुनें। शुरू करने का सबसे आसान तरीका।',
    'ফোনে সেভ করা গ্রাহক বেছে নিন। শুরু করার সবচেয়ে সহজ উপায়।',
  );
  String get ctChoose => pick(
    'Choose from contacts',
    'कॉन्टैक्ट्स से चुनें',
    'কন্টাক্ট থেকে বাছুন',
  );
  String get ctTitle => pick('Pick customers', 'ग्राहक चुनें', 'গ্রাহক বাছুন');
  String get ctSearch =>
      pick('Search name or number', 'नाम या नंबर खोजें', 'নাম বা নম্বর খুঁজুন');
  String get ctSelectAll => pick('Select all', 'सभी चुनें', 'সব বাছুন');
  String get ctClear => pick('Clear', 'हटाएँ', 'মুছুন');
  String ctAddN(int n) => plural(
    n,
    'Add 1 customer',
    'Add $n customers',
    '$n ग्राहक जोड़ें',
    '$n জন গ্রাহক যোগ করুন',
  );
  String get ctAccessTitle => pick(
    'Allow contacts',
    'कॉन्टैक्ट्स की अनुमति दें',
    'কন্টাক্টের অনুমতি দিন',
  );
  String get ctAccessBody => pick(
    'To pick customers, CallPilot needs to see your contacts. Only the people you choose are added.',
    'ग्राहक चुनने के लिए CallPilot को आपके कॉन्टैक्ट्स देखने होंगे। सिर्फ़ वही लोग जुड़ेंगे जिन्हें आप चुनेंगे।',
    'গ্রাহক বাছতে CallPilot-কে আপনার কন্টাক্ট দেখতে হবে। শুধু আপনি যাঁদের বাছবেন তাঁরাই যোগ হবেন।',
  );
  String get ctAllow => pick('Allow access', 'अनुमति दें', 'অনুমতি দিন');
  String get ctNone => pick(
    'No contacts with a mobile number',
    'मोबाइल नंबर वाला कोई कॉन्टैक्ट नहीं',
    'মোবাইল নম্বর সহ কোনো কন্টাক্ট নেই',
  );
  String get ctNoMatch => pick('No one matches', 'कोई नहीं मिला', 'কেউ মেলেনি');
  String get ctHaveFile => pick(
    'Add from Excel / file',
    'Excel / फ़ाइल से जोड़ें',
    'Excel / ফাইল থেকে যোগ করুন',
  );

  // Prominent disclosure, shown before Android's contacts permission prompt.
  String get ctDiscTitle => pick(
    'Before we open your contacts',
    'कॉन्टैक्ट्स खोलने से पहले',
    'কন্টাক্ট খোলার আগে',
  );
  String get ctDiscRead => pick(
    'CallPilot reads the names and numbers saved on this phone, only to show you the list.',
    'CallPilot इस फ़ोन में सेव नाम और नंबर पढ़ता है, सिर्फ़ आपको लिस्ट दिखाने के लिए।',
    'CallPilot এই ফোনে সেভ করা নাম আর নম্বর পড়ে, শুধু আপনাকে তালিকা দেখানোর জন্য।',
  );
  String get ctDiscSend => pick(
    'Only the people you tick are sent to CallPilot, so your AI employee can call them when you say so.',
    'सिर्फ़ जिन लोगों पर आप टिक करेंगे, वही CallPilot को भेजे जाएँगे, ताकि आपके कहने पर आपका AI कर्मचारी उन्हें कॉल कर सके।',
    'শুধু যাঁদের আপনি টিক দেবেন, তাঁরাই CallPilot-এ পাঠানো হবে, যাতে আপনি বললে আপনার AI কর্মী তাঁদের কল করতে পারে।',
  );
  String get ctDiscKeep => pick(
    'Everyone else stays on your phone. We never sell your contacts.',
    'बाकी सब आपके फ़ोन में ही रहते हैं। हम आपके कॉन्टैक्ट्स कभी नहीं बेचते।',
    'বাকি সবাই আপনার ফোনেই থাকে। আমরা কখনও আপনার কন্টাক্ট বিক্রি করি না।',
  );
  String get ctDiscAgree => pick(
    'I agree, continue',
    'मैं सहमत हूँ, आगे बढ़ें',
    'আমি রাজি, এগিয়ে যান',
  );
  String get ctDiscNo => pick('Not now', 'अभी नहीं', 'এখন না');

  // ------------------------------------------------------------ Consent history
  String get consentHistory =>
      pick('Permission to call', 'कॉल करने की अनुमति', 'কল করার অনুমতি');
  String get consentHistoryEmpty => pick(
    'Nothing noted yet about whether they agreed to calls.',
    'अभी तक कॉल की अनुमति के बारे में कुछ दर्ज नहीं।',
    'কলের অনুমতি নিয়ে এখনও কিছু লেখা নেই।',
  );

  /// What the consent was set to.
  String consentValue(String v) => switch (v) {
    'explicit_opt_in' => pick(
      'Agreed to be called',
      'कॉल के लिए सहमति दी',
      'কলের জন্য সম্মতি দিয়েছেন',
    ),
    'inquiry' => pick('Made an enquiry', 'पूछताछ की थी', 'জিজ্ঞাসা করেছিলেন'),
    'existing_customer' => pick(
      'Existing customer',
      'मौजूदा ग्राहक',
      'বর্তমান গ্রাহক',
    ),
    'owner_attested' => pick(
      'You confirmed they agreed to a call',
      'आपने बताया कि वे कॉल के लिए राज़ी हैं',
      'আপনি জানিয়েছেন ওঁরা কলে রাজি',
    ),
    'opt_out' => pick(
      'Asked not to be called',
      'कॉल न करने को कहा',
      'কল না করতে বলেছেন',
    ),
    'do_not_call' => pick(
      'Marked do not call',
      '“कॉल न करें” लगाया',
      '“কল করবেন না” দেওয়া হয়েছে',
    ),
    'do_not_call_removed' => pick(
      'Do not call removed',
      '“कॉल न करें” हटाया',
      '“কল করবেন না” সরানো হয়েছে',
    ),
    _ => pick(
      'Not known if they agreed to calls',
      'पता नहीं कि वे कॉल के लिए राज़ी हैं',
      'ওঁরা কলে রাজি কিনা জানা নেই',
    ),
  };

  /// Where the consent change came from.
  String consentSource(String v) => switch (v) {
    'form' => pick('Enquiry form', 'पूछताछ फ़ॉर्म', 'জিজ্ঞাসার ফর্ম'),
    'webhook' => pick('Your website', 'आपकी वेबसाइट', 'আপনার ওয়েবসাইট'),
    'google_ads' => pick(
      'Google Ads form',
      'Google Ads फ़ॉर्म',
      'Google Ads ফর্ম',
    ),
    'indiamart' => pick(
      'IndiaMART enquiry',
      'IndiaMART पूछताछ',
      'IndiaMART খোঁজ',
    ),
    'meta_lead_ads' => pick(
      'Facebook / Instagram form',
      'Facebook / Instagram फ़ॉर्म',
      'Facebook / Instagram ফর্ম',
    ),
    'import_attestation' => pick(
      'You added them and confirmed',
      'आपने जोड़ा और पुष्टि की',
      'আপনি যোগ করে নিশ্চিত করেছেন',
    ),
    'in_call_opt_out' => pick('Said so on a call', 'कॉल पर कहा', 'কলে বলেছেন'),
    _ => pick(
      'Added or edited by you',
      'आपने जोड़ा या बदला',
      'আপনি যোগ বা বদল করেছেন',
    ),
  };
}
