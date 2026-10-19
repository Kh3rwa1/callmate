import 's.dart';

/// "Answer my missed calls" (Agent tab): the AI picks up calls the owner
/// can't, on a number their phone forwards to.
extension SAnswering on S {
  String get answeringTitle => pick(
    'Answer my missed calls',
    'मेरी छूटी कॉल का जवाब',
    'আমার মিস করা কলের উত্তর',
  );
  String answeringIntro(String agent) => pick(
    'When you can\'t pick up, $agent answers the call in Hindi, Bengali or English, finds out what they need, and sends you the summary.',
    'जब आप फ़ोन नहीं उठा पाते, तब कॉल का जवाब $agent से मिलेगा: हिंदी, बांग्ला या अंग्रेज़ी में। ग्राहक को क्या चाहिए, इसका सारांश आपको भेजा जाएगा।',
    'আপনি ফোন ধরতে না পারলে $agent কলের উত্তর দেবে, হিন্দি, বাংলা বা ইংরেজিতে। কী দরকার জেনে নিয়ে আপনাকে সারাংশ পাঠাবে।',
  );
  String answeringSwitch(String agent) => pick(
    '$agent answers my missed calls',
    'मेरी छूटी कॉल पर $agent जवाब दे',
    'মিস করা কলে $agent উত্তর দেবে',
  );
  String get answeringUnavailable => pick(
    'Not available yet. We\'ll tell you when it\'s ready.',
    'अभी उपलब्ध नहीं। तैयार होते ही बताएँगे।',
    'এখনও চালু হয়নি। তৈরি হলে জানাব।',
  );
  String answeringForwardTitle(String agent) => pick(
    'Send missed calls to $agent',
    'छूटी कॉल $agent को भेजें',
    'মিস করা কল $agent-কে পাঠান',
  );
  String get answeringLine =>
      pick('Your AI line', 'आपकी AI लाइन', 'আপনার AI লাইন');
  String get answeringForwardHint => pick(
    'Tap one: your phone app opens with a code. Tap call to turn it on.',
    'एक चुनें: फ़ोन ऐप में कोड खुलेगा। चालू करने के लिए कॉल दबाएँ।',
    'একটি বাছুন: ফোন অ্যাপে কোড খুলবে। চালু করতে কল চাপুন।',
  );
  String get forwardNoAnswer => pick(
    'When I don\'t pick up',
    'जब मैं फ़ोन न उठाऊँ',
    'যখন আমি ফোন ধরি না',
  );
  String get forwardBusy => pick(
    'When I\'m on another call',
    'जब मैं दूसरी कॉल पर हूँ',
    'যখন আমি অন্য কলে থাকি',
  );
  String get forwardUnreachable => pick(
    'When my phone is off or has no network',
    'जब फ़ोन बंद हो या नेटवर्क न हो',
    'যখন ফোন বন্ধ বা নেটওয়ার্ক নেই',
  );
  String get forwardStop =>
      pick('Stop sending calls', 'कॉल भेजना बंद करें', 'কল পাঠানো বন্ধ করুন');
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
  String get answeringOn => pick('On', 'चालू', 'চালু');

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
  String get leadSourceCalledYou =>
      pick('Called you', 'आपको कॉल किया', 'আপনাকে কল করেছেন');
}
