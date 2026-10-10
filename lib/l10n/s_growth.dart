import 's.dart';

/// Referral program: signup referral field and the "Invite & earn" screen.
extension SGrowth on S {
  // ------------------------------------------------------------ Signup
  String get referralCodeOptional => pick(
    'Referral code (optional)',
    'रेफ़रल कोड (ज़रूरी नहीं)',
    'রেফারেল কোড (ঐচ্ছিক)',
  );
  String get referralCodeHelper => pick(
    'From the business that invited you',
    'जिस बिज़नेस ने आपको बुलाया, उनसे मिला कोड',
    'যে ব্যবসা আপনাকে আমন্ত্রণ জানিয়েছে, তাদের দেওয়া কোড',
  );

  // ------------------------------------------------------------ Invite & earn
  String get inviteAndEarn =>
      pick('Invite & earn', 'बुलाएँ और कमाएँ', 'আমন্ত্রণ করুন, আয় করুন');
  String inviteRowValue(int minutes) =>
      pick('$minutes free min', '$minutes मुफ़्त मिनट', '$minutes ফ্রি মিনিট');
  String inviteHeadline(int minutes) => pick(
    'Give $minutes minutes, get $minutes minutes',
    '$minutes मिनट दें, $minutes मिनट पाएँ',
    '$minutes মিনিট দিন, $minutes মিনিট পান',
  );
  String inviteBody(int minutes) => pick(
    'Know another business owner who misses enquiries? When a business you invite makes its first payment, you both get $minutes free call minutes.',
    'किसी और बिज़नेस मालिक को जानते हैं जिनकी पूछताछ छूट जाती है? आपके बुलाए बिज़नेस का पहला पेमेंट होते ही आप दोनों को $minutes मुफ़्त कॉल मिनट मिलेंगे।',
    'এমন কোনো ব্যবসার মালিককে চেনেন যাঁর এনকোয়ারি মিস হয়? আপনার আমন্ত্রিত ব্যবসা প্রথম পেমেন্ট করলেই আপনারা দুজনেই $minutes ফ্রি কল মিনিট পাবেন।',
  );
  String get yourReferralCode =>
      pick('Your referral code', 'आपका रेफ़रल कोड', 'আপনার রেফারেল কোড');
  String get copyCode => pick('Copy code', 'कोड कॉपी करें', 'কোড কপি করুন');
  String get copyInviteLink =>
      pick('Copy link', 'लिंक कॉपी करें', 'লিংক কপি করুন');
  String get copiedToClipboard => pick('Copied', 'कॉपी हो गया', 'কপি হয়েছে');
  String get shareOnWhatsApp => pick(
    'Share on WhatsApp',
    'WhatsApp पर शेयर करें',
    'WhatsApp-এ শেয়ার করুন',
  );
  String get shareOtherApps => pick(
    'Share another way',
    'दूसरे तरीके से शेयर करें',
    'অন্যভাবে শেয়ার করুন',
  );
  String get whatsAppNotOpened => pick(
    "Couldn't open WhatsApp. Copy the link instead.",
    'WhatsApp नहीं खुला। लिंक कॉपी कर लें।',
    'WhatsApp খোলা গেল না। লিংকটি কপি করে নিন।',
  );
  String get inviteYouSend => pick(
    'WhatsApp opens with the message ready. You choose who gets it and tap send.',
    'WhatsApp में मैसेज तैयार मिलेगा। किसे भेजना है, आप चुनें और भेजें।',
    'WhatsApp-এ মেসেজ তৈরি থাকবে। কাকে পাঠাবেন আপনি বেছে নিয়ে পাঠান।',
  );
  String get referralsJoined => pick('Signed up', 'जुड़े', 'যোগ দিয়েছেন');
  String get referralsPaid => pick('Paid', 'पेमेंट किया', 'পেমেন্ট করেছেন');
  String get minutesEarned =>
      pick('Minutes earned', 'कमाए मिनट', 'অর্জিত মিনিট');
  String get inviteHowItWorks =>
      pick('How it works', 'कैसे काम करता है', 'কীভাবে কাজ করে');
  String get inviteStep1 => pick(
    'Share your link on WhatsApp.',
    'अपना लिंक WhatsApp पर शेयर करें।',
    'আপনার লিংক WhatsApp-এ শেয়ার করুন।',
  );
  String get inviteStep2 => pick(
    'They install CallPilot and sign up. Your code is filled in for them.',
    'वे CallPilot इंस्टॉल करके साइन अप करें। आपका कोड अपने-आप भर जाएगा।',
    'তাঁরা CallPilot ইনস্টল করে সাইন আপ করবেন। আপনার কোড নিজে থেকেই বসে যাবে।',
  );
  String inviteStep3(int minutes) => pick(
    'After their first payment, you both get $minutes minutes.',
    'उनके पहले पेमेंट के बाद आप दोनों को $minutes मिनट मिलेंगे।',
    'তাঁদের প্রথম পেমেন্টের পর আপনারা দুজনেই $minutes মিনিট পাবেন।',
  );

  /// The WhatsApp message the owner sends (they pick the contact and tap send).
  String inviteMessage(String link, String code, int minutes) => pick(
    'I use CallPilot: an AI that calls back every enquiry within a minute, in Hindi, Bengali or English, and tells me who is serious. Try it: $link\nUse my code $code when you sign up and we both get $minutes free call minutes after your first payment.',
    'मैं CallPilot इस्तेमाल करता/करती हूँ: यह AI हर पूछताछ को एक मिनट में हिंदी, बांग्ला या अंग्रेज़ी में कॉल करता है और बताता है कि कौन सच में इच्छुक है। आज़माएँ: $link\nसाइन अप करते समय मेरा कोड $code डालें, आपके पहले पेमेंट के बाद हम दोनों को $minutes मुफ़्त कॉल मिनट मिलेंगे।',
    'আমি CallPilot ব্যবহার করি: এই AI প্রতিটি এনকোয়ারিতে এক মিনিটের মধ্যে বাংলা, হিন্দি বা ইংরেজিতে কল করে আর জানায় কে সত্যিই আগ্রহী। চেষ্টা করে দেখুন: $link\nসাইন আপের সময় আমার কোড $code দিন, আপনার প্রথম পেমেন্টের পর আমরা দুজনেই $minutes ফ্রি কল মিনিট পাব।',
  );
}
