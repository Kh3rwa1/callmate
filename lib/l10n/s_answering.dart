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
}
