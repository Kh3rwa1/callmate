import 's.dart';

/// Speed-to-lead: "Get leads automatically" (enquiry form, webhooks, lead
/// source integrations) and lead source chips.
extension SLeadCapture on S {
  String get getLeadsAutomatically => pick(
    'Get new customers automatically',
    'अपने-आप नए ग्राहक पाएँ',
    'নিজে থেকে নতুন গ্রাহক পান',
  );
  String get leadCaptureIntro => pick(
    'Share your enquiry form. Every new enquiry gets a call from your AI employee in about a minute.',
    'अपना पूछताछ फ़ॉर्म शेयर करें। हर नई पूछताछ पर आपका AI कर्मचारी लगभग एक मिनट में कॉल करेगा।',
    'আপনার খোঁজের ফর্ম শেয়ার করুন। প্রতিটি নতুন খোঁজে আপনার AI কর্মী প্রায় এক মিনিটে কল করবে।',
  );
  String get leadCaptureEntrySubtitle => pick(
    'Form link, QR code and your website',
    'फ़ॉर्म लिंक, QR कोड और आपकी वेबसाइट',
    'ফর্ম লিংক, QR কোড আর আপনার ওয়েবসাইট',
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
    'Enquiries from your website or Google Form come straight here. The person who made your website sets it up once.',
    'आपकी वेबसाइट या Google Form की पूछताछ सीधे यहाँ आएगी। जिसने आपकी वेबसाइट बनाई है, वह इसे एक बार सेट कर दे।',
    'আপনার ওয়েবসাইট বা Google Form-এর খোঁজ সোজা এখানে আসবে। যিনি আপনার ওয়েবসাইট বানিয়েছেন, তিনি একবার এটা সেট করে দেবেন।',
  );
  String get addWebsiteConnection => pick(
    'Connect your website',
    'अपनी वेबसाइट जोड़ें',
    'আপনার ওয়েবসাইট যুক্ত করুন',
  );
  String get websiteConnection => pick(
    'Connect your website',
    'अपनी वेबसाइट जोड़ें',
    'আপনার ওয়েবসাইট যুক্ত করুন',
  );
  String get secretKey => pick(
    'Password for your website',
    'आपकी वेबसाइट का पासवर्ड',
    'আপনার ওয়েবসাইটের পাসওয়ার্ড',
  );
  String get webhookUrl =>
      pick('Website link', 'वेबसाइट लिंक', 'ওয়েবসাইট লিংক');
  String get tokenShownOnce => pick(
    'Copy this password now and send it to the person who made your website. For your safety it is shown only once.',
    'यह पासवर्ड अभी कॉपी करके उसे भेजें जिसने आपकी वेबसाइट बनाई है। सुरक्षा के लिए यह सिर्फ़ एक बार दिखेगा।',
    'এই পাসওয়ার্ড এখনই কপি করে যিনি আপনার ওয়েবসাইট বানিয়েছেন তাঁকে পাঠান। নিরাপত্তার জন্য এটি একবারই দেখানো হবে।',
  );
  String get copyForDeveloper => pick(
    'Copy and send to the person who made your website',
    'कॉपी करके उसे भेजें जिसने आपकी वेबसाइट बनाई',
    'কপি করে তাঁকে পাঠান যিনি আপনার ওয়েবসাইট বানিয়েছেন',
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
    'google_ads' => 'Google Ads',
    'indiamart' => 'IndiaMART',
    'meta' => 'Facebook',
    _ => null,
  };

  // Demo tools
  String get simulateFormEnquiry => pick(
    'Simulate new form enquiry → auto call',
    'नई फ़ॉर्म पूछताछ → ऑटो कॉल (डेमो)',
    'নতুন ফর্ম খোঁজ → অটো কল (ডেমো)',
  );

  // Lead-source integrations (Google Ads, IndiaMART, Meta Lead Ads)
  String get connectLeadSource => pick(
    'Get customers from your ads',
    'अपने विज्ञापनों से ग्राहक पाएँ',
    'আপনার বিজ্ঞাপন থেকে গ্রাহক পান',
  );
  String get connectLeadSourceHint => pick(
    'Customers from your ads and IndiaMART come in by themselves and get an AI call in about a minute.',
    'आपके विज्ञापनों और IndiaMART के ग्राहक अपने-आप आएँगे और लगभग एक मिनट में AI कॉल करेगा।',
    'আপনার বিজ্ঞাপন আর IndiaMART-এর গ্রাহক নিজে থেকে আসবেন, AI প্রায় এক মিনিটে কল করবে।',
  );
  String get googleAdsName => 'Google Ads';
  String get indiaMartName => 'IndiaMART';
  String get metaName => pick(
    'Facebook & Instagram',
    'Facebook और Instagram',
    'Facebook ও Instagram',
  );
  String get googleAdsTileHint =>
      pick('Ads with a form', 'फ़ॉर्म वाले विज्ञापन', 'ফর্মসহ বিজ্ঞাপন');
  String get indiaMartTileHint => pick(
    'Buyer enquiries from Lead Manager',
    'Lead Manager से खरीदारों की पूछताछ',
    'Lead Manager থেকে ক্রেতাদের খোঁজ',
  );
  String get metaTileHint => pick(
    'Lead Ads instant forms',
    'Lead Ads इंस्टेंट फ़ॉर्म',
    'Lead Ads ইনস্ট্যান্ট ফর্ম',
  );
  String get connect => pick('Connect', 'जोड़ें', 'যুক্ত করুন');
  String get connected => pick('Connected', 'जुड़ा हुआ', 'যুক্ত আছে');
  String get notConnected => pick('Not connected', 'जुड़ा नहीं', 'যুক্ত নেই');
  String get howToConnect =>
      pick('How to connect', 'कैसे जोड़ें', 'কীভাবে যুক্ত করবেন');

  List<String> get googleAdsSteps => [
    pick(
      'Tap Connect below. You get a link and a password.',
      'नीचे "जोड़ें" दबाएँ। आपको एक लिंक और एक पासवर्ड मिलेगा।',
      'নিচে "যুক্ত করুন" চাপুন। একটি লিংক আর একটি পাসওয়ার্ড পাবেন।',
    ),
    pick(
      'In Google Ads, open your lead form, go to "Lead delivery options" → "Webhook integration" and paste both.',
      'Google Ads में अपना फ़ॉर्म खोलें, "Lead delivery options" → "Webhook integration" में दोनों पेस्ट करें।',
      'Google Ads-এ আপনার ফর্ম খুলুন, "Lead delivery options" → "Webhook integration"-এ দুটোই পেস্ট করুন।',
    ),
    pick(
      'Tap "Send test data" in Google Ads to check. Test enquiries are never called.',
      'जाँचने के लिए Google Ads में "Send test data" दबाएँ। टेस्ट पूछताछ पर कभी कॉल नहीं होता।',
      'যাচাই করতে Google Ads-এ "Send test data" চাপুন। টেস্ট খোঁজে কখনো কল হয় না।',
    ),
  ];

  List<String> get indiaMartSteps => [
    pick(
      'On seller.indiamart.com open Lead Manager → ⋮ → Import/Export Leads → Pull API, and tap "Generate Key".',
      'seller.indiamart.com पर Lead Manager → ⋮ → Import/Export Leads → Pull API खोलें और "Generate Key" दबाएँ।',
      'seller.indiamart.com-এ Lead Manager → ⋮ → Import/Export Leads → Pull API খুলে "Generate Key" চাপুন।',
    ),
    pick(
      'Paste the key here and tap Connect. We check IndiaMART for new enquiries every few minutes.',
      'की यहाँ पेस्ट करके "जोड़ें" दबाएँ। हम हर कुछ मिनट में IndiaMART पर नई पूछताछ देखते हैं।',
      'কী এখানে পেস্ট করে "যুক্ত করুন" চাপুন। আমরা কয়েক মিনিট পরপর IndiaMART-এ নতুন খোঁজ দেখি।',
    ),
    pick(
      'Optional, to get enquiries instantly: paste the push link into IndiaMART\'s "Push API" page (choose "Other").',
      'वैकल्पिक, पूछताछ तुरंत पाने के लिए: push लिंक को IndiaMART के "Push API" पेज में पेस्ट करें ("Other" चुनें)।',
      'ঐচ্ছিক, সঙ্গে সঙ্গে খোঁজ পেতে: push লিংক IndiaMART-এর "Push API" পেজে পেস্ট করুন ("Other" বেছে নিন)।',
    ),
  ];

  List<String> get metaSteps => [
    pick(
      'Ask your developer to create a Meta app with Webhooks, linked to your Facebook Page.',
      'अपने डेवलपर से Webhooks वाला एक Meta ऐप बनवाएँ, जो आपके Facebook पेज से जुड़ा हो।',
      'আপনার ডেভেলপারকে দিয়ে Webhooks-সহ একটি Meta অ্যাপ বানান, যা আপনার Facebook পেজের সঙ্গে যুক্ত।',
    ),
    pick(
      'Paste the App Secret and a Page access token with "leads_retrieval" permission, then tap Connect.',
      '"leads_retrieval" अनुमति वाला Page access token और App Secret पेस्ट करके "जोड़ें" दबाएँ।',
      '"leads_retrieval" অনুমতিসহ Page access token আর App Secret পেস্ট করে "যুক্ত করুন" চাপুন।',
    ),
    pick(
      'In the app\'s Webhooks settings choose "Page", paste the callback URL and verify token, and subscribe to "leadgen".',
      'ऐप की Webhooks सेटिंग में "Page" चुनें, callback URL और verify token पेस्ट करें और "leadgen" सब्सक्राइब करें।',
      'অ্যাপের Webhooks সেটিংসে "Page" বেছে callback URL আর verify token পেস্ট করুন, তারপর "leadgen" সাবস্ক্রাইব করুন।',
    ),
  ];

  String get crmKeyLabel =>
      pick('IndiaMART password', 'IndiaMART पासवर्ड', 'IndiaMART পাসওয়ার্ড');
  String get appSecretLabel => 'App Secret';
  String get pageTokenLabel => 'Page access token';
  String get crmKeyMissing => pick(
    'Paste the full IndiaMART key.',
    'पूरी IndiaMART की पेस्ट करें।',
    'পুরো IndiaMART কী পেস্ট করুন।',
  );
  String get metaSecretsInvalid => pick(
    'Paste the App Secret (letters and numbers only) and the full page access token.',
    'App Secret (सिर्फ़ अक्षर और अंक) और पूरा page access token पेस्ट करें।',
    'App Secret (শুধু অক্ষর আর সংখ্যা) আর পুরো page access token পেস্ট করুন।',
  );
  String get integrationShownOnce => pick(
    'Copy these now. For your safety the password is shown only once.',
    'इन्हें अभी कॉपी करें। सुरक्षा के लिए पासवर्ड सिर्फ़ एक बार दिखेगा।',
    'এগুলো এখনই কপি করুন। নিরাপত্তার জন্য পাসওয়ার্ড একবারই দেখানো হবে।',
  );
  String get secretsStoredSafely => pick(
    'Your passwords are kept safely locked and never shown again.',
    'आपके पासवर्ड सुरक्षित रखे जाते हैं और दोबारा नहीं दिखते।',
    'আপনার পাসওয়ার্ড নিরাপদে রাখা হয়, আর কখনো দেখানো হয় না।',
  );
  String get googleKeyLabel => pick('Password', 'पासवर्ड', 'পাসওয়ার্ড');
  String get callbackUrlLabel => 'Callback URL';
  String get verifyTokenLabel => 'Verify token';
  String get pushUrlLabel => pick(
    'Push link (optional)',
    'Push लिंक (वैकल्पिक)',
    'Push লিংক (ঐচ্ছিক)',
  );
  String lastChecked(String when) => pick(
    'Last checked $when',
    'आख़िरी बार देखा: $when',
    'শেষ দেখা হয়েছে: $when',
  );

  /// Why an integration is not bringing leads in (lead source `last_error`).
  String sourceProblem(String code) => switch (code) {
    'invalid_key' => pick(
      'Your IndiaMART key stopped working. Generate a new key and connect again.',
      'आपकी IndiaMART की काम नहीं कर रही। नई की बनाकर फिर से जोड़ें।',
      'আপনার IndiaMART কী কাজ করছে না। নতুন কী বানিয়ে আবার যুক্ত করুন।',
    ),
    'meta_token_invalid' => pick(
      'Facebook stopped sending enquiries. Connect again with a new page access token.',
      'Facebook ने पूछताछ भेजना बंद कर दिया। नए page access token से फिर से जोड़ें।',
      'Facebook খোঁজ পাঠানো বন্ধ করেছে। নতুন page access token দিয়ে আবার যুক্ত করুন।',
    ),
    'rate_limited' => pick(
      'IndiaMART asked us to slow down. We will try again in a few minutes.',
      'IndiaMART ने रुकने को कहा। हम कुछ मिनट में फिर कोशिश करेंगे।',
      'IndiaMART একটু থামতে বলেছে। কয়েক মিনিট পরে আবার চেষ্টা করব।',
    ),
    'config_unreadable' => pick(
      'We could not read your saved keys. Please connect again.',
      'आपकी सेव की गई की पढ़ी नहीं जा सकीं। कृपया फिर से जोड़ें।',
      'আপনার সেভ করা কী পড়া যায়নি। দয়া করে আবার যুক্ত করুন।',
    ),
    _ => pick(
      'There was a connection problem. We will keep trying.',
      'कनेक्शन में दिक्कत आई। हम कोशिश करते रहेंगे।',
      'সংযোগে সমস্যা হয়েছে। আমরা চেষ্টা চালিয়ে যাব।',
    ),
  };

  String get simulateIndiaMartEnquiry => pick(
    'Simulate IndiaMART enquiry → auto call',
    'IndiaMART पूछताछ → ऑटो कॉल (डेमो)',
    'IndiaMART খোঁজ → অটো কল (ডেমো)',
  );
}
