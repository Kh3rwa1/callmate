import '../data/models/playbook.dart';
import 's.dart';

/// "Your call playbook" (Agent tab) and the onboarding confirmation.
extension SPlaybook on S {
  String get playbookTitle =>
      pick('Your call playbook', 'आपकी कॉल प्लेबुक', 'আপনার কল প্লেবুক');
  String get playbookIntro => pick(
    'What your AI employee asks on every call, when a customer counts as '
        'ready to buy, and the WhatsApp message it drafts after the call.',
    'हर कॉल पर आपका AI कर्मचारी क्या पूछता है, ग्राहक कब ख़रीदने को तैयार '
        'माना जाता है, और कॉल के बाद वह कौन-सा WhatsApp मैसेज तैयार करता है।',
    'প্রতিটি কলে আপনার AI কর্মী কী জিজ্ঞেস করে, কখন একজন গ্রাহককে কিনতে '
        'তৈরি ধরা হয়, আর কলের পরে সে কোন WhatsApp মেসেজ তৈরি করে।',
  );
  String playbookOf(String name) =>
      pick('$name playbook', '$name प्लेबुक', '$name প্লেবুক');
  String get playbookQuestions => pick(
    'Questions your AI asks',
    'आपका AI ये सवाल पूछता है',
    'আপনার AI যে প্রশ্নগুলো করে',
  );
  String get playbookReadyToBuy =>
      pick('Ready to buy means', 'ख़रीदने को तैयार का मतलब', 'কিনতে তৈরি মানে');
  String playbookReadyScore(int n) => pick(
    'Such customers are marked hot, with a score of $n or more.',
    'ऐसे ग्राहक $n या उससे ज़्यादा स्कोर के साथ हॉट माने जाते हैं।',
    'এমন গ্রাহকদের $n বা তার বেশি স্কোরে হট ধরা হয়।',
  );
  String get playbookObjections => pick(
    'When customers hesitate',
    'जब ग्राहक हिचकिचाएँ',
    'গ্রাহক দ্বিধায় থাকলে',
  );
  String get playbookFollowups =>
      pick('WhatsApp follow-ups', 'WhatsApp फ़ॉलो-अप', 'WhatsApp ফলো-আপ');
  String get playbookFollowupsNote => pick(
    'Drafted after a call when the AI has no message of its own. You review '
        'and send every message yourself.',
    'जब AI का अपना कोई मैसेज न हो, तब कॉल के बाद यह ड्राफ़्ट बनता है। हर '
        'मैसेज आप ख़ुद देखकर भेजते हैं।',
    'AI-এর নিজের কোনো মেসেজ না থাকলে কলের পরে এটি খসড়া হিসেবে তৈরি হয়। '
        'প্রতিটি মেসেজ আপনি নিজে দেখে পাঠান।',
  );
  String followupOutcome(FollowupOutcome o) => switch (o) {
    FollowupOutcome.hot => pick(
      'Ready to buy',
      'ख़रीदने को तैयार',
      'কিনতে তৈরি',
    ),
    FollowupOutcome.warm => pick('Interested', 'रुचि है', 'আগ্রহী'),
    FollowupOutcome.callback => pick(
      'Asked for a call back',
      'कॉल बैक माँगा',
      'কল ব্যাক চেয়েছেন',
    ),
    FollowupOutcome.notInterested => pick(
      'Not interested',
      'रुचि नहीं',
      'আগ্রহী নন',
    ),
  };
  String get playbookNamePlaceholder => pick('[Name]', '[नाम]', '[নাম]');
  String get playbookCallbackTiming => pick(
    'Best time to call back',
    'कॉल बैक का सबसे अच्छा समय',
    'কল ব্যাকের সেরা সময়',
  );
  String get playbookCustomise => pick(
    'Ask us to customise',
    'हमसे बदलाव करवाएँ',
    'আমাদের দিয়ে কাস্টমাইজ করান',
  );
  String get playbookCustomiseHint => pick(
    'Want different questions or messages? Write to us and we will tailor '
        'the playbook for your business.',
    'अलग सवाल या मैसेज चाहिए? हमें लिखें, हम आपके व्यवसाय के लिए प्लेबुक बदल '
        'देंगे।',
    'অন্য প্রশ্ন বা মেসেজ চান? আমাদের লিখুন, আমরা আপনার ব্যবসার জন্য '
        'প্লেবুক সাজিয়ে দেব।',
  );
  String playbookCustomiseSubject(String name) => pick(
    'Customise my call playbook ($name)',
    'मेरी कॉल प्लेबुक बदलें ($name)',
    'আমার কল প্লেবুক কাস্টমাইজ করুন ($name)',
  );
  String playbookMailFailed(String email) => pick(
    'Couldn’t open your email app. Write to $email.',
    'ईमेल ऐप नहीं खुला। $email पर लिखें।',
    'ইমেল অ্যাপ খোলা গেল না। $email-এ লিখুন।',
  );

  /// Onboarding: shown once a business type is picked.
  String obPlaybookReady(String name) => pick(
    'We set up the $name playbook for you',
    'हमने आपके लिए $name प्लेबुक तैयार कर दी है',
    'আমরা আপনার জন্য $name প্লেবুক তৈরি করে দিয়েছি',
  );

  String playbookName(PlaybookVertical v) => switch (v) {
    PlaybookVertical.education => pick(
      'Coaching & education',
      'कोचिंग और शिक्षा',
      'কোচিং ও শিক্ষা',
    ),
    PlaybookVertical.healthcare => pick(
      'Clinic & healthcare',
      'क्लिनिक और स्वास्थ्य',
      'ক্লিনিক ও স্বাস্থ্য',
    ),
    PlaybookVertical.realEstate => pick(
      'Real estate',
      'रियल एस्टेट',
      'রিয়েল এস্টেট',
    ),
    PlaybookVertical.salon => pick(
      'Salon & spa',
      'सैलून और स्पा',
      'সেলুন ও স্পা',
    ),
    PlaybookVertical.fitness => pick(
      'Gym & fitness',
      'जिम और फ़िटनेस',
      'জিম ও ফিটনেস',
    ),
    PlaybookVertical.general => pick('General', 'सामान्य', 'সাধারণ'),
  };
}
