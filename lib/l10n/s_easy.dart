import 's.dart';

/// The short first run (business → name and voice → hear your AI), the Home
/// "Getting started" card, the Help sheet, text size and the regrouped
/// "My employee" tab.
///
/// Hindi copy avoids verbs that would give the AI employee a gender.
extension SEasy on S {
  // ------------------------------------------------------- First run: 1/3
  String get obTypeQuestion => pick(
    'What is your business?',
    'आपका कारोबार क्या है?',
    'আপনার ব্যবসা কী?',
  );
  String get obTypeHint => pick(
    'Tap one. Your AI employee will call your customers for you.',
    'एक चुनें। आपका AI कर्मचारी आपकी तरफ़ से ग्राहकों को कॉल करेगा।',
    'একটি বাছুন। আপনার AI কর্মী আপনার হয়ে গ্রাহকদের কল করবে।',
  );

  // ------------------------------------------------------- First run: 2/3
  String get obNameTitle =>
      pick('Your business name', 'आपके कारोबार का नाम', 'আপনার ব্যবসার নাম');
  String get obNameSub => pick(
    'Your AI employee says this name on every call.',
    'हर कॉल पर यही नाम बोला जाएगा।',
    'প্রতিটি কলে এই নামই বলা হবে।',
  );
  String get obVoiceQuestion => pick(
    'Who should speak for you?',
    'आपकी तरफ़ से कौन बोले?',
    'আপনার হয়ে কে কথা বলবে?',
  );

  /// "Maya, your Sales Assistant. You can change this later." [role] is
  /// already translated.
  String obEmployeeIntro(String name, String role) => pick(
    '$name, your $role. You can change this later.',
    '$name, आपका $role। बाद में बदल सकते हैं।',
    '$name, আপনার $role। পরে বদলাতে পারবেন।',
  );

  // ------------------------------------------------------- First run: 3/3
  String get obHearTitle => pick(
    'Hear your AI employee',
    'अपने AI कर्मचारी को सुनें',
    'আপনার AI কর্মীর কথা শুনুন',
  );
  String obHearSub(String name) => pick(
    '$name will call your phone now. Hear exactly what your customers will hear.',
    '$name की कॉल अभी आपके फ़ोन पर आएगी। सुनें, आपके ग्राहक क्या सुनेंगे।',
    '$name এখনই আপনার ফোনে কল করবে। শুনুন, আপনার গ্রাহকরা কী শুনবেন।',
  );

  /// [from] / [to] are formatted times ("10 AM", "7 PM").
  String outsideCallingHours(String name, String from, String to) => pick(
    'Phone calls can only be made between $from and $to. Talk to $name here in the app instead.',
    'फ़ोन कॉल सिर्फ़ $from से $to के बीच हो सकती है। अभी ऐप में ही $name से बात करें।',
    'ফোন কল শুধু $from থেকে $to-এর মধ্যে করা যায়। এখন অ্যাপেই $name-এর সঙ্গে কথা বলুন।',
  );
  String get goToHome => pick('Go to home', 'होम पर जाएँ', 'হোমে যান');
  String get setupNotSaved => pick(
    'Could not save. Check your internet and try again.',
    'सेव नहीं हो पाया। इंटरनेट देखकर फिर कोशिश करें।',
    'সেভ হল না। ইন্টারনেট দেখে আবার চেষ্টা করুন।',
  );

  // ------------------------------------------------- Home: getting started
  String get gsTitle => pick('Getting started', 'शुरुआत करें', 'শুরু করুন');
  String gsProgress(int done, int total) => pick(
    '$done of $total done',
    '$total में से $done हो गए',
    '$total-টির মধ্যে $done-টি হয়েছে',
  );
  String get gsContacts => pick(
    'Add customers from your phone contacts',
    'फ़ोन कॉन्टैक्ट्स से ग्राहक जोड़ें',
    'ফোনের কন্টাক্ট থেকে গ্রাহক যোগ করুন',
  );
  String get gsHear => pick(
    'Hear your AI on a real call',
    'असली कॉल पर अपने AI को सुनें',
    'আসল কলে আপনার AI-কে শুনুন',
  );
  String get gsForm => pick(
    'Share your enquiry form',
    'अपना पूछताछ फ़ॉर्म शेयर करें',
    'আপনার এনকোয়ারি ফর্ম শেয়ার করুন',
  );
  String get gsHide => pick('Hide', 'छिपाएँ', 'লুকান');
  String get gsDone => pick('Done', 'हो गया', 'হয়ে গেছে');

  // ------------------------------------------------------------ Top bar
  String get help => pick('Help', 'मदद', 'সাহায্য');
  String get alertsShort => pick('Alerts', 'अलर्ट', 'অ্যালার্ট');

  // ------------------------------------------------------------ Help sheet
  String get helpWatchVideo => pick(
    'Watch 1-minute video',
    '1 मिनट का वीडियो देखें',
    '১ মিনিটের ভিডিও দেখুন',
  );
  String get helpEmail =>
      pick('Email us', 'हमें ईमेल करें', 'আমাদের ইমেল করুন');

  // ------------------------------------------------------------ Text size
  String get textSize => pick('Text size', 'अक्षरों का आकार', 'লেখার মাপ');
  String get textNormal => pick('Normal', 'सामान्य', 'সাধারণ');
  String get textLarge => pick('Large', 'बड़ा', 'বড়');
  String get textExtraLarge => pick('Extra large', 'बहुत बड़ा', 'খুব বড়');

  // ------------------------------------------------------ My employee tab
  String get myEmployee => pick('My employee', 'मेरा कर्मचारी', 'আমার কর্মী');
  String get sectionYourEmployee =>
      pick('Your employee', 'आपका कर्मचारी', 'আপনার কর্মী');
  String get sectionPlan =>
      pick('Plan & minutes', 'प्लान और मिनट', 'প্ল্যান ও মিনিট');
  String get sectionSettingsHelp =>
      pick('Settings & help', 'सेटिंग्स और मदद', 'সেটিংস ও সাহায্য');

  // ------------------------------------------------------------ Customers
  String get getCustomersAuto => pick(
    'Get new customers automatically',
    'नए ग्राहक अपने-आप पाएँ',
    'নতুন গ্রাহক নিজে থেকেই পান',
  );
  String get getCustomersAutoSub => pick(
    'Your AI calls every new enquiry within minutes',
    'हर नई पूछताछ पर AI मिनटों में कॉल करे',
    'প্রতিটি নতুন এনকোয়ারিতে AI কয়েক মিনিটে কল করে',
  );
  String get addShort => pick('Add', 'जोड़ें', 'যোগ করুন');

  // ------------------------------------------------------------ Demo
  String get demoNewOwner => pick(
    'Start as a new owner',
    'नए मालिक की तरह शुरू करें',
    'নতুন মালিক হিসেবে শুরু করুন',
  );
}
