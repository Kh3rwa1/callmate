/**
 * Text of the public pages in English, Hindi and Bengali, side by side so a reviewer can proofread
 * them together. Values are plain text unless the key ends in `Html` (trusted markup written here;
 * every interpolated value is HTML-escaped by the caller first).
 *
 * The consent sentence keeps the SAME legal meaning in every language: agreeing to receive a call
 * from the named business about the enquiry, which may be an automated AI call. Each language's
 * wording is versioned separately (services/consent.ts formConsentTextVersion), so changing one
 * language's sentence means bumping that version.
 */
import type { PageLang } from './page_lang';

type L<T = string> = Record<PageLang, T>;

export interface FormStrings {
  enquireTitle: string;
  lede: string;
  nameLabel: string;
  phoneLabel: string;
  interestLabel: string;
  optional: string;
  honeypotLabel: string;
  submit: string;
  consent: (business: string) => string;
  errName: string;
  errPhone: string;
  errConsent: string;
  thankYouTitle: string;
  thankYou: (first: string) => string;
  willCall: (business: string) => string;
  willContact: (business: string) => string;
  notFoundTitle: string;
  notFoundMessage: string;
  tooLongTitle: string;
  tooLongMessage: string;
  waitTitle: string;
  waitMessage: string;
  poweredBy: string;
  privacy: string;
  languageLabel: string;
}

export const FORM_STRINGS: L<FormStrings> = {
  en: {
    enquireTitle: 'Enquire',
    lede: 'Leave your details and we’ll call you back in about a minute.',
    nameLabel: 'Your name',
    phoneLabel: 'Mobile number',
    interestLabel: 'What are you interested in?',
    optional: '(optional)',
    honeypotLabel: 'Leave this empty',
    submit: 'Request a call',
    consent: (b) => `I agree to receive a call from ${b} about my enquiry (may be an automated AI call).`,
    errName: 'Please enter your name.',
    errPhone: 'Please enter a valid mobile number.',
    errConsent: 'Please tick the box to agree to receive a call.',
    thankYouTitle: 'Thank you',
    thankYou: (first) => (first ? `Thank you, ${first}!` : 'Thank you!'),
    willCall: (b) => `${b} will call you in about a minute, or when their calling hours start. The call may be from an AI assistant.`,
    willContact: (b) => `${b} has your enquiry and will get in touch soon.`,
    notFoundTitle: 'Form not available',
    notFoundMessage: 'This enquiry form is no longer available. Please contact the business directly.',
    tooLongTitle: 'Too long',
    tooLongMessage: 'Please shorten your message and try again.',
    waitTitle: 'Please wait',
    waitMessage: 'Too many enquiries were sent from here. Please try again in a few minutes.',
    poweredBy: 'Powered by CallPilot',
    privacy: 'Privacy',
    languageLabel: 'Language',
  },
  hi: {
    enquireTitle: 'पूछताछ',
    lede: 'अपनी जानकारी दें, हम लगभग एक मिनट में आपको कॉल करेंगे।',
    nameLabel: 'आपका नाम',
    phoneLabel: 'मोबाइल नंबर',
    interestLabel: 'आप किस चीज़ में रुचि रखते हैं?',
    optional: '(वैकल्पिक)',
    honeypotLabel: 'इसे खाली छोड़ें',
    submit: 'कॉल का अनुरोध करें',
    consent: (b) => `मैं अपनी पूछताछ के बारे में ${b} से कॉल प्राप्त करने के लिए सहमत हूँ (यह एक स्वचालित AI कॉल हो सकती है)।`,
    errName: 'कृपया अपना नाम दर्ज करें।',
    errPhone: 'कृपया एक मान्य मोबाइल नंबर दर्ज करें।',
    errConsent: 'कॉल प्राप्त करने की सहमति देने के लिए कृपया बॉक्स पर टिक करें।',
    thankYouTitle: 'धन्यवाद',
    thankYou: (first) => (first ? `धन्यवाद, ${first}!` : 'धन्यवाद!'),
    willCall: (b) => `${b} आपको लगभग एक मिनट में कॉल करेगा, या उनके कॉल करने का समय शुरू होने पर। यह कॉल किसी AI सहायक की ओर से हो सकती है।`,
    willContact: (b) => `${b} को आपकी पूछताछ मिल गई है, वे जल्द ही आपसे संपर्क करेंगे।`,
    notFoundTitle: 'फ़ॉर्म उपलब्ध नहीं है',
    notFoundMessage: 'यह पूछताछ फ़ॉर्म अब उपलब्ध नहीं है। कृपया सीधे व्यवसाय से संपर्क करें।',
    tooLongTitle: 'संदेश बहुत लंबा है',
    tooLongMessage: 'कृपया अपना संदेश छोटा करके फिर से कोशिश करें।',
    waitTitle: 'कृपया प्रतीक्षा करें',
    waitMessage: 'यहाँ से बहुत सारी पूछताछ भेजी गई हैं। कृपया कुछ मिनट बाद फिर से कोशिश करें।',
    poweredBy: 'CallPilot द्वारा संचालित',
    privacy: 'गोपनीयता',
    languageLabel: 'भाषा',
  },
  bn: {
    enquireTitle: 'জিজ্ঞাসা',
    lede: 'আপনার তথ্য দিন, আমরা প্রায় এক মিনিটের মধ্যে আপনাকে কল করব।',
    nameLabel: 'আপনার নাম',
    phoneLabel: 'মোবাইল নম্বর',
    interestLabel: 'আপনি কোন বিষয়ে আগ্রহী?',
    optional: '(ঐচ্ছিক)',
    honeypotLabel: 'এটি ফাঁকা রাখুন',
    submit: 'কল করার অনুরোধ করুন',
    consent: (b) => `আমি আমার জিজ্ঞাসা সম্পর্কে ${b} থেকে একটি কল পেতে সম্মত (এটি একটি স্বয়ংক্রিয় AI কল হতে পারে)।`,
    errName: 'অনুগ্রহ করে আপনার নাম লিখুন।',
    errPhone: 'অনুগ্রহ করে একটি সঠিক মোবাইল নম্বর লিখুন।',
    errConsent: 'কল পেতে সম্মতি দিতে অনুগ্রহ করে বাক্সে টিক দিন।',
    thankYouTitle: 'ধন্যবাদ',
    thankYou: (first) => (first ? `ধন্যবাদ, ${first}!` : 'ধন্যবাদ!'),
    willCall: (b) => `${b} প্রায় এক মিনিটের মধ্যে, অথবা তাদের কল করার সময় শুরু হলে, আপনাকে কল করবে। কলটি একজন AI সহকারীর কাছ থেকে আসতে পারে।`,
    willContact: (b) => `${b} আপনার জিজ্ঞাসা পেয়েছে এবং শীঘ্রই আপনার সঙ্গে যোগাযোগ করবে।`,
    notFoundTitle: 'ফর্মটি পাওয়া যাচ্ছে না',
    notFoundMessage: 'এই জিজ্ঞাসার ফর্মটি আর পাওয়া যাচ্ছে না। অনুগ্রহ করে সরাসরি ব্যবসার সঙ্গে যোগাযোগ করুন।',
    tooLongTitle: 'বার্তাটি খুব বড়',
    tooLongMessage: 'অনুগ্রহ করে বার্তাটি ছোট করে আবার চেষ্টা করুন।',
    waitTitle: 'অনুগ্রহ করে অপেক্ষা করুন',
    waitMessage: 'এখান থেকে অনেক বেশি জিজ্ঞাসা পাঠানো হয়েছে। অনুগ্রহ করে কয়েক মিনিট পরে আবার চেষ্টা করুন।',
    poweredBy: 'CallPilot দ্বারা চালিত',
    privacy: 'গোপনীয়তা',
    languageLabel: 'ভাষা',
  },
};

export interface StopStrings {
  title: string;
  heading: string;
  ledeHtml: string;
  doneHtml: (email: string) => string;
  limitedHtml: (email: string) => string;
  unavailableHtml: (email: string) => string;
  phoneLabel: string;
  submit: string;
  hint: string;
  otherWays: string;
  inCallTip: string;
  dndTipHtml: string;
  privacyHtml: string;
  errPhone: string;
  languageLabel: string;
}

const mail = (email: string) => `<a href="mailto:${email}">${email}</a>`;

export const STOP_STRINGS: L<StopStrings> = {
  en: {
    title: 'Stop calls to my number',
    heading: 'Stop AI calls to my number',
    ledeHtml: 'CallPilot is a service that businesses use to make AI phone calls to people who asked about their products. Enter your number below and <strong>no business using CallPilot</strong> will call it again.',
    doneHtml: (e) => `<p class="notice" role="status"><strong>Done.</strong> This number is on the CallPilot do-not-call list. No business using CallPilot will place AI calls to it from now on. Calls already in progress may still finish.</p>
<p>If a business keeps calling you, write to ${mail(e)} with the business name and the time of the call.</p>`,
    limitedHtml: (e) => `Too many requests from your connection. Please try again in an hour, or email ${mail(e)}.`,
    unavailableHtml: (e) => `This page is temporarily unavailable. Please email ${mail(e)} with your number and we will add it for you.`,
    phoneLabel: 'Your mobile number',
    submit: 'Stop calls to this number',
    hint: 'Indian numbers can be entered with or without +91. We store only a one-way hash of the number, used for nothing except blocking calls.',
    otherWays: 'Other ways to stop calls',
    inCallTip: 'During a call, say “don’t call me again”; that business will stop calling you.',
    dndTipHtml: 'Register on the National Customer Preference Register (DND) by sending <strong>START 0</strong> to 1909, or through your mobile operator’s app.',
    privacyHtml: 'See our <a href="/legal/privacy">Privacy Policy</a> for how we handle personal data.',
    errPhone: 'Please enter a valid mobile number, e.g. 98765 43210.',
    languageLabel: 'Language',
  },
  hi: {
    title: 'मेरे नंबर पर कॉल बंद करें',
    heading: 'मेरे नंबर पर AI कॉल बंद करें',
    ledeHtml: 'CallPilot एक सेवा है, जिससे व्यवसाय उन लोगों को AI फ़ोन कॉल करते हैं जिन्होंने उनके उत्पादों के बारे में पूछा था। नीचे अपना नंबर दर्ज करें, फिर <strong>CallPilot इस्तेमाल करने वाला कोई भी व्यवसाय</strong> उस नंबर पर दोबारा कॉल नहीं करेगा।',
    doneHtml: (e) => `<p class="notice" role="status"><strong>हो गया।</strong> यह नंबर CallPilot की “कॉल न करें” सूची में है। अब से CallPilot इस्तेमाल करने वाला कोई भी व्यवसाय इस नंबर पर AI कॉल नहीं करेगा। जो कॉल अभी चल रही हैं, वे पूरी हो सकती हैं।</p>
<p>अगर कोई व्यवसाय फिर भी आपको कॉल करता रहे, तो उस व्यवसाय का नाम और कॉल का समय लिखकर ${mail(e)} पर ईमेल करें।</p>`,
    limitedHtml: (e) => `आपके कनेक्शन से बहुत सारे अनुरोध आए हैं। कृपया एक घंटे बाद फिर से कोशिश करें, या ${mail(e)} पर ईमेल करें।`,
    unavailableHtml: (e) => `यह पेज अभी कुछ समय के लिए उपलब्ध नहीं है। कृपया अपना नंबर लिखकर ${mail(e)} पर ईमेल करें, हम उसे आपके लिए सूची में जोड़ देंगे।`,
    phoneLabel: 'आपका मोबाइल नंबर',
    submit: 'इस नंबर पर कॉल बंद करें',
    hint: 'भारतीय नंबर +91 के साथ या उसके बिना दर्ज कर सकते हैं। हम नंबर का सिर्फ़ एक-तरफ़ा हैश रखते हैं, जिसका इस्तेमाल केवल कॉल रोकने के लिए होता है।',
    otherWays: 'कॉल रोकने के दूसरे तरीके',
    inCallTip: 'कॉल के दौरान कहें “मुझे दोबारा कॉल मत करना”; वह व्यवसाय आपको कॉल करना बंद कर देगा।',
    dndTipHtml: '1909 पर <strong>START 0</strong> भेजकर, या अपने मोबाइल ऑपरेटर के ऐप से, नेशनल कस्टमर प्रेफ़रेंस रजिस्टर (DND) में रजिस्टर करें।',
    privacyHtml: 'हम निजी डेटा को कैसे संभालते हैं, यह जानने के लिए हमारी <a href="/legal/privacy">गोपनीयता नीति</a> (अंग्रेज़ी में) देखें।',
    errPhone: 'कृपया एक मान्य मोबाइल नंबर दर्ज करें, जैसे 98765 43210।',
    languageLabel: 'भाषा',
  },
  bn: {
    title: 'আমার নম্বরে কল বন্ধ করুন',
    heading: 'আমার নম্বরে AI কল বন্ধ করুন',
    ledeHtml: 'CallPilot এমন একটি পরিষেবা, যার মাধ্যমে ব্যবসাগুলি তাদের পণ্য সম্পর্কে জানতে চাওয়া মানুষদের AI ফোন কল করে। নীচে আপনার নম্বর লিখুন, তাহলে <strong>CallPilot ব্যবহারকারী কোনো ব্যবসা</strong> আর সেই নম্বরে কল করবে না।',
    doneHtml: (e) => `<p class="notice" role="status"><strong>হয়ে গেছে।</strong> এই নম্বরটি CallPilot-এর “কল করবেন না” তালিকায় আছে। এখন থেকে CallPilot ব্যবহারকারী কোনো ব্যবসা এই নম্বরে AI কল করবে না। যে কলগুলি এখন চলছে, সেগুলি শেষ হতে পারে।</p>
<p>কোনো ব্যবসা যদি তবুও আপনাকে কল করতে থাকে, তাহলে সেই ব্যবসার নাম আর কলের সময় লিখে ${mail(e)}-এ ইমেল করুন।</p>`,
    limitedHtml: (e) => `আপনার কানেকশন থেকে অনেক বেশি অনুরোধ এসেছে। অনুগ্রহ করে এক ঘণ্টা পরে আবার চেষ্টা করুন, অথবা ${mail(e)}-এ ইমেল করুন।`,
    unavailableHtml: (e) => `এই পৃষ্ঠাটি এখন সাময়িকভাবে পাওয়া যাচ্ছে না। অনুগ্রহ করে আপনার নম্বর লিখে ${mail(e)}-এ ইমেল করুন, আমরা আপনার হয়ে সেটি তালিকায় যোগ করে দেব।`,
    phoneLabel: 'আপনার মোবাইল নম্বর',
    submit: 'এই নম্বরে কল বন্ধ করুন',
    hint: 'ভারতীয় নম্বর +91 সহ বা ছাড়া লিখতে পারেন। আমরা নম্বরটির শুধু একটি একমুখী হ্যাশ রাখি, যা কেবল কল আটকানোর কাজেই লাগে।',
    otherWays: 'কল বন্ধ করার অন্যান্য উপায়',
    inCallTip: 'কলের সময় বলুন “আমাকে আর কল করবেন না”; সেই ব্যবসা আপনাকে কল করা বন্ধ করবে।',
    dndTipHtml: '1909-এ <strong>START 0</strong> পাঠিয়ে, অথবা আপনার মোবাইল অপারেটরের অ্যাপ থেকে, ন্যাশনাল কাস্টমার প্রেফারেন্স রেজিস্টারে (DND) নাম নথিভুক্ত করুন।',
    privacyHtml: 'আমরা ব্যক্তিগত তথ্য কীভাবে ব্যবহার করি, তা জানতে আমাদের <a href="/legal/privacy">গোপনীয়তা নীতি</a> (ইংরেজিতে) দেখুন।',
    errPhone: 'অনুগ্রহ করে একটি সঠিক মোবাইল নম্বর লিখুন, যেমন 98765 43210।',
    languageLabel: 'ভাষা',
  },
};

/** Navigation and footer of the legal-page layout (routes/legal.ts page()). */
export interface LegalChromeStrings {
  navLabel: string;
  privacy: string;
  terms: string;
  deleteAccount: string;
  stopCalls: string;
  questionsHtml: (email: string) => string;
  lastUpdated: string;
}

export const LEGAL_CHROME: L<LegalChromeStrings> = {
  en: {
    navLabel: 'Legal pages',
    privacy: 'Privacy Policy',
    terms: 'Terms of Service',
    deleteAccount: 'Delete your account',
    stopCalls: 'Stop calls to my number',
    questionsHtml: (e) => `Questions? Email ${mail(e)}.`,
    lastUpdated: 'Last updated',
  },
  hi: {
    navLabel: 'कानूनी पेज',
    privacy: 'गोपनीयता नीति',
    terms: 'सेवा की शर्तें',
    deleteAccount: 'अपना खाता हटाएँ',
    stopCalls: 'मेरे नंबर पर कॉल बंद करें',
    questionsHtml: (e) => `कोई सवाल है? ${mail(e)} पर ईमेल करें।`,
    lastUpdated: 'आख़िरी अपडेट',
  },
  bn: {
    navLabel: 'আইনি পৃষ্ঠা',
    privacy: 'গোপনীয়তা নীতি',
    terms: 'পরিষেবার শর্তাবলি',
    deleteAccount: 'আপনার অ্যাকাউন্ট মুছুন',
    stopCalls: 'আমার নম্বরে কল বন্ধ করুন',
    questionsHtml: (e) => `কোনো প্রশ্ন আছে? ${mail(e)}-এ ইমেল করুন।`,
    lastUpdated: 'সর্বশেষ আপডেট',
  },
};
