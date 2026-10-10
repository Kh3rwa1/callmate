import 's.dart';

/// Home results card, the owner test call and the daily summary setting.
extension SResults on S {
  // ------------------------------------------------------------ Results card
  String get resultsThisWeek => pick('This week', 'इस हफ़्ते', 'এই সপ্তাহে');
  String get statEnquiries => pick('Enquiries', 'पूछताछ', 'এনকোয়ারি');
  String get statMessagesSent =>
      pick('Messages sent', 'भेजे गए मैसेज', 'পাঠানো মেসেজ');
  String deltaVsLastWeek(int d) {
    final sign = d > 0 ? '+' : '';
    return pick(
      '$sign$d vs last week',
      'पिछले हफ़्ते से $sign$d',
      'গত সপ্তাহের চেয়ে $sign$d',
    );
  }

  String resultsWorth(String amount) => pick(
    'Worth about $amount',
    'लगभग $amount का काम',
    'প্রায় $amount মূল্যের',
  );
  String resultsWorthDetail(int n, String avg) => pick(
    '$n ready to buy × $avg average sale',
    '$n खरीदने को तैयार × $avg औसत बिक्री',
    '$n জন কিনতে তৈরি × $avg গড় বিক্রি',
  );
  String get addAvgSaleCta => pick(
    'Add your average sale value to see what this is worth',
    'औसत बिक्री मूल्य डालें और देखें यह कितने का है',
    'গড় বিক্রির মূল্য দিন, দেখুন এর দাম কত',
  );

  // ------------------------------------------------------------ Avg sale sheet
  String get avgSaleTitle =>
      pick('Average sale value', 'औसत बिक्री मूल्य', 'গড় বিক্রির মূল্য');
  String get avgSaleHint => pick(
    'What one customer usually pays you. Used only to estimate what your AI\'s results are worth.',
    'एक ग्राहक आम तौर पर आपको कितना देता है। सिर्फ़ यह अंदाज़ा लगाने के लिए कि AI के नतीजे कितने के हैं।',
    'একজন গ্রাহক সাধারণত আপনাকে কত দেন। শুধু AI-এর ফলাফলের মূল্য আন্দাজ করতে ব্যবহার হয়।',
  );
  String get avgSaleInvalid => pick(
    'Enter an amount in rupees, like 5000',
    'रुपये में रकम डालें, जैसे 5000',
    'টাকায় পরিমাণ দিন, যেমন 5000',
  );
  String get removeValue => pick('Remove', 'हटाएँ', 'সরান');

  // ------------------------------------------------------------ Owner test call
  String get hearYourAiTitle => pick(
    'Hear your AI on a real call',
    'असली कॉल पर अपना AI सुनें',
    'আসল কলে আপনার AI শুনুন',
  );
  String hearYourAiBody(String name) => pick(
    '$name will call your phone, so you hear exactly what your customers hear.',
    '$name से आपके फ़ोन पर कॉल आएगी, ताकि आप वही सुनें जो आपके ग्राहक सुनते हैं।',
    '$name আপনার ফোনে কল করবে, যাতে আপনি ঠিক তাই শোনেন যা গ্রাহকরা শোনেন।',
  );
  String get hearYourAiShort =>
      pick('Hear your AI on a call', 'कॉल पर AI सुनें', 'কলে AI শুনুন');
  String get callMeNow =>
      pick('Call me now', 'मुझे अभी कॉल करें', 'আমাকে এখনই কল করুন');
  String get yourMobileNumber =>
      pick('Your mobile number', 'आपका मोबाइल नंबर', 'আপনার মোবাইল নম্বর');
  String get testCallUsesMinutes => pick(
    'Uses about a minute from your plan. Only you are called.',
    'आपके प्लान से लगभग एक मिनट लगेगा। सिर्फ़ आपको कॉल होगी।',
    'আপনার প্ল্যান থেকে প্রায় এক মিনিট লাগবে। শুধু আপনাকেই কল করা হবে।',
  );
  String get testCallPlaced => pick(
    'Calling you now. Your phone will ring in a few seconds.',
    'आपको कॉल हो रही है। कुछ सेकंड में फ़ोन बजेगा।',
    'আপনাকে কল করা হচ্ছে। কয়েক সেকেন্ডে ফোন বাজবে।',
  );
  String testCallsLeft(int n) => plural(
    n,
    '$n test call left today',
    '$n test calls left today',
    'आज $n टेस्ट कॉल बाकी',
    'আজ $n টি টেস্ট কল বাকি',
  );
  String get testCallLimitReached => pick(
    'You have used today\'s test calls. Try again tomorrow, or talk to your AI in the app.',
    'आज की टेस्ट कॉल हो चुकी हैं। कल फिर कोशिश करें, या ऐप में AI से बात करें।',
    'আজকের টেস্ট কল শেষ। কাল আবার চেষ্টা করুন, বা অ্যাপে AI-এর সঙ্গে কথা বলুন।',
  );
  String get testCallPhoneIsCustomer => pick(
    'This number is one of your customers. Use your own number.',
    'यह नंबर आपके एक ग्राहक का है। अपना नंबर डालें।',
    'এই নম্বরটা আপনার একজন গ্রাহকের। নিজের নম্বর দিন।',
  );

  // ------------------------------------------------------------ Daily summary
  String get dailySummaryTitle => pick(
    'Daily summary at 7 PM',
    'शाम 7 बजे दिन का सार',
    'সন্ধ্যা 7টায় দিনের সারাংশ',
  );
  String get dailySummarySubtitle => pick(
    'One notification with today\'s calls and who is ready to buy',
    'आज की कॉल और खरीदने को तैयार ग्राहकों की एक सूचना',
    'আজকের কল আর কে কিনতে তৈরি, একটা নোটিফিকেশনে',
  );
}
