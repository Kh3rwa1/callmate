import 's.dart';

/// "Talk to {employee}": the in-app voice test.
extension SVoice on S {
  String get vConnecting => pick('Connecting…', 'जुड़ रहा है…', 'যুক্ত হচ্ছে…');
  String get vListening => pick('Listening', 'सुन रहे हैं', 'শুনছে');
  String get vMuted => pick('Muted', 'म्यूट', 'মিউট');
  String get vSpeaking => pick('Speaking', 'बोल रहे हैं', 'বলছে');
  String get vThinking => pick('Thinking…', 'सोच रहे हैं…', 'ভাবছে…');
  String get vDisconnected =>
      pick('Disconnected', 'कॉल खत्म', 'সংযোগ বিচ্ছিন্ন');
  String get vCouldntConnect =>
      pick('Couldn\'t connect', 'जुड़ नहीं पाया', 'যুক্ত হতে পারেনি');
  String get vReady => pick('Ready', 'तैयार', 'তৈরি');
  String connectingTo(String name) => pick(
    'Connecting to $name…',
    '$name से जोड़ रहे हैं…',
    '$name-এর সঙ্গে যুক্ত হচ্ছে…',
  );
  String get sayHello => pick('Say “Hello”', '“नमस्ते” कहें', '“নমস্কার” বলুন');
  String messageTo(String name) =>
      pick('Message $name', '$name को लिखें', '$name-কে লিখুন');
  String get send => pick('Send', 'भेजें', 'পাঠান');
  String get mute => pick('Mute', 'म्यूट', 'মিউট');
  String get unmute => pick('Unmute', 'अनम्यूट', 'আনমিউট');
  String get end => pick('End', 'खत्म करें', 'শেষ করুন');
  String get talkAgain =>
      pick('Talk again', 'फिर से बात करें', 'আবার কথা বলুন');
  String get openSettings =>
      pick('Open settings', 'सेटिंग्स खोलें', 'সেটিংস খুলুন');
  String get continueToDashboard =>
      pick('Continue to dashboard', 'डैशबोर्ड पर जाएँ', 'ড্যাশবোর্ডে যান');
  String get goBack => pick('Go back', 'वापस जाएँ', 'ফিরে যান');
  String couldntConnectName(String name) => pick(
    '$name couldn\'t connect. Check your connection and try again.',
    '$name से जुड़ नहीं पाए। कनेक्शन देखकर फिर कोशिश करें।',
    '$name-এর সঙ্গে যুক্ত হওয়া গেল না। সংযোগ দেখে আবার চেষ্টা করুন।',
  );

  /// Canned questions: (chip label, message sent to the AI).
  List<(String, String)> get voiceSuggestions => [
    (
      pick('“What do you do?”', '“आप क्या करते हैं?”', '“আপনারা কী করেন?”'),
      pick('What do you do?', 'आप क्या करते हैं?', 'আপনারা কী করেন?'),
    ),
    (
      pick('“How do you handle fees?”', '“फ़ीस कितनी है?”', '“ফি কত?”'),
      pick(
        'How do you handle fees and pricing?',
        'आपकी फ़ीस और कीमतें क्या हैं?',
        'আপনাদের ফি আর দাম কেমন?',
      ),
    ),
    (
      pick(
        '“Can I book a visit?”',
        '“क्या विज़िट बुक हो सकती है?”',
        '“ভিজিট বুক করা যাবে?”',
      ),
      pick(
        'Can I book an appointment or visit?',
        'क्या मैं अपॉइंटमेंट या विज़िट बुक कर सकता हूँ?',
        'অ্যাপয়েন্টমেন্ট বা ভিজিট বুক করা যাবে?',
      ),
    ),
    (
      pick(
        '“What are your hours?”',
        '“आपका समय क्या है?”',
        '“আপনাদের সময় কখন?”',
      ),
      pick(
        'What are your calling hours?',
        'आप किस समय कॉल करते हैं?',
        'আপনারা কখন কল করেন?',
      ),
    ),
  ];
}
