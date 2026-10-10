import 's.dart';

/// Follow-ups list, the follow-up detail and the WhatsApp handoff.
extension SFollowUps on S {
  String get followUpsTitle => pick('Follow-ups', 'फ़ॉलो-अप', 'ফলো-আপ');
  String nDraftedFromCalls(int n) => pick(
    '$n WhatsApp messages drafted from calls',
    'कॉल्स से $n WhatsApp मैसेज तैयार',
    'কল থেকে $n টি WhatsApp মেসেজ তৈরি',
  );
  String get readyToSend =>
      pick('Ready to send', 'भेजने के लिए तैयार', 'পাঠানোর জন্য তৈরি');
  String get whatsappOpened =>
      pick('WhatsApp opened', 'WhatsApp खुला', 'WhatsApp খোলা হয়েছে');
  String get newDraftsAppear => pick(
    'New drafts appear here after calls.',
    'कॉल के बाद नए ड्राफ़्ट यहाँ दिखेंगे।',
    'কলের পরে নতুন ড্রাফট এখানে দেখা যাবে।',
  );
  String get openInWhatsapp =>
      pick('Open in WhatsApp', 'WhatsApp में खोलें', 'WhatsApp-এ খুলুন');
  String get swipeToOpenHint => pick(
    'Swipe left to open in WhatsApp',
    'WhatsApp में खोलने के लिए बाईं ओर स्वाइप करें',
    'WhatsApp-এ খুলতে বাঁ দিকে সোয়াইপ করুন',
  );

  // ------------------------------------------------------------ Detail
  String get followUpReady =>
      pick('Follow-up ready', 'फ़ॉलो-अप तैयार', 'ফলো-আপ তৈরি');
  String get iSentIt => pick('I sent it', 'मैंने भेज दिया', 'আমি পাঠিয়েছি');
  String get dismiss => pick('Dismiss', 'हटाएँ', 'বাদ দিন');
  String get messageUpdated =>
      pick('Message updated', 'मैसेज अपडेट हुआ', 'মেসেজ আপডেট হয়েছে');
  String get callSummary =>
      pick('Call summary', 'कॉल का सारांश', 'কলের সারাংশ');
  String get aiDraftedFromCall => pick(
    'AI drafted this from the call',
    'AI ने कॉल से यह लिखा',
    'কল থেকে AI এটি লিখেছে',
  );
  String get nothingSendsUntil => pick(
    'Nothing sends until you tap Send in WhatsApp',
    'जब तक आप WhatsApp में Send नहीं दबाते, कुछ नहीं जाता',
    'WhatsApp-এ Send না চাপা পর্যন্ত কিছুই যায় না',
  );
  String get didYouSendIt =>
      pick('Did you send it?', 'क्या आपने भेजा?', 'পাঠিয়েছেন কি?');
  String get markedAsSent =>
      pick('Marked as sent', 'भेजा हुआ मार्क किया', 'পাঠানো হিসেবে চিহ্নিত');
  String get editing => pick('Editing', 'बदल रहे हैं', 'এডিট হচ্ছে');
  String get draft => pick('Draft', 'ड्राफ़्ट', 'ড্রাফট');
  String get tapToEdit =>
      pick('Tap to edit', 'बदलने के लिए टैप करें', 'এডিট করতে ট্যাপ করুন');

  // ------------------------------------------------------------ Handoff
  String get waOpenedTapSend => pick(
    'WhatsApp opened – tap Send there ✓',
    'WhatsApp खुल गया – वहाँ Send दबाएँ ✓',
    'WhatsApp খুলেছে – সেখানে Send চাপুন ✓',
  );
  String get messageEmpty => pick(
    'The message is empty. Add some text first.',
    'मैसेज खाली है। पहले कुछ लिखें।',
    'মেসেজ খালি। আগে কিছু লিখুন।',
  );
  String get waNotInstalled => pick(
    'WhatsApp isn\'t installed',
    'WhatsApp इंस्टॉल नहीं है',
    'WhatsApp ইনস্টল করা নেই',
  );
  String get copyOrShareInstead => pick(
    'Copy or share the message instead.',
    'इसके बजाय मैसेज कॉपी या शेयर करें।',
    'তার বদলে মেসেজটি কপি বা শেয়ার করুন।',
  );
  String get openWhatsappSemantics => pick(
    'Open WhatsApp with the message ready to send',
    'मैसेज के साथ WhatsApp खोलें',
    'মেসেজসহ WhatsApp খুলুন',
  );
}
