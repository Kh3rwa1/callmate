import 's.dart';

/// Onboarding: Welcome → type → skills → details → offer → teach → meet →
/// first call.
///
/// Hindi copy avoids verbs that would give the AI employee (or the owner) a
/// gender: passive voice, noun phrases and subjunctive forms instead.
extension SOnboarding on S {
  // ------------------------------------------------------------ Welcome
  String get obWelcomeTitle => pick(
    'Let\'s set up your AI employee',
    'चलिए, आपका AI कर्मचारी तैयार करें',
    'চলুন, আপনার AI কর্মী তৈরি করি',
  );
  String get obWelcomeSub => pick(
    '6 quick steps, about 2 minutes. You can change anything later.',
    '6 छोटे स्टेप, करीब 2 मिनट। बाद में कुछ भी बदल सकते हैं।',
    '6টি ছোট ধাপ, প্রায় 2 মিনিট। পরে যেকোনো কিছু বদলাতে পারবেন।',
  );
  String get obHowItWorks =>
      pick('How it works', 'यह कैसे काम करता है', 'কীভাবে কাজ করে');

  /// The core loop, one (short label, sentence) per step.
  List<(String, String)> get obLoop => [
    (
      pick('Calls', 'कॉल', 'কল'),
      pick(
        'Calls every new customer within minutes',
        'हर नए ग्राहक को मिनटों में कॉल',
        'প্রতিটি নতুন গ্রাহকে কয়েক মিনিটে কল',
      ),
    ),
    (
      pick('Listens', 'समझ', 'বোঝে'),
      pick(
        'Understands what each customer wants',
        'समझे कि हर ग्राहक क्या चाहता है',
        'বোঝে প্রত্যেক গ্রাহক কী চায়',
      ),
    ),
    (
      pick('Scores', 'स्कोर', 'স্কোর'),
      pick(
        'Tells you who is ready to buy',
        'बताए कि कौन खरीदने को तैयार है',
        'জানায় কে কিনতে তৈরি',
      ),
    ),
    (
      pick('Drafts', 'मैसेज', 'মেসেজ'),
      pick(
        'Drafts a WhatsApp message for you',
        'आपके लिए WhatsApp मैसेज लिखकर रखे',
        'আপনার জন্য WhatsApp মেসেজ লিখে রাখে',
      ),
    ),
    (
      pick('You close', 'आपकी डील', 'আপনার ডিল'),
      pick(
        'You review it, tap Send and close the deal',
        'आप देखें, Send दबाएँ और डील पक्की करें',
        'আপনি দেখে Send চাপুন, ডিল পাকা করুন',
      ),
    ),
  ];

  // ----------------------------------------------------------- Scaffold
  String obStepOf(int step, int total) => pick(
    'Step $step of $total',
    'स्टेप $step / $total',
    'ধাপ $step / $total',
  );

  // ------------------------------------------------------ Business type
  String get obTypeTitle =>
      pick('Type of business', 'कारोबार का प्रकार', 'ব্যবসার ধরন');
  String get obTypeSub => pick(
    'Calls, questions and messages are tailored to it.',
    'कॉल, सवाल और मैसेज इसी के हिसाब से बनेंगे।',
    'কল, প্রশ্ন আর মেসেজ এই অনুযায়ী সাজানো হবে।',
  );

  // ------------------------------------------------------------- Skills
  String get obSkillsTitle =>
      pick('What should it do?', 'इसे क्या-क्या करना है?', 'এটি কী কী করবে?');
  String get obSkillsSub => pick(
    'Pick all that apply.',
    'जो भी लागू हों, सब चुनें।',
    'যা যা লাগে, সব বেছে নিন।',
  );

  /// "We'll set up a Sales Assistant for you." [role] is already
  /// translated for display.
  String obWeWillSetUp(String role) {
    final article = role.isNotEmpty && 'AEIOU'.contains(role[0]) ? 'an' : 'a';
    return pick(
      'We\'ll set up $article $role for you.',
      'आपके लिए $role सेट किया जाएगा।',
      'আপনার জন্য $role সেট করা হবে।',
    );
  }

  // ------------------------------------------------------------ Details
  String get obDetailsTitle =>
      pick('Your business', 'आपका कारोबार', 'আপনার ব্যবসা');
  String get obDetailsSub => pick(
    'Used on every call and WhatsApp message.',
    'हर कॉल और WhatsApp मैसेज में यही इस्तेमाल होगा।',
    'প্রতিটি কল আর WhatsApp মেসেজে এটাই ব্যবহার হবে।',
  );
  String get obBizNameHint =>
      pick('e.g. Smile Dental', 'जैसे Smile Dental', 'যেমন Smile Dental');
  String get obBizNameRequired => pick(
    'Please enter your business name',
    'अपने कारोबार का नाम डालें',
    'আপনার ব্যবসার নাম দিন',
  );
  String get obAddress => pick('Address', 'पता', 'ঠিকানা');
  String get obAddressHint => pick(
    'e.g. 12 Park Street, Kolkata',
    'जैसे 12 Park Street, Kolkata',
    'যেমন 12 Park Street, Kolkata',
  );

  // -------------------------------------------------------------- Offer
  String get obOfferTitle =>
      pick('What you offer', 'आपकी सेवाएँ और ऑफ़र', 'আপনি কী অফার করেন');
  String get obOfferSub => pick(
    'Customer questions are answered from these details.',
    'ग्राहकों के सवालों के जवाब इन्हीं से दिए जाएँगे।',
    'গ্রাহকের প্রশ্নের উত্তর এই তথ্য থেকেই দেওয়া হবে।',
  );

  /// "Add at least one course". [noun] is already translated.
  String obAddAtLeastOne(String noun) => pick(
    'Add at least one ${noun.toLowerCase()}',
    'कम से कम एक $noun लिखें',
    'অন্তত একটি $noun লিখুন',
  );
  String get obPricing => pick('Pricing', 'कीमत', 'দাম');
  String get obPricingHint =>
      pick('e.g. From ₹999', 'जैसे ₹999 से शुरू', 'যেমন ₹999 থেকে শুরু');
  String get obHours => pick('Opening hours', 'खुलने का समय', 'খোলার সময়');
  String get obHoursHint =>
      pick('e.g. Mon–Sat, 9–8', 'जैसे सोम–शनि, 9–8', 'যেমন সোম–শনি, 9–8');
  String get obLocation => pick('Location', 'लोकेशन', 'লোকেশন');
  String get obLocationHint => pick(
    'e.g. Park Street, Kolkata',
    'जैसे Park Street, Kolkata',
    'যেমন Park Street, Kolkata',
  );

  /// "Counsellor number". [label] is already translated.
  String obHumanNumber(String label) =>
      pick('$label number', '$label का नंबर', '$label-এর নম্বর');
  String get obHumanNumberHint => pick(
    'Who talks to ready-to-buy customers',
    'जो खरीदने को तैयार ग्राहक की डील पक्की करे',
    'যিনি কিনতে তৈরি গ্রাহকের ডিল পাকা করেন',
  );
  String get obRequired => pick('Required', 'ज़रूरी है', 'দরকারি');

  // -------------------------------------------------------------- Teach
  String get obTeachSub => pick(
    'Add what a new employee would read on day one. You can add more later.',
    'वो सब जोड़ें जो नया कर्मचारी पहले दिन पढ़े। बाद में और जोड़ सकते हैं।',
    'নতুন কর্মী প্রথম দিনে যা পড়ে, সেসব যোগ করুন। পরে আরও যোগ করা যাবে।',
  );
  String get obAdded => pick('Added', 'जोड़ा गया', 'যোগ করা হয়েছে');
  String get obSkipForNow => pick('Skip for now', 'अभी छोड़ें', 'এখন বাদ দিন');
  String get obCsvLater => pick(
    'You can add customers from your phone contacts right after setup.',
    'सेटअप के ठीक बाद फ़ोन कॉन्टैक्ट्स से ग्राहक जोड़ सकते हैं।',
    'সেটআপের ঠিক পরেই ফোনের কন্টাক্ট থেকে গ্রাহক যোগ করতে পারবেন।',
  );

  // ------------------------------------------------------------- Create
  List<String> get obLearning => [
    pick(
      'Reading your business details',
      'कारोबार की जानकारी पढ़ी जा रही है',
      'ব্যবসার তথ্য পড়া হচ্ছে',
    ),
    pick(
      'Learning what you offer',
      'आपकी सेवाएँ समझी जा रही हैं',
      'আপনার পরিষেবা শেখা হচ্ছে',
    ),
    pick(
      'Practising customer calls',
      'ग्राहक कॉल की प्रैक्टिस हो रही है',
      'গ্রাহকের কলের অনুশীলন হচ্ছে',
    ),
  ];
  String get obAlmostReady =>
      pick('Almost ready…', 'बस तैयार…', 'প্রায় তৈরি…');
  String get obAllSet => pick('All set!', 'सब तैयार!', 'সব তৈরি!');
  String get obSignInRequired =>
      pick('Sign in required', 'साइन इन ज़रूरी है', 'সাইন ইন দরকার');
  String get obSetupFailed => pick(
    'We couldn\'t set up your AI employee',
    'AI कर्मचारी सेट नहीं हो पाया',
    'AI কর্মী সেট করা গেল না',
  );
  String get obSignInToConnect => pick(
    'Sign in to connect your AI employee.',
    'AI कर्मचारी जोड़ने के लिए साइन इन करें।',
    'AI কর্মী যুক্ত করতে সাইন ইন করুন।',
  );
  String get obMeet => pick(
    'Meet your AI employee',
    'मिलिए अपने AI कर्मचारी से',
    'আপনার AI কর্মীর সঙ্গে পরিচয় করুন',
  );
  String get obNameYourEmployee =>
      pick('Name your employee', 'कर्मचारी का नाम रखें', 'কর্মীর নাম দিন');
  String get obSpeaks => pick('Speaks', 'भाषाएँ', 'ভাষা');
  String get obVoice => pick('Voice', 'आवाज़', 'কণ্ঠ');
  String get obVoiceFemale =>
      pick("Woman's voice", 'महिला की आवाज़', 'মহিলার কণ্ঠ');
  String get obVoiceMale =>
      pick("Man's voice", 'पुरुष की आवाज़', 'পুরুষের কণ্ঠ');
  String get obActivate =>
      pick('Activate Employee', 'कर्मचारी चालू करें', 'কর্মী চালু করুন');

  // --------------------------------------------------------- First call
  String get obFirstCallTitle =>
      pick('Your first call', 'आपकी पहली कॉल', 'আপনার প্রথম কল');
  String obFirstCallSub(String name) => pick(
    'Play this customer and talk to $name – a practice call, right here in the app.',
    'यह ग्राहक बनकर $name से बात करें – ऐप में ही प्रैक्टिस कॉल।',
    'এই গ্রাহক সেজে $name-এর সঙ্গে কথা বলুন – অ্যাপেই প্র্যাকটিস কল।',
  );
  String get obYouPlay =>
      pick('You play this customer', 'आप यह ग्राहक हैं', 'আপনি এই গ্রাহক');
  String get obGoToDashboard =>
      pick('Go to dashboard', 'डैशबोर्ड पर जाएँ', 'ড্যাশবোর্ডে যান');
  String obTalkAgainTo(String name) => pick(
    'Talk to $name again',
    '$name से फिर बात करें',
    '$name-এর সঙ্গে আবার কথা বলুন',
  );
  String get obFreePractice => pick(
    'Free · never calls real customers',
    'मुफ़्त · असली ग्राहकों को कभी कॉल नहीं',
    'ফ্রি · আসল গ্রাহকে কখনও কল নয়',
  );
}
