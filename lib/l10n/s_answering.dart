import '../core/utils/call_forwarding.dart';
import '../data/models/models.dart';
import 's.dart';

/// "Who answers my calls" (Agent tab → Settings): the AI employee answers
/// every call, the ones the owner misses, or none.
extension SAnswering on S {
  String get answeringTitle =>
      pick('Who answers my calls', 'मेरी कॉल कौन उठाए', 'আমার কল কে ধরবে');
  String answeringIntro(String agent) => pick(
    'Choose who picks up when customers call your number. $agent answers in Hindi, Bengali or English, finds out what they need, and sends you the summary.',
    'चुनें कि ग्राहकों की कॉल कौन उठाए। $agent से हिंदी, बांग्ला या अंग्रेज़ी में बात होगी, ग्राहक को क्या चाहिए यह पता किया जाएगा, और सारांश आपको भेजा जाएगा।',
    'গ্রাহকরা আপনার নম্বরে ফোন করলে কে ধরবে বেছে নিন। $agent হিন্দি, বাংলা বা ইংরেজিতে কথা বলে জেনে নেবে কী দরকার, আর আপনাকে সারাংশ পাঠাবে।',
  );
  String get whoAnswers => pick('Who answers', 'कौन उठाए', 'কে ধরবে');
  String modeAi(String agent) => pick(
    '$agent answers every call',
    'हर कॉल $agent उठाए',
    'সব কল $agent ধরবে',
  );
  String get modeAiSub => pick(
    'Your phone sends every call to your AI line. You can still call customers yourself.',
    'आपका फ़ोन हर कॉल AI लाइन पर भेजेगा। आप ख़ुद ग्राहकों को कॉल कर सकते हैं।',
    'আপনার ফোন সব কল AI লাইনে পাঠাবে। আপনি নিজে গ্রাহকদের ফোন করতে পারবেন।',
  );
  String modeMissed(String agent) => pick(
    'I answer first, $agent takes the ones I miss',
    'पहले मैं उठाऊँ, छूटी कॉल $agent उठाए',
    'আগে আমি ধরব, মিস হলে $agent ধরবে',
  );
  String get modeMissedSub => pick(
    'When you don\'t pick up, are on another call, or your phone is off.',
    'जब आप न उठाएँ, दूसरी कॉल पर हों, या फ़ोन बंद हो।',
    'যখন আপনি ধরেন না, অন্য কলে থাকেন, বা ফোন বন্ধ থাকে।',
  );
  String get modeOwner => pick('Only me', 'सिर्फ़ मैं', 'শুধু আমি');
  String modeOwnerSub(String agent) => pick(
    '$agent doesn\'t answer calls.',
    'कॉल $agent तक नहीं जाएगी।',
    '$agent কল ধরবে না।',
  );

  /// Short value for the Agent tab row.
  String answerModeShort(AnswerMode m) => switch (m) {
    AnswerMode.ai => pick('AI answers', 'AI उठाए', 'AI ধরবে'),
    AnswerMode.missed => pick('Me first', 'पहले मैं', 'আগে আমি'),
    AnswerMode.owner => pick('Only me', 'सिर्फ़ मैं', 'শুধু আমি'),
  };

  String get answeringUnavailable => pick(
    'Not available yet. We\'ll tell you when it\'s ready.',
    'अभी उपलब्ध नहीं। तैयार होते ही बताएँगे।',
    'এখনও চালু হয়নি। তৈরি হলে জানাব।',
  );
  String get applyOnPhone => pick(
    'Set it up on your phone',
    'अपने फ़ोन पर चालू करें',
    'আপনার ফোনে চালু করুন',
  );
  String get answeringLine =>
      pick('Your AI line', 'आपकी AI लाइन', 'আপনার AI লাইন');
  String get whichNetwork => pick(
    'Which network is your SIM on?',
    'आपकी SIM किस नेटवर्क की है?',
    'আপনার SIM কোন নেটওয়ার্কের?',
  );
  String get networkOthers =>
      pick('Airtel, Vi, BSNL', 'Airtel, Vi, BSNL', 'Airtel, Vi, BSNL');
  String get answeringForwardHint => pick(
    'Tap each step: your phone app opens with a code. Press call, wait for the "successful" message, then come back.',
    'हर स्टेप दबाएँ: फ़ोन ऐप में कोड खुलेगा। कॉल दबाएँ, "सफल" मैसेज आने दें, फिर वापस आएँ।',
    'প্রতিটি ধাপে চাপুন: ফোন অ্যাপে কোড খুলবে। কল চাপুন, "সফল" মেসেজ আসা পর্যন্ত অপেক্ষা করে ফিরে আসুন।',
  );
  String forwardingStep(ForwardingStepKind k, String agent) => switch (k) {
    ForwardingStepKind.clear => pick(
      'Clear old call forwarding',
      'पुरानी कॉल फ़ॉरवर्डिंग हटाएँ',
      'পুরোনো কল ফরওয়ার্ডিং সরান',
    ),
    ForwardingStepKind.all => pick(
      'Send every call to $agent',
      'हर कॉल $agent को भेजें',
      'সব কল $agent-কে পাঠান',
    ),
    ForwardingStepKind.noAnswer => pick(
      'When I don\'t pick up',
      'जब मैं फ़ोन न उठाऊँ',
      'যখন আমি ফোন ধরি না',
    ),
    ForwardingStepKind.busy => pick(
      'When I\'m on another call',
      'जब मैं दूसरी कॉल पर हूँ',
      'যখন আমি অন্য কলে থাকি',
    ),
    ForwardingStepKind.unreachable => pick(
      'When my phone is off or has no network',
      'जब फ़ोन बंद हो या नेटवर्क न हो',
      'যখন ফোন বন্ধ বা নেটওয়ার্ক নেই',
    ),
  };
  String get answeringChargesNote => pick(
    'Your operator may count forwarded calls as outgoing calls; most unlimited plans include them. Answered calls use your calling minutes.',
    'आपका ऑपरेटर फ़ॉरवर्ड की गई कॉल को आउटगोइंग कॉल गिन सकता है; ज़्यादातर अनलिमिटेड प्लान में ये शामिल हैं। जवाब दी गई कॉल आपके कॉल मिनट से कटती है।',
    'আপনার অপারেটর ফরওয়ার্ড করা কলকে আউটগোয়িং কল ধরতে পারে; বেশিরভাগ আনলিমিটেড প্ল্যানে এটা থাকে। উত্তর দেওয়া কলে আপনার কলের মিনিট খরচ হয়।',
  );
  String dialYourself(String code) => pick(
    'Couldn\'t open your phone app. Dial $code yourself.',
    'फ़ोन ऐप नहीं खुला। $code ख़ुद डायल करें।',
    'ফোন অ্যাপ খোলেনি। নিজে $code ডায়াল করুন।',
  );
  String get answeringNoNumbers => pick(
    'No answering numbers are free right now. Try again later.',
    'अभी कोई जवाब नंबर खाली नहीं है। बाद में कोशिश करें।',
    'এখন কোনো উত্তর দেওয়ার নম্বর খালি নেই। পরে চেষ্টা করুন।',
  );

  /// A call the customer made that the AI answered.
  String calledYouFor(String duration) => pick(
    'Called you · $duration',
    'आपको कॉल किया · $duration',
    'আপনাকে কল করেছেন · $duration',
  );
  String get calledYouAiAnswered => pick(
    'They called, your AI answered',
    'उन्होंने कॉल किया, AI ने जवाब दिया',
    'ওঁরা কল করেছেন, AI উত্তর দিয়েছে',
  );

  // ------------------------------------------------------ business number
  String get businessNumberTitle =>
      pick('Your business number', 'आपका बिज़नेस नंबर', 'আপনার ব্যবসার নম্বর');
  String get yourBusinessNumber => businessNumberTitle;
  String get numberWhyTitle => pick(
    'One number for your business',
    'आपके बिज़नेस का एक नंबर',
    'আপনার ব্যবসার একটি নম্বর',
  );
  String numberWhySame(String agent) => pick(
    'Customers see the same number every time $agent calls. No more calls from random numbers.',
    'जब भी $agent कॉल करे, ग्राहकों को हर बार वही नंबर दिखेगा। अलग-अलग नंबरों से कॉल नहीं।',
    '$agent যখনই ফোন করবে, গ্রাহকরা একই নম্বর দেখবেন। আর আলাদা আলাদা নম্বর থেকে কল নয়।',
  );
  String numberWhyCallBack(String agent) => pick(
    'When customers call it back, $agent answers and you get the summary.',
    'ग्राहक इस नंबर पर वापस कॉल करें तो जवाब $agent से मिलेगा और सारांश आपको।',
    'গ্রাহক এই নম্বরে ফোন করলে $agent উত্তর দেবে, আর সারাংশ আপনি পাবেন।',
  );
  String get numberWhyYours => pick(
    'It stays yours as long as you are on Growth. Print it on your boards and ads.',
    'जब तक आप Growth पर हैं, यह नंबर आपका रहेगा। इसे बोर्ड और विज्ञापनों पर छापें।',
    'যতদিন Growth-এ থাকবেন, নম্বরটি আপনারই। বোর্ড আর বিজ্ঞাপনে ছাপুন।',
  );
  String get numberGetWithGrowth => pick(
    'Get your number with Growth',
    'Growth के साथ अपना नंबर पाएँ',
    'Growth-এর সঙ্গে আপনার নম্বর নিন',
  );
  String get numberIncludedInGrowth => pick(
    'Included in the Growth plan at no extra cost.',
    'Growth प्लान में बिना अतिरिक्त ख़र्च के शामिल।',
    'Growth প্ল্যানে কোনো বাড়তি খরচ ছাড়াই।',
  );
  String get pickYourNumber =>
      pick('Pick your number', 'अपना नंबर चुनें', 'আপনার নম্বর বাছুন');
  String get rentThisNumber => pick(
    'Make this my business number',
    'इसे मेरा बिज़नेस नंबर बनाएँ',
    'এটাকে আমার ব্যবসার নম্বর করুন',
  );
  String numberChosenOnce(int days) => pick(
    'You choose it once and it doesn\'t change. If your plan lapses, we keep it for you for $days days.',
    'यह नंबर एक बार चुना जाता है और बदलता नहीं। प्लान रुक जाए तो $days दिन तक आपके लिए रखा जाता है।',
    'নম্বরটি একবারই বাছা হয়, বদলায় না। প্ল্যান বন্ধ হলে $days দিন আপনার জন্য রাখা থাকে।',
  );
  String rentNumberConfirmTitle(String n) => pick(
    'Make $n your business number?',
    '$n को अपना बिज़नेस नंबर बनाएँ?',
    '$n আপনার ব্যবসার নম্বর করবেন?',
  );
  String rentNumberConfirmBody(String agent) => pick(
    '$agent will call customers from this number and answer it. You can\'t switch to another number later.',
    'ग्राहकों को AI कॉल इसी नंबर से जाएँगी और इसी पर जवाब मिलेगा। बाद में दूसरा नंबर नहीं लिया जा सकता।',
    '$agent এই নম্বর থেকে গ্রাহকদের ফোন করবে আর এতেই উত্তর দেবে। পরে অন্য নম্বরে বদলানো যাবে না।',
  );
  String get rentNumberYes =>
      pick('Yes, make it mine', 'हाँ, मेरा बनाएँ', 'হ্যাঁ, আমার করুন');
  String get numberTaken => pick(
    'That number was just taken. Pick another one.',
    'यह नंबर अभी किसी ने ले लिया। दूसरा चुनें।',
    'এই নম্বরটা এইমাত্র নেওয়া হয়ে গেছে। অন্যটা বাছুন।',
  );
  String get numberNeedsGrowth => pick(
    'A business number comes with the Growth plan.',
    'बिज़नेस नंबर Growth प्लान के साथ मिलता है।',
    'ব্যবসার নম্বর Growth প্ল্যানের সঙ্গে পাওয়া যায়।',
  );
  String get numberActive => pick('Active', 'चालू', 'চালু');
  String get numberOnHold => pick('On hold', 'रुका हुआ', 'স্থগিত');
  String numberActiveNote(String agent) => pick(
    'Every AI call shows this number. Customers who call it reach $agent.',
    'हर AI कॉल पर यही नंबर दिखता है। इस पर कॉल करने वालों को जवाब $agent से मिलता है।',
    'প্রতিটি AI কলে এই নম্বর দেখা যায়। এতে ফোন করলে $agent উত্তর দেয়।',
  );
  String numberHeldUntil(String date) => pick(
    'Your plan lapsed. We keep this number for you until $date: renew Growth to keep it.',
    'आपका प्लान रुक गया है। यह नंबर $date तक आपके लिए रखा है: इसे रखने के लिए Growth रिन्यू करें।',
    'আপনার প্ল্যান বন্ধ হয়েছে। $date পর্যন্ত নম্বরটি আপনার জন্য রাখা আছে: রাখতে Growth রিনিউ করুন।',
  );
  String get numberHeldForwarding => pick(
    'While it\'s on hold the AI doesn\'t answer it. If your phone forwards calls to it, dial ##002# so they ring on your phone again.',
    'होल्ड के दौरान AI इस पर कॉल नहीं उठाता। अगर आपका फ़ोन कॉल इस नंबर पर भेजता है, तो ##002# डायल करें ताकि कॉल फिर आपके फ़ोन पर बजें।',
    'হোল্ডে থাকাকালীন AI এই নম্বরে কল ধরে না। আপনার ফোন কল এই নম্বরে পাঠালে ##002# ডায়াল করুন, যাতে কল আবার আপনার ফোনে বাজে।',
  );
  String get renewToKeepNumber => pick(
    'Renew Growth to keep your number',
    'नंबर रखने के लिए Growth रिन्यू करें',
    'নম্বর রাখতে Growth রিনিউ করুন',
  );
  String get copyNumber =>
      pick('Copy number', 'नंबर कॉपी करें', 'নম্বর কপি করুন');
  String shareNumberText(String n) =>
      pick('Call us at $n', 'हमें $n पर कॉल करें', 'আমাদের $n নম্বরে ফোন করুন');
  String get answeringNeedsNumber => pick(
    'Calls are forwarded to your business number. Get one first.',
    'कॉल आपके बिज़नेस नंबर पर फ़ॉरवर्ड होती हैं। पहले नंबर लें।',
    'কল আপনার ব্যবসার নম্বরে ফরওয়ার্ড হয়। আগে একটি নম্বর নিন।',
  );
  String get getBusinessNumber => pick(
    'Get your business number',
    'अपना बिज़नेस नंबर लें',
    'আপনার ব্যবসার নম্বর নিন',
  );

  /// Plan picker.
  String get planNumberIncluded => pick(
    'Your own business number',
    'आपका अपना बिज़नेस नंबर',
    'আপনার নিজের ব্যবসার নম্বর',
  );
  String get planSharedNumbers => pick(
    'Calls from shared CallPilot numbers',
    'साझा CallPilot नंबरों से कॉल',
    'শেয়ার করা CallPilot নম্বর থেকে কল',
  );
  String get premiumBadge => pick('Premium', 'प्रीमियम', 'প্রিমিয়াম');
}
