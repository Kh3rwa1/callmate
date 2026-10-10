import 's.dart';

/// Display translations for English text that also lives in data:
/// business templates (labels, hints, sample leads), default roles, goals,
/// capabilities, voices and language names.
///
/// Stored values stay English (the backend and the AI read them); only
/// what's shown is translated. Anything not listed – e.g. a role the owner
/// typed themselves – is shown as entered.
extension SData on S {
  String data(String en) {
    if (isEn) return _plainEn[en.trim()] ?? en;
    final t = _data[en.trim()];
    if (t == null) return en;
    return lang == AppLang.hi ? t.$1 : t.$2;
  }

  /// [data] for each item, joined with " · ".
  String dataList(Iterable<String> items) => items.map(data).join(' · ');
}

/// Backend words an owner wouldn't use, shown in plain English instead.
/// The stored value stays the same; only the label changes.
const _plainEn = <String, String>{
  'Lead Qualification': 'Finds serious buyers',
  'Follow-up': 'Sends WhatsApp messages',
  'Callback Scheduling': 'Books call backs',
  'Hot Lead Alerts': 'Tells you who wants to buy',
};

const _data = <String, (String, String)>{
  // Roles
  'Sales Assistant': ('सेल्स असिस्टेंट', 'সেলস অ্যাসিস্ট্যান্ট'),
  'Admissions Assistant': ('एडमिशन असिस्टेंट', 'ভর্তি সহকারী'),
  'Admissions Counsellor': ('एडमिशन काउंसलर', 'ভর্তি কাউন্সেলর'),
  'Appointment Assistant': ('अपॉइंटमेंट असिस्टेंट', 'অ্যাপয়েন্টমেন্ট সহকারী'),
  'Support Assistant': ('सपोर्ट असिस्टेंट', 'সাপোর্ট সহকারী'),
  'Reception Assistant': ('रिसेप्शन असिस्टेंट', 'রিসেপশন সহকারী'),

  // Goals and purposes
  'Convert enquiries into qualified opportunities': (
    'पूछताछ को पक्के ग्राहकों में बदलना',
    'জিজ্ঞাসাকে পাকা সুযোগে বদলানো',
  ),
  'Convert enquiries into counselling appointments': (
    'पूछताछ को काउंसलिंग अपॉइंटमेंट में बदलना',
    'জিজ্ঞাসাকে কাউন্সেলিং অ্যাপয়েন্টমেন্টে বদলানো',
  ),
  'Turn enquiries into booked appointments': (
    'पूछताछ को बुक किए गए अपॉइंटमेंट में बदलना',
    'জিজ্ঞাসাকে বুক করা অ্যাপয়েন্টমেন্টে বদলানো',
  ),
  'Answer customer questions and resolve enquiries quickly': (
    'ग्राहकों के सवालों का जल्दी जवाब देना',
    'গ্রাহকের প্রশ্নের দ্রুত উত্তর দেওয়া',
  ),
  'Enquiry follow-up': ('पूछताछ का फ़ॉलो-अप', 'জিজ্ঞাসার ফলো-আপ'),
  'Admission enquiry follow-up': (
    'एडमिशन पूछताछ का फ़ॉलो-अप',
    'ভর্তির জিজ্ঞাসার ফলো-আপ',
  ),
  'Appointment enquiry follow-up': (
    'अपॉइंटमेंट पूछताछ का फ़ॉलो-अप',
    'অ্যাপয়েন্টমেন্টের জিজ্ঞাসার ফলো-আপ',
  ),
  'Customer support follow-up': (
    'कस्टमर सपोर्ट फ़ॉलो-अप',
    'কাস্টমার সাপোর্ট ফলো-আপ',
  ),

  // Capabilities
  'Calling': ('कॉलिंग', 'কল করা'),
  'Lead Qualification': ('पक्के खरीदार ढूँढता है', 'আসল ক্রেতা খোঁজে'),
  'Follow-up': ('WhatsApp मैसेज भेजता है', 'WhatsApp মেসেজ পাঠায়'),
  'Customer Questions': ('ग्राहकों के सवाल', 'গ্রাহকের প্রশ্ন'),
  'Callback Scheduling': ('कॉल बैक तय करता है', 'কল ব্যাক ঠিক করে'),
  'Hot Lead Alerts': ('बताता है कौन खरीदना चाहता है', 'জানায় কে কিনতে চান'),
  'Admissions guidance': ('एडमिशन सलाह', 'ভর্তির পরামর্শ'),
  'Admissions Guidance': ('एडमिशन सलाह', 'ভর্তির পরামর্শ'),
  'Appointment Booking': ('अपॉइंटमेंट बुकिंग', 'অ্যাপয়েন্টমেন্ট বুকিং'),
  'Sales Conversations': ('सेल्स बातचीत', 'সেলসের কথাবার্তা'),
  'Customer Support': ('कस्टमर सपोर्ट', 'কাস্টমার সাপোর্ট'),
  'Enquiry Handling': ('पूछताछ संभालना', 'জিজ্ঞাসার উত্তর'),

  // Languages
  'English': ('अंग्रेज़ी', 'ইংরেজি'),
  'Hindi': ('हिन्दी', 'হিন্দি'),
  'Bengali': ('बांग्ला', 'বাংলা'),
  'Odia': ('ओड़िया', 'ওড়িয়া'),
  'Tamil': ('तमिल', 'তামিল'),
  'Telugu': ('तेलुगु', 'তেলুগু'),
  'Marathi': ('मराठी', 'মারাঠি'),
  'Gujarati': ('गुजराती', 'গুজরাটি'),
  'Kannada': ('कन्नड़', 'কন্নড়'),
  'Malayalam': ('मलयालम', 'মালয়ালম'),
  'Punjabi': ('पंजाबी', 'পাঞ্জাবি'),

  // Plans
  'Founding Plan': ('फ़ाउंडिंग प्लान', 'ফাউন্ডিং প্ল্যান'),
  'Free trial': ('फ़्री ट्रायल', 'ফ্রি ট্রায়াল'),
  'Starter': ('स्टार्टर प्लान', 'স্টার্টার প্ল্যান'),
  'Growth': ('ग्रोथ प्लान', 'গ্রোথ প্ল্যান'),

  // Voices and personality
  'Warm · Female': ('गर्मजोशी · महिला', 'আন্তরিক · মহিলা'),
  'Calm · Female': ('शांत · महिला', 'শান্ত · মহিলা'),
  'Friendly · Male': ('दोस्ताना · पुरुष', 'বন্ধুসুলভ · পুরুষ'),
  'Confident · Male': ('आत्मविश्वासी · पुरुष', 'আত্মবিশ্বাসী · পুরুষ'),
  'Warm · Friendly': ('गर्मजोशी · दोस्ताना', 'আন্তরিক · বন্ধুসুলভ'),
  'Friendly · Professional': ('दोस्ताना · प्रोफ़ेशनल', 'বন্ধুসুলভ · পেশাদার'),
  'Formal · Professional': ('औपचारिक · प्रोफ़ेशनल', 'আনুষ্ঠানিক · পেশাদার'),

  // Workflow vocabulary
  'customer': ('ग्राहक', 'গ্রাহক'),
  'student': ('छात्र', 'ছাত্রছাত্রী'),
  'patient': ('मरीज़', 'রোগী'),
  'buyer': ('खरीदार', 'ক্রেতা'),
  'client': ('क्लाइंट', 'ক্লায়েন্ট'),
  'member': ('मेंबर', 'মেম্বার'),
  'Goal': ('लक्ष्य', 'লক্ষ্য'),
  'Plans / classes': ('प्लान / क्लास', 'প্ল্যান / ক্লাস'),
  'Trainer': ('ट्रेनर', 'ট্রেনার'),
  'Interest': ('रुचि', 'আগ্রহ'),
  'Course': ('कोर्स', 'কোর্স'),
  'Property': ('प्रॉपर्टी', 'প্রপার্টি'),
  'Service': ('सेवा', 'পরিষেবা'),
  'Model': ('मॉडल', 'মডেল'),
  'Products / services': ('प्रोडक्ट / सेवाएँ', 'প্রোডাক্ট / পরিষেবা'),
  'Courses': ('कोर्स', 'কোর্স'),
  'Projects / properties': ('प्रोजेक्ट / प्रॉपर्टी', 'প্রজেক্ট / প্রপার্টি'),
  'Services / departments': ('सेवाएँ / विभाग', 'পরিষেবা / বিভাগ'),
  'Models / services': ('मॉडल / सेवाएँ', 'মডেল / পরিষেবা'),
  'Services': ('सेवाएँ', 'পরিষেবা'),
  'Team member': ('टीम सदस्य', 'টিমের সদস্য'),
  'Counsellor': ('काउंसलर', 'কাউন্সেলর'),
  'Sales agent': ('सेल्स एजेंट', 'সেলস এজেন্ট'),
  'Front desk': ('फ्रंट डेस्क', 'ফ্রন্ট ডেস্ক'),
  'Sales executive': ('सेल्स एग्ज़िक्यूटिव', 'সেলস এক্সিকিউটিভ'),
  'Stylist': ('स्टाइलिस्ट', 'স্টাইলিস্ট'),
  'Batch': ('बैच', 'ব্যাচ'),
  'Budget': ('बजट', 'বাজেট'),
  'Preferred area': ('पसंदीदा इलाका', 'পছন্দের এলাকা'),
  'Preferred slot': ('पसंदीदा समय', 'পছন্দের সময়'),

  // Interest options (shown translated, stored in English)
  'Product enquiry': ('प्रोडक्ट की पूछताछ', 'প্রোডাক্টের জিজ্ঞাসা'),
  'Service enquiry': ('सेवा की पूछताछ', 'পরিষেবার জিজ্ঞাসা'),
  'Pricing': ('कीमत', 'দাম'),
  'Demo / visit': ('डेमो / विज़िट', 'ডেমো / ভিজিট'),
  'Other': ('अन्य', 'অন্যান্য'),
  'Consultation': ('परामर्श', 'পরামর্শ'),
  'Follow-up visit': ('फ़ॉलो-अप विज़िट', 'ফলো-আপ ভিজিট'),
  'Health check-up': ('हेल्थ चेक-अप', 'হেলথ চেক-আপ'),
  'Procedure enquiry': ('इलाज की पूछताछ', 'চিকিৎসার জিজ্ঞাসা'),
  'Service booking': ('सर्विस बुकिंग', 'সার্ভিস বুকিং'),
  'Haircut': ('हेयरकट', 'হেয়ারকাট'),
  'Hair colour': ('हेयर कलर', 'হেয়ার কালার'),
  'Facial': ('फ़ेशियल', 'ফেসিয়াল'),
  'Bridal': ('ब्राइडल', 'ব্রাইডাল'),
  'Spa': ('स्पा', 'স্পা'),
  'Weight loss': ('वज़न घटाना', 'ওজন কমানো'),
  'Muscle gain': ('मसल बनाना', 'পেশি বাড়ানো'),
  'General fitness': ('फ़िट रहना', 'সাধারণ ফিটনেস'),
  'Personal training': ('पर्सनल ट्रेनिंग', 'পার্সোনাল ট্রেনিং'),
  'Yoga': ('योग', 'যোগব্যায়াম'),

  // Hints
  'e.g. Home cleaning, AC repair, Pest control': (
    'जैसे होम क्लीनिंग, AC रिपेयर, पेस्ट कंट्रोल',
    'যেমন হোম ক্লিনিং, AC রিপেয়ার, পেস্ট কন্ট্রোল',
  ),
  'e.g. NEET, JEE Main, Class 10 Boards': (
    'जैसे NEET, JEE Main, Class 10 Boards',
    'যেমন NEET, JEE Main, Class 10 Boards',
  ),
  'e.g. Green Valley 2 & 3 BHK, Lake View Plots': (
    'जैसे Green Valley 2 और 3 BHK, Lake View प्लॉट',
    'যেমন Green Valley 2 ও 3 BHK, Lake View প্লট',
  ),
  'e.g. General physician, Dental, Dermatology': (
    'जैसे जनरल फ़िज़िशियन, डेंटल, स्किन',
    'যেমন জেনারেল ফিজিশিয়ান, ডেন্টাল, স্কিন',
  ),
  'e.g. City, Amaze, Elevate, Servicing': (
    'जैसे City, Amaze, Elevate, सर्विसिंग',
    'যেমন City, Amaze, Elevate, সার্ভিসিং',
  ),
  'e.g. Haircut, Colour, Facial, Bridal makeup': (
    'जैसे हेयरकट, कलर, फ़ेशियल, ब्राइडल मेकअप',
    'যেমন হেয়ারকাট, কালার, ফেসিয়াল, ব্রাইডাল মেকআপ',
  ),
  'Services, pricing, opening hours, location, policies, FAQs': (
    'सेवाएँ, कीमतें, समय, पता, नियम, सवाल-जवाब',
    'পরিষেবা, দাম, সময়, ঠিকানা, নিয়ম, প্রশ্নোত্তর',
  ),
  'Courses, fees, batch timings, faculty, results, FAQs': (
    'कोर्स, फ़ीस, बैच का समय, टीचर, रिज़ल्ट, सवाल-जवाब',
    'কোর্স, ফি, ব্যাচের সময়, শিক্ষক, রেজাল্ট, প্রশ্নোত্তর',
  ),
  'Projects, prices, possession dates, amenities, location': (
    'प्रोजेक्ट, कीमतें, पज़ेशन की तारीख, सुविधाएँ, लोकेशन',
    'প্রজেক্ট, দাম, পজেশনের তারিখ, সুবিধা, লোকেশন',
  ),
  'Doctors, timings, consultation fees, location, policies': (
    'डॉक्टर, समय, परामर्श फ़ीस, पता, नियम',
    'ডাক্তার, সময়, পরামর্শের ফি, ঠিকানা, নিয়ম',
  ),
  'Models, on-road prices, offers, test drives, service plans': (
    'मॉडल, ऑन-रोड कीमत, ऑफ़र, टेस्ट ड्राइव, सर्विस प्लान',
    'মডেল, অন-রোড দাম, অফার, টেস্ট ড্রাইভ, সার্ভিস প্ল্যান',
  ),
  'e.g. Monthly plan, Personal training, Zumba, Yoga': (
    'जैसे मंथली प्लान, पर्सनल ट्रेनिंग, ज़ुम्बा, योग',
    'যেমন মাসিক প্ল্যান, পার্সোনাল ট্রেনিং, জুম্বা, যোগব্যায়াম',
  ),
  'Membership plans, fees, timings, trainers, classes, location': (
    'मेंबरशिप प्लान, फ़ीस, समय, ट्रेनर, क्लास, पता',
    'মেম্বারশিপ প্ল্যান, ফি, সময়, ট্রেনার, ক্লাস, ঠিকানা',
  ),
  'Services, price list, timings, offers, location': (
    'सेवाएँ, रेट लिस्ट, समय, ऑफ़र, पता',
    'পরিষেবা, রেট লিস্ট, সময়, অফার, ঠিকানা',
  ),

  // Sample leads (onboarding "first call")
  'Asked about pricing': ('कीमत के बारे में पूछा', 'দাম জানতে চেয়েছেন'),
  'NEET · Evening batch': ('NEET · शाम का बैच', 'NEET · সন্ধ্যার ব্যাচ'),
  '3 BHK · Site visit': ('3 BHK · साइट विज़िट', '3 BHK · সাইট ভিজিট'),
  'Consultation · Evening': ('परामर्श · शाम', 'পরামর্শ · সন্ধ্যা'),
  'SUV · Test drive': ('SUV · टेस्ट ड्राइव', 'SUV · টেস্ট ড্রাইভ'),
  'Haircut · Saturday': ('हेयरकट · शनिवार', 'হেয়ারকাট · শনিবার'),
  'Weight loss · Trial': ('वज़न घटाना · ट्रायल', 'ওজন কমানো · ট্রায়াল'),
  '“Hi, I saw your ad. Can you tell me the price and how soon you can start?”': (
    '“नमस्ते, मैंने आपका विज्ञापन देखा। कीमत क्या है और कब से शुरू कर सकते हैं?”',
    '“নমস্কার, আপনাদের বিজ্ঞাপন দেখলাম। দাম কত আর কবে থেকে শুরু করতে পারবেন?”',
  ),
  '“Hi, I filled a form for NEET coaching. What are the fees?”': (
    '“नमस्ते, मैंने NEET कोचिंग का फ़ॉर्म भरा था। फ़ीस कितनी है?”',
    '“নমস্কার, NEET কোচিংয়ের ফর্ম ভরেছিলাম। ফি কত?”',
  ),
  '“I saw the Green Valley ad. What\'s the price of a 3 BHK?”': (
    '“मैंने Green Valley का विज्ञापन देखा। 3 BHK की कीमत क्या है?”',
    '“Green Valley-র বিজ্ঞাপন দেখলাম। 3 BHK-র দাম কত?”',
  ),
  '“I want to book a consultation. Is the doctor available this evening?”': (
    '“मुझे परामर्श बुक करना है। क्या डॉक्टर आज शाम मिलेंगे?”',
    '“একটা পরামর্শ বুক করতে চাই। ডাক্তার কি আজ সন্ধ্যায় আছেন?”',
  ),
  '“What\'s the on-road price of the SUV? Can I book a test drive?”': (
    '“SUV की ऑन-रोड कीमत क्या है? क्या टेस्ट ड्राइव बुक हो सकती है?”',
    '“SUV-র অন-রোড দাম কত? টেস্ট ড্রাইভ বুক করা যাবে?”',
  ),
  '“How much is a monthly membership? Can I try a session first?”': (
    '“मंथली मेंबरशिप कितने की है? क्या पहले एक सेशन ट्राई कर सकता हूँ?”',
    '“মাসিক মেম্বারশিপ কত? আগে একটা সেশন করে দেখতে পারি?”',
  ),
  '“Do you have a slot on Saturday for a haircut?”': (
    '“क्या शनिवार को हेयरकट का समय मिलेगा?”',
    '“শনিবার হেয়ারকাটের সময় পাওয়া যাবে?”',
  ),
};
