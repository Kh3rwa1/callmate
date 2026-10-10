import 's.dart';

/// Leads list, lead detail, calling a lead and adding/importing leads.
extension SLeads on S {
  // ------------------------------------------------------------ List
  String get leadsTitle => pick('Leads', 'लीड्स', 'লিড');
  String get addOrImportLeads => pick(
    'Add or import leads',
    'लीड्स जोड़ें या इम्पोर्ट करें',
    'লিড যোগ বা ইমপোর্ট করুন',
  );
  String get searchLeadsHint => pick(
    'Search name, phone or interest',
    'नाम, फ़ोन या रुचि से खोजें',
    'নাম, ফোন বা আগ্রহ দিয়ে খুঁজুন',
  );
  String get filterAll => pick('All', 'सभी', 'সব');
  String get filterNew => pick('New', 'नई', 'নতুন');
  String get filterCalled => pick('Called', 'कॉल हुई', 'কল হয়েছে');
  String get filterHot => pick('Hot', 'हॉट', 'হট');
  String get filterWarm => pick('Warm', 'वॉर्म', 'ওয়ার্ম');
  String get filterCallback => pick('Callback', 'कॉलबैक', 'কলব্যাক');
  String get noMatches =>
      pick('No matches', 'कुछ नहीं मिला', 'কিছু পাওয়া যায়নি');
  String noLeadsMatch(String q) => pick(
    'No leads match “$q”.',
    '“$q” से कोई लीड नहीं मिली।',
    '“$q”-এর সঙ্গে কোনো লিড মিলল না।',
  );
  String get hotLeadsAppearAfterCalls => pick(
    'Hot leads show up here after calls.',
    'कॉल के बाद हॉट लीड्स यहाँ दिखेंगी।',
    'কলের পরে হট লিড এখানে দেখা যাবে।',
  );
  String get noLeadsHere =>
      pick('No leads here', 'यहाँ कोई लीड नहीं', 'এখানে কোনো লিড নেই');
  String get noLeadsForFilter => pick(
    'No leads match this filter yet.',
    'इस फ़िल्टर में अभी कोई लीड नहीं।',
    'এই ফিল্টারে এখনও কোনো লিড নেই।',
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
  String get callbackTooltip => pick('Callback', 'कॉलबैक', 'কলব্যাক');
  String get aiSummary => pick('AI summary', 'AI सारांश', 'AI সারাংশ');
  String get fullCallResult =>
      pick('Full call result', 'कॉल का पूरा नतीजा', 'কলের পুরো ফলাফল');
  String get details => pick('Details', 'जानकारी', 'বিস্তারিত');
  String get notKnownYet =>
      pick('Not known yet', 'अभी पता नहीं', 'এখনও জানা নেই');
  String get language => pick('Language', 'भाषा', 'ভাষা');
  String get nextActionLabel => pick('Next action', 'अगला कदम', 'পরের পদক্ষেপ');
  String get callbackLabel => pick('Callback', 'कॉलबैक', 'কলব্যাক');
  String get notScheduled => pick('Not scheduled', 'तय नहीं', 'ঠিক করা হয়নি');
  String get added => pick('Added', 'जोड़ी गई', 'যোগ হয়েছে');
  String get signals => pick('Signals', 'संकेत', 'সংকেত');
  String get positive => pick('Positive', 'अच्छा संकेत', 'ভালো সংকেত');
  String get concern => pick('Concern', 'चिंता', 'আপত্তি');
  String get followUpSection => pick('Follow-up', 'फ़ॉलो-अप', 'ফলো-আপ');
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
  String get transcript => pick('Transcript', 'बातचीत', 'কথোপকথন');

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
  String get addLeadsTitle => pick('Add leads', 'लीड्स जोड़ें', 'লিড যোগ করুন');
  String get importCsv =>
      pick('Import CSV', 'CSV इम्पोर्ट करें', 'CSV ইমপোর্ট');
  String get csvColumns => pick(
    'Name, Phone, Interest, Source',
    'नाम, फ़ोन, रुचि, स्रोत',
    'নাম, ফোন, আগ্রহ, উৎস',
  );
  String get chooseFile => pick('Choose file', 'फ़ाइल चुनें', 'ফাইল বাছুন');
  String get chooseAnotherFile =>
      pick('Choose another file', 'दूसरी फ़ाइल चुनें', 'অন্য ফাইল বাছুন');
  String get trySample => pick(
    'Try with sample leads',
    'नमूना लीड्स से आज़माएँ',
    'নমুনা লিড দিয়ে দেখুন',
  );
  String get preview => pick('Preview', 'झलक', 'প্রিভিউ');
  String nReady(int n) => pick('$n ready', '$n तैयार', '$n টি তৈরি');
  String nSkipped(int n) =>
      pick('$n skipped', '$n छोड़ी गईं', '$n টি বাদ গেছে');
  String nMore(int n) => pick('+ $n more', '+ $n और', '+ আরও $n টি');
  String importN(int n) => pick(
    'Import $n leads',
    '$n लीड्स इम्पोर्ट करें',
    '$n টি লিড ইমপোর্ট করুন',
  );
  String get orAddOne =>
      pick('Or add one lead', 'या एक लीड जोड़ें', 'অথবা একটি লিড যোগ করুন');
  String get customerNameHint =>
      pick('Customer name', 'ग्राहक का नाम', 'গ্রাহকের নাম');
  String get mobileNumberHint =>
      pick('Mobile number', 'मोबाइल नंबर', 'মোবাইল নম্বর');
  String optionalField(String label) =>
      pick('$label (optional)', '$label (ज़रूरी नहीं)', '$label (ঐচ্ছিক)');
  String get enterName => pick('Enter a name', 'नाम डालें', 'নাম লিখুন');
  String get addLead => pick('Add lead', 'लीड जोड़ें', 'লিড যোগ করুন');
  String get leadAdded =>
      pick('Lead added ✓', 'लीड जुड़ गई ✓', 'লিড যোগ হয়েছে ✓');
  String get csvTooLarge => pick(
    'That file is over 2 MB. Split it and try again.',
    'फ़ाइल 2 MB से बड़ी है। उसे बाँटकर फिर कोशिश करें।',
    'ফাইলটি 2 MB-র বেশি। ভাগ করে আবার চেষ্টা করুন।',
  );
  String get csvUnreadable => pick(
    'Couldn\'t read that file. Make sure it\'s a CSV.',
    'फ़ाइल पढ़ी नहीं जा सकी। देखें कि यह CSV है।',
    'ফাইলটি পড়া গেল না। এটি CSV কিনা দেখুন।',
  );
  String get csvEmpty =>
      pick('The file is empty.', 'फ़ाइल खाली है।', 'ফাইলটি খালি।');
  String csvRowInvalid(String row) => pick(
    'Row $row: invalid phone number',
    'पंक्ति $row: फ़ोन नंबर गलत है',
    'সারি $row: ফোন নম্বর ভুল',
  );
  String nImported(int n) => pick(
    '$n leads imported',
    '$n लीड्स इम्पोर्ट हुईं',
    '$n টি লিড ইমপোর্ট হয়েছে',
  );
  String get callThemNow =>
      pick('Call them now', 'अभी कॉल करें', 'এখনই কল করুন');
}
