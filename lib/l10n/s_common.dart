import '../core/utils/format.dart';
import '../data/models/models.dart';
import '../data/templates/templates.dart';
import 's.dart';

/// Strings shared by many screens, and labels for domain enums.
///
/// Hindi strings avoid verbs that agree with the AI employee's gender
/// ("Riya कॉल कर रही है" vs "Arjun … रहा है"), since the employee can be
/// either; Bengali verbs don't inflect for gender.
extension SCommon on S {
  // ------------------------------------------------------------ Actions
  String get continueLabel => pick('Continue', 'आगे बढ़ें', 'এগিয়ে যান');
  String get cancel => pick('Cancel', 'रद्द करें', 'বাতিল');
  String get tryAgain =>
      pick('Try again', 'फिर से कोशिश करें', 'আবার চেষ্টা করুন');
  String get done => pick('Done', 'हो गया', 'হয়ে গেছে');
  String get save => pick('Save', 'सेव करें', 'সেভ করুন');
  String get saveChanges =>
      pick('Save changes', 'बदलाव सेव करें', 'পরিবর্তন সেভ করুন');
  String get skip => pick('Skip', 'छोड़ें', 'বাদ দিন');
  String get later => pick('Later', 'बाद में', 'পরে');
  String get notNow => pick('Not now', 'अभी नहीं', 'এখন না');
  String get edit => pick('Edit', 'बदलें', 'এডিট');
  String get remove => pick('Remove', 'हटाएँ', 'সরান');
  String get ok => pick('OK', 'ठीक है', 'ঠিক আছে');
  String get share => pick('Share…', 'शेयर करें…', 'শেয়ার করুন…');
  String get copyMessage =>
      pick('Copy Message', 'मैसेज कॉपी करें', 'মেসেজ কপি করুন');
  String get messageCopied =>
      pick('Message copied', 'मैसेज कॉपी हुआ', 'মেসেজ কপি হয়েছে');
  String get back => pick('Back', 'वापस', 'ফিরে যান');
  String get more => pick('More', 'और', 'আরও');
  String get clear => pick('Clear', 'साफ़ करें', 'মুছুন');
  String get call => pick('Call', 'कॉल', 'কল');
  String get whatsapp => 'WhatsApp';
  String get optional => pick('Optional', 'ज़रूरी नहीं', 'ঐচ্ছিক');
  String get loading => pick('Loading', 'लोड हो रहा है', 'লোড হচ্ছে');
  String get seeAll => pick('See all', 'सब देखें', 'সব দেখুন');
  String get undo => pick('Undo', 'वापस लें', 'ফিরিয়ে আনুন');

  // ------------------------------------------------------------ Generic
  String get allCaughtUp => pick('All caught up', 'सब हो गया', 'সব কাজ শেষ');
  String get somethingWentWrong => pick(
    'Something went wrong. Try again.',
    'कुछ गड़बड़ हो गई। फिर से कोशिश करें।',
    'কিছু একটা ভুল হয়েছে। আবার চেষ্টা করুন।',
  );
  String get errorTitle =>
      pick('Hmm, that didn\'t work', 'यह नहीं हो पाया', 'এটা হলো না');
  String get errNotFound => pick(
    'We couldn\'t find that. It may have been removed.',
    'यह नहीं मिला। शायद हटा दिया गया है।',
    'এটা খুঁজে পাওয়া গেল না। হয়তো সরিয়ে দেওয়া হয়েছে।',
  );
  String get errOffline => pick(
    'No connection. Check your internet and try again.',
    'इंटरनेट नहीं है। कनेक्शन देखकर फिर से कोशिश करें।',
    'ইন্টারনেট নেই। সংযোগ দেখে আবার চেষ্টা করুন।',
  );
  String get errRateLimit => pick(
    'Too many attempts. Please wait 10 minutes before requesting a new code.',
    'बहुत बार कोशिश हुई। नया कोड माँगने से पहले 10 मिनट रुकें।',
    'অনেকবার চেষ্টা হয়েছে। নতুন কোড চাওয়ার আগে 10 মিনিট অপেক্ষা করুন।',
  );
  String get errInvalidOtp => pick(
    'That code is wrong or too old. Please check it and try again.',
    'कोड गलत है या पुराना हो गया। कोड देखकर फिर डालें।',
    'কোডটি ভুল বা পুরোনো। কোডটি দেখে আবার দিন।',
  );
  String get errOtpLocked => pick(
    'Too many wrong tries. Please ask for a new code.',
    'कई बार गलत कोड डाला गया। नया कोड माँगें।',
    'অনেকবার ভুল কোড দেওয়া হয়েছে। নতুন কোড চান।',
  );
  String get errPhoneRegistered => pick(
    'This phone number is already registered. Please sign in instead.',
    'यह नंबर पहले से रजिस्टर्ड है। साइन इन करें।',
    'এই নম্বর আগেই রেজিস্টার করা আছে। সাইন ইন করুন।',
  );
  String get errSessionExpired => pick(
    'Your session ended. Please sign in again.',
    'आपका सेशन खत्म हो गया। दोबारा साइन इन करें।',
    'আপনার সেশন শেষ হয়েছে। আবার সাইন ইন করুন।',
  );
  String get validPhone => pick(
    'Enter a valid 10-digit mobile number',
    'सही 10 अंकों का मोबाइल नंबर डालें',
    'সঠিক 10 সংখ্যার মোবাইল নম্বর দিন',
  );
  String get validPhoneShort => pick(
    'Enter a valid mobile number',
    'सही मोबाइल नंबर डालें',
    'সঠিক মোবাইল নম্বর দিন',
  );
  String get phoneLooksWrong => pick(
    'This phone number doesn\'t look right. Edit the customer and try again.',
    'यह फ़ोन नंबर सही नहीं लग रहा। ग्राहक बदलकर फिर कोशिश करें।',
    'ফোন নম্বরটা ঠিক মনে হচ্ছে না। গ্রাহক এডিট করে আবার চেষ্টা করুন।',
  );
  String get pdfTooLarge => pick(
    'That PDF is over 15 MB. Try a smaller file.',
    'यह PDF 15 MB से बड़ी है। छोटी फ़ाइल चुनें।',
    'PDF-টি 15 MB-র বেশি। ছোট ফাইল দিন।',
  );
  String get pdfUnreadable => pick(
    'Couldn\'t open that file. Try another PDF.',
    'यह फ़ाइल नहीं खुली। कोई और PDF चुनें।',
    'ফাইলটি খোলা গেল না। অন্য PDF দিন।',
  );

  // ------------------------------------------------------------ Domain words
  String get aiEmployee => pick('AI employee', 'AI कर्मचारी', 'AI কর্মী');
  String get aiEmployeeTitle => pick('AI Employee', 'AI कर्मचारी', 'AI কর্মী');
  String get yourAiEmployee =>
      pick('Your AI employee', 'आपका AI कर्मचारी', 'আপনার AI কর্মী');
  String get leadsWord => pick('Customers', 'ग्राहक', 'গ্রাহক');
  String get sample => pick('Sample', 'नमूना', 'নমুনা');
  String get active => pick('Active', 'सक्रिय', 'চালু');
  String get notScoredYet =>
      pick('Not called yet', 'अभी कॉल नहीं हुई', 'এখনও কল হয়নি');

  /// "3 min" with the unit in each language.
  String minutes(int n) => pick('$n min', '$n मिनट', '$n মিনিট');

  // ------------------------------------------------------------ Enums
  String leadStatus(LeadStatus v) => switch (v) {
    LeadStatus.newLead => pick('New', 'नया', 'নতুন'),
    LeadStatus.queued => pick('Queued', 'कतार में', 'লাইনে আছে'),
    LeadStatus.calling => pick('Calling', 'कॉल जारी', 'কল চলছে'),
    LeadStatus.called => pick('Called', 'कॉल हो चुकी', 'কল হয়েছে'),
    LeadStatus.callback => pick('Call back', 'कॉल बैक', 'কল ব্যাক'),
    LeadStatus.noAnswer => pick('No answer', 'जवाब नहीं', 'উত্তর নেই'),
    LeadStatus.converted => pick(
      'Became a customer',
      'ग्राहक बन गए',
      'গ্রাহক হয়েছেন',
    ),
    LeadStatus.notInterested => pick(
      'Not interested',
      'रुचि नहीं',
      'আগ্রহী নন',
    ),
  };

  /// What the customer wants, in the owner's words: never "hot/warm/cold"
  /// or a score.
  String temperature(LeadTemperature v) => switch (v) {
    LeadTemperature.hot => pick(
      'Wants to buy',
      'खरीदना चाहते हैं',
      'কিনতে চান',
    ),
    LeadTemperature.warm => pick('Thinking about it', 'सोच रहे हैं', 'ভাবছেন'),
    LeadTemperature.cold => pick(
      'Not interested now',
      'अभी रुचि नहीं',
      'এখন আগ্রহ নেই',
    ),
    LeadTemperature.unknown => pick('New', 'नया', 'নতুন'),
  };

  /// Short form for small badges in lists, where the full words get cut
  /// off on a phone ("Not interested n…"). Detail screens keep [temperature].
  String temperatureShort(LeadTemperature v) => switch (v) {
    LeadTemperature.hot => pick('Wants to buy', 'खरीदना चाहें', 'কিনতে চান'),
    LeadTemperature.warm => pick('Thinking', 'सोच रहे हैं', 'ভাবছেন'),
    LeadTemperature.cold => pick('Not now', 'अभी नहीं', 'এখন নয়'),
    LeadTemperature.unknown => pick('New', 'नया', 'নতুন'),
  };

  String intent(LeadIntent v) => switch (v) {
    LeadIntent.interested => pick('Interested', 'रुचि है', 'আগ্রহী'),
    LeadIntent.exploring => pick(
      'Exploring',
      'जानकारी ले रहे हैं',
      'খোঁজ নিচ্ছেন',
    ),
    LeadIntent.notInterested => pick(
      'Not interested',
      'रुचि नहीं',
      'আগ্রহী নন',
    ),
    LeadIntent.callbackRequested => pick(
      'Wants a call back',
      'कॉल बैक चाहते हैं',
      'কল ব্যাক চান',
    ),
    LeadIntent.unknown => pick('Unknown', 'पता नहीं', 'জানা নেই'),
  };

  String callStatus(CallStatus v) => switch (v) {
    CallStatus.queued => pick('Queued', 'कतार में', 'লাইনে আছে'),
    CallStatus.ringing => pick('Ringing', 'घंटी जा रही है', 'রিং হচ্ছে'),
    CallStatus.inProgress => pick('On call', 'कॉल पर', 'কলে আছেন'),
    CallStatus.completed => pick('Connected', 'बात हुई', 'কথা হয়েছে'),
    CallStatus.noAnswer => pick('No answer', 'जवाब नहीं', 'উত্তর নেই'),
    CallStatus.busy => pick('Busy', 'व्यस्त', 'ব্যস্ত'),
    CallStatus.failed => pick('Failed', 'कॉल नहीं लगी', 'কল যায়নি'),
  };

  /// One owner-facing label per next action, used on every screen.
  String nextAction(NextAction v) => switch (v) {
    NextAction.humanFollowUp => pick(
      'You should call',
      'टीम से मैसेज',
      'টিমের মেসেজ',
    ),
    NextAction.sendWhatsapp => pick(
      'Send WhatsApp',
      'WhatsApp भेजें',
      'WhatsApp পাঠান',
    ),
    NextAction.whatsappAndCallback => pick(
      'WhatsApp + call back',
      'WhatsApp + कॉल बैक',
      'WhatsApp + কল ব্যাক',
    ),
    NextAction.bookAppointment => pick(
      'Book appointment / visit',
      'अपॉइंटमेंट / विज़िट बुक करें',
      'অ্যাপয়েন্টমেন্ট / ভিজিট বুক করুন',
    ),
    NextAction.retryCall => pick(
      'Try calling again',
      'फिर से कॉल करें',
      'আবার কল করুন',
    ),
    NextAction.none => pick(
      'No action needed',
      'कुछ करने की ज़रूरत नहीं',
      'কিছু করার দরকার নেই',
    ),
  };

  String followUpStatus(FollowUpStatus v) => switch (v) {
    FollowUpStatus.ready => pick(
      'Ready to send',
      'भेजने के लिए तैयार',
      'পাঠানোর জন্য তৈরি',
    ),
    FollowUpStatus.opened => pick(
      'WhatsApp opened',
      'WhatsApp खुला',
      'WhatsApp খোলা হয়েছে',
    ),
    FollowUpStatus.done => pick(
      'Marked as sent by you',
      'आपने भेजा',
      'আপনি পাঠিয়েছেন',
    ),
    FollowUpStatus.dismissed => pick('Dismissed', 'हटाया गया', 'বাদ দেওয়া'),
  };

  String campaignStatus(CampaignStatus v) => switch (v) {
    CampaignStatus.draft => pick('Draft', 'ड्राफ़्ट', 'খসড়া'),
    CampaignStatus.running => pick('Running', 'चल रहा है', 'চলছে'),
    CampaignStatus.paused => pick('Paused', 'रुका हुआ', 'থেমে আছে'),
    CampaignStatus.completed => pick('Completed', 'पूरा हुआ', 'শেষ হয়েছে'),
    CampaignStatus.stopped => pick('Stopped', 'बंद किया', 'বন্ধ করা হয়েছে'),
  };

  String knowledgeType(KnowledgeType v) => switch (v) {
    KnowledgeType.pdf => 'PDF',
    KnowledgeType.website => pick('Website', 'वेबसाइट', 'ওয়েবসাইট'),
    KnowledgeType.faq => pick('FAQ', 'सवाल-जवाब', 'প্রশ্নোত্তর'),
    KnowledgeType.text => pick('Notes', 'नोट्स', 'নোট'),
    KnowledgeType.businessInfo => pick(
      'Business information',
      'कारोबार की जानकारी',
      'ব্যবসার তথ্য',
    ),
  };

  String agentStatus(AgentStatus v) => switch (v) {
    AgentStatus.active => active,
    AgentStatus.paused => pick('Paused', 'रुका हुआ', 'থেমে আছে'),
    AgentStatus.inactive => pick('Inactive', 'बंद', 'বন্ধ'),
    AgentStatus.training => pick('Learning', 'सीखना जारी', 'শিখছে'),
  };

  String category(BusinessCategory v) => switch (v) {
    BusinessCategory.coaching => pick(
      'Coaching Centre',
      'कोचिंग सेंटर',
      'কোচিং সেন্টার',
    ),
    BusinessCategory.realEstate => pick(
      'Real Estate',
      'रियल एस्टेट',
      'রিয়েল এস্টেট',
    ),
    BusinessCategory.clinic => pick('Clinic', 'क्लिनिक', 'ক্লিনিক'),
    BusinessCategory.diagnostic => pick(
      'Diagnostic Centre',
      'डायग्नोस्टिक सेंटर',
      'ডায়াগনস্টিক সেন্টার',
    ),
    BusinessCategory.automobile => pick('Automobile', 'ऑटोमोबाइल', 'অটোমোবাইল'),
    BusinessCategory.salon => pick('Salon', 'सैलून', 'সেলুন'),
    BusinessCategory.gym => pick(
      'Gym & Fitness',
      'जिम और फ़िटनेस',
      'জিম ও ফিটনেস',
    ),
    BusinessCategory.restaurant => pick(
      'Restaurant',
      'रेस्टोरेंट',
      'রেস্তোরাঁ',
    ),
    BusinessCategory.retail => pick('Retail', 'रिटेल दुकान', 'খুচরো দোকান'),
    BusinessCategory.localServices => pick(
      'Local Services',
      'लोकल सर्विस',
      'লোকাল সার্ভিস',
    ),
    BusinessCategory.other => pick('Other', 'अन्य', 'অন্যান্য'),
  };

  String skill(EmployeeSkill v) => switch (v) {
    EmployeeSkill.makeCalls => pick('Make Calls', 'कॉल करना', 'কল করা'),
    EmployeeSkill.qualifyLeads => pick(
      'Find Serious Buyers',
      'गंभीर खरीदार पहचानना',
      'আসল ক্রেতা চেনা',
    ),
    EmployeeSkill.followUp => pick('Follow Up', 'मैसेज', 'মেসেজ'),
    EmployeeSkill.bookAppointments => pick(
      'Book Appointments',
      'अपॉइंटमेंट बुक करना',
      'অ্যাপয়েন্টমেন্ট বুক',
    ),
    EmployeeSkill.sales => pick('Sales', 'सेल्स', 'সেলস'),
    EmployeeSkill.customerSupport => pick(
      'Customer Support',
      'कस्टमर सपोर्ट',
      'কাস্টমার সাপোর্ট',
    ),
    EmployeeSkill.admissions => pick('Admissions', 'एडमिशन', 'ভর্তি'),
    EmployeeSkill.enquiryHandling => pick(
      'Enquiry Handling',
      'पूछताछ संभालना',
      'জিজ্ঞাসার উত্তর',
    ),
  };

  // ------------------------------------------------------------ Dates
  String relative(DateTime d) => Fmt.relative(d, lang: lang);
  String friendlyFuture(DateTime d) => Fmt.friendlyFuture(d, lang: lang);
  String callbackPhrase(DateTime d) => Fmt.callbackPhrase(d, lang: lang);
  String dayLabel(DateTime d) => Fmt.dayLabel(d, lang: lang);
  String date(DateTime d) => Fmt.date(d, lang: lang);
  String greeting() => Fmt.greeting(null, lang);

  /// Generic fallback when the employee hasn't loaded yet.
  String employeeName(String? name) =>
      (name == null || name.isEmpty) ? yourAiEmployee : name;
}
