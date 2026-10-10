import 's.dart';

/// Speed-to-lead: "Get leads automatically" (enquiry form, webhooks) and
/// lead source chips.
extension SLeadCapture on S {
  String get getLeadsAutomatically => pick(
    'Get leads automatically',
    'अपने-आप ग्राहक पाएँ',
    'নিজে থেকে গ্রাহক পান',
  );
  String get leadCaptureIntro => pick(
    'Share your enquiry form. Every new enquiry gets a call from your AI employee in about a minute.',
    'अपना पूछताछ फ़ॉर्म शेयर करें। हर नई पूछताछ पर आपका AI कर्मचारी लगभग एक मिनट में कॉल करेगा।',
    'আপনার খোঁজের ফর্ম শেয়ার করুন। প্রতিটি নতুন খোঁজে আপনার AI কর্মী প্রায় এক মিনিটে কল করবে।',
  );
  String get leadCaptureEntrySubtitle => pick(
    'Form link, QR code and website connection',
    'फ़ॉर्म लिंक, QR कोड और वेबसाइट कनेक्शन',
    'ফর্ম লিংক, QR কোড আর ওয়েবসাইট সংযোগ',
  );
  String get enquiryForm =>
      pick('Enquiry form', 'पूछताछ फ़ॉर्म', 'খোঁজের ফর্ম');
  String get enquiryFormHint => pick(
    'Put this link on Instagram, WhatsApp or Google, or print the QR code.',
    'यह लिंक Instagram, WhatsApp या Google पर डालें, या QR कोड प्रिंट करें।',
    'এই লিংক Instagram, WhatsApp বা Google-এ দিন, বা QR কোড প্রিন্ট করুন।',
  );
  String get createFormLink => pick(
    'Create my form link',
    'मेरा फ़ॉर्म लिंक बनाएँ',
    'আমার ফর্ম লিংক বানান',
  );
  String get copyLink => pick('Copy link', 'लिंक कॉपी करें', 'লিংক কপি করুন');
  String get shareLink => pick('Share', 'शेयर करें', 'শেয়ার করুন');
  String get showQr => pick('QR code', 'QR कोड', 'QR কোড');
  String get linkCopied =>
      pick('Link copied', 'लिंक कॉपी हो गया', 'লিংক কপি হয়েছে');
  String get copied => pick('Copied', 'कॉपी हो गया', 'কপি হয়েছে');
  String shareFormText(String business, String url) => pick(
    'Enquire with $business and get a call back in a minute: $url',
    '$business से पूछताछ करें और एक मिनट में कॉल पाएँ: $url',
    '$business-এ খোঁজ নিন, এক মিনিটে কল পান: $url',
  );
  String get autoCallNewEnquiries => pick(
    'AI calls new enquiries',
    'AI नई पूछताछ पर कॉल करे',
    'AI নতুন খোঁজে কল করবে',
  );
  String get autoCallHint => pick(
    'Within about a minute, during calling hours',
    'लगभग एक मिनट में, कॉलिंग के समय में',
    'প্রায় এক মিনিটে, কলের সময়ের মধ্যে',
  );
  String enquiriesCount(int n) => plural(
    n,
    '1 enquiry so far',
    '$n enquiries so far',
    'अब तक $n पूछताछ',
    'এখন পর্যন্ত $n টি খোঁজ',
  );
  String get websiteConnections => pick(
    'Website & Google Forms',
    'वेबसाइट और Google Forms',
    'ওয়েবসাইট ও Google Forms',
  );
  String get websiteConnectionsHint => pick(
    'For your web developer: a secure link your website or Google Form can send enquiries to.',
    'आपके वेब डेवलपर के लिए: एक सुरक्षित लिंक जिस पर आपकी वेबसाइट या Google Form पूछताछ भेज सके।',
    'আপনার ওয়েব ডেভেলপারের জন্য: একটি নিরাপদ লিংক যেখানে আপনার ওয়েবসাইট বা Google Form খোঁজ পাঠাতে পারে।',
  );
  String get addWebsiteConnection => pick(
    'Add website connection',
    'वेबसाइट कनेक्शन जोड़ें',
    'ওয়েবসাইট সংযোগ যোগ করুন',
  );
  String get websiteConnection =>
      pick('Website connection', 'वेबसाइट कनेक्शन', 'ওয়েবসাইট সংযোগ');
  String get secretKey => pick('Secret key', 'सीक्रेट की', 'সিক্রেট কী');
  String get webhookUrl => pick('Address (URL)', 'पता (URL)', 'ঠিকানা (URL)');
  String get tokenShownOnce => pick(
    'Copy the secret key now and send it to your web developer. For your safety it is shown only once.',
    'सीक्रेट की अभी कॉपी करके अपने वेब डेवलपर को भेजें। सुरक्षा के लिए यह सिर्फ़ एक बार दिखेगी।',
    'সিক্রেট কী এখনই কপি করে আপনার ওয়েব ডেভেলপারকে পাঠান। নিরাপত্তার জন্য এটি একবারই দেখানো হবে।',
  );
  String get copyForDeveloper => pick(
    'Copy setup for developer',
    'डेवलपर के लिए सेटअप कॉपी करें',
    'ডেভেলপারের জন্য সেটআপ কপি করুন',
  );
  String get turnOff => pick('Turn off', 'बंद करें', 'বন্ধ করুন');
  String get turnOffLinkTitle =>
      pick('Turn off this link?', 'यह लिंक बंद करें?', 'এই লিংক বন্ধ করবেন?');
  String get turnOffLinkBody => pick(
    'It stops accepting enquiries right away. Customers you already have stay.',
    'यह तुरंत पूछताछ लेना बंद कर देगा। जो ग्राहक पहले से हैं, वे रहेंगे।',
    'এটি সঙ্গে সঙ্গে খোঁজ নেওয়া বন্ধ করবে। আগের গ্রাহকরা থাকবেন।',
  );
  String get leadCaptureLoadFailed => pick(
    'Could not load your enquiry form.',
    'आपका पूछताछ फ़ॉर्म लोड नहीं हुआ।',
    'আপনার খোঁজের ফর্ম লোড হয়নি।',
  );
  String get formNewLink =>
      pick('Get a new link', 'नया लिंक बनाएँ', 'নতুন লিংক বানান');

  /// Chip on a lead row / detail: where an automatic lead came from.
  /// Null for leads added by hand or imported.
  String? leadSourceLabel(String source) => switch (source) {
    'form' => pick('Form', 'फ़ॉर्म', 'ফর্ম'),
    'webhook' => pick('Website', 'वेबसाइट', 'ওয়েবসাইট'),
    _ => null,
  };

  // Demo tools
  String get simulateFormEnquiry => pick(
    'Simulate new form enquiry → auto call',
    'नई फ़ॉर्म पूछताछ → ऑटो कॉल (डेमो)',
    'নতুন ফর্ম খোঁজ → অটো কল (ডেমো)',
  );
}
