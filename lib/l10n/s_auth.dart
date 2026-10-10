import 's.dart';

/// Splash and sign-in.
extension SAuth on S {
  String get tagline => pick(
    'Your AI Calling Employee',
    'आपका AI कॉलिंग कर्मचारी',
    'আপনার AI কলিং কর্মী',
  );
  String get loginHeadline => pick(
    'Your AI employee\ncalls every lead',
    'आपका AI कर्मचारी\nहर लीड को कॉल करे',
    'আপনার AI কর্মী\nপ্রতিটি লিডে কল করে',
  );
  String get loginLanguages => pick(
    'Hindi · English · Bengali',
    'हिन्दी · English · বাংলা',
    'বাংলা · हिन्दी · English',
  );
  String get loginPointCalls => pick(
    'Calls new leads within minutes',
    'नई लीड्स को मिनटों में कॉल',
    'নতুন লিডে কয়েক মিনিটে কল',
  );
  String get loginPointScores => pick(
    'Tells you who is ready to buy',
    'बताए कि कौन खरीदने को तैयार है',
    'জানায় কে কিনতে তৈরি',
  );
  String get loginPointSend => pick(
    'You review every message, then tap Send',
    'हर मैसेज आप देखें, फिर Send दबाएँ',
    'প্রতিটি মেসেজ আপনি দেখে Send চাপুন',
  );
  String get continueWithGoogle => pick(
    'Continue with Google',
    'Google से जारी रखें',
    'Google দিয়ে চালিয়ে যান',
  );
  String get useDifferentGoogle => pick(
    'Use a different Google account',
    'दूसरा Google अकाउंट चुनें',
    'অন্য Google অ্যাকাউন্ট বাছুন',
  );
  String get usePhoneInstead => pick(
    'Use phone number instead',
    'इसके बजाय फ़ोन नंबर से',
    'তার বদলে ফোন নম্বর দিয়ে',
  );
  String get demoMode => pick('Demo mode', 'डेमो मोड', 'ডেমো মোড');
  String get setUpYourBusiness => pick(
    'Set up your business',
    'अपना कारोबार सेट करें',
    'আপনার ব্যবসা সেট করুন',
  );
  String get welcome => pick('Welcome', 'स्वागत है', 'স্বাগতম');
  String get enterCode => pick('Enter code', 'कोड डालें', 'কোড দিন');
  String get createAccount =>
      pick('Create account', 'अकाउंट बनाएँ', 'অ্যাকাউন্ট তৈরি করুন');
  String get createAccountCta =>
      pick('Create Account', 'अकाउंट बनाएँ', 'অ্যাকাউন্ট তৈরি করুন');
  String get signIn => pick('Sign in', 'साइन इन', 'সাইন ইন');
  String sentTo(String phone) =>
      pick('Sent to $phone', '$phone पर भेजा गया', '$phone-এ পাঠানো হয়েছে');
  String get useTestCode =>
      pick(' · use 123456', ' · 123456 डालें', ' · 123456 দিন');
  String get businessName =>
      pick('Business name', 'कारोबार का नाम', 'ব্যবসার নাম');
  String get businessNameHint =>
      pick('e.g. Apex Coaching', 'जैसे Apex Coaching', 'যেমন Apex Coaching');
  String get businessMobile => pick(
    'Business mobile number',
    'कारोबार का मोबाइल नंबर',
    'ব্যবসার মোবাইল নম্বর',
  );
  String get shownOnFollowUps => pick(
    'Shown on your WhatsApp follow-ups',
    'आपके WhatsApp फ़ॉलो-अप पर दिखेगा',
    'আপনার WhatsApp ফলো-আপে দেখাবে',
  );
  String get mobileNumber =>
      pick('Mobile number', 'मोबाइल नंबर', 'মোবাইল নম্বর');
  String get getCode => pick(
    'Get Verification Code',
    'वेरिफ़िकेशन कोड पाएँ',
    'ভেরিফিকেশন কোড পান',
  );
  String get sendOtp => pick('Send OTP', 'OTP भेजें', 'OTP পাঠান');
  String get haveAccount => pick(
    'Already have an account? Sign in',
    'पहले से अकाउंट है? साइन इन करें',
    'আগে থেকেই অ্যাকাউন্ট আছে? সাইন ইন করুন',
  );
  String get newHere => pick(
    'New here? Create an account',
    'नए हैं? अकाउंट बनाएँ',
    'নতুন? অ্যাকাউন্ট তৈরি করুন',
  );
  String get otpLabel => pick('6-digit OTP', '6 अंकों का OTP', '6 সংখ্যার OTP');
  String get verifyCreate => pick(
    'Verify & Create Account',
    'वेरिफ़ाई करके अकाउंट बनाएँ',
    'যাচাই করে অ্যাকাউন্ট তৈরি করুন',
  );
  String get verifyEnter =>
      pick('Verify & Enter', 'वेरिफ़ाई करके आगे बढ़ें', 'যাচাই করে ঢুকুন');
  String get changeNumber => pick('Change number', 'नंबर बदलें', 'নম্বর বদলান');
  String resendIn(int s) =>
      pick('Resend in ${s}s', '$s सेकंड में दोबारा', '$s সেকেন্ডে আবার');
  String get resendCode =>
      pick('Resend code', 'कोड दोबारा भेजें', 'আবার কোড পাঠান');
  String get termsPrefix => pick(
    'By continuing, you agree to our ',
    'आगे बढ़कर आप हमारी ',
    'এগিয়ে গেলে আপনি আমাদের ',
  );
  String get terms => pick('Terms', 'शर्तों', 'শর্তাবলি');
  String get and => pick(' & ', ' और ', ' ও ');
  String get privacyPolicy =>
      pick('Privacy Policy', 'प्राइवेसी पॉलिसी', 'গোপনীয়তা নীতি');
  String get termsSuffix => pick('.', ' से सहमत होते हैं।', ' মেনে নিচ্ছেন।');
  String get errBusinessName => pick(
    'Please enter your business or company name.',
    'अपने कारोबार या कंपनी का नाम डालें।',
    'আপনার ব্যবসা বা কোম্পানির নাম দিন।',
  );
  String get errPhone10 => pick(
    'Please enter a valid 10-digit mobile number.',
    'सही 10 अंकों का मोबाइल नंबर डालें।',
    'সঠিক 10 সংখ্যার মোবাইল নম্বর দিন।',
  );
  String get errOtp6 => pick(
    'Please enter the 6-digit verification code.',
    '6 अंकों का वेरिफ़िकेशन कोड डालें।',
    '6 সংখ্যার ভেরিফিকেশন কোড দিন।',
  );
  String get orLabel => pick('or', 'या', 'অথবা');
  String get errInvalidPhone =>
      pick('Invalid phone number.', 'फ़ोन नंबर गलत है।', 'ফোন নম্বর ভুল।');
}
