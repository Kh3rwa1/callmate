/**
 * Vertical call playbooks: the single source of what the AI employee asks, what "ready to buy"
 * means, how to handle common objections, the default WhatsApp follow-up per outcome and when to
 * call back, for each kind of business.
 *
 * Used by:
 *  - services/call_variables.ts  business_context (questions + ready-to-buy, only when allow-listed)
 *  - routes/voice.ts             default WhatsApp draft when the agent returned no whatsapp_message
 *  - services/prompt.ts          in-app chat system prompt
 *  - routes/playbooks.ts         GET /playbooks/current for the app's "Your call playbook" screen
 *
 * Text is English, Hindi and Bengali side by side. The AI-facing parts (call context, chat prompt)
 * use English; the app and WhatsApp drafts use the owner's / employee's language. Follow-up
 * templates use the placeholders {name} (lead's first name) and {business}.
 */
import { businessPageLang, type PageLang } from './page_lang';
import { callLang } from './voice_persona';

export type PlaybookLang = PageLang;
export type PlaybookId = 'education' | 'healthcare' | 'real_estate' | 'salon' | 'fitness' | 'general';
export type FollowupOutcome = 'hot' | 'warm' | 'callback' | 'not_interested';
export const FOLLOWUP_OUTCOMES: readonly FollowupOutcome[] = ['hot', 'warm', 'callback', 'not_interested'];

type L = Record<PlaybookLang, string>;

export interface Playbook {
  id: PlaybookId;
  name: L;
  /** 3-5 questions the employee works into the call, most important first. */
  qualifyingQuestions: L[];
  /**
   * What "ready to buy" means for this vertical. Maps onto the call output fields: such a lead
   * should come back with `temperature` hot, `intent` interested and a lead_score >= minScore.
   */
  readyToBuy: { description: L; temperature: 'hot'; intents: readonly ['interested']; minScore: number };
  objections: { objection: L; hint: L }[];
  /** Default WhatsApp follow-up per outcome, with {name} and {business}. */
  followups: Record<FollowupOutcome, L>;
  /** Suggested time to call back, IST hours [start, end). */
  callbackTiming: { hint: L; startHour: number; endHour: number };
}

const READY = { temperature: 'hot', intents: ['interested'], minScore: 75 } as const;

const CALLBACK: L = {
  en: 'Hi {name}, this is {business}. As you asked, we will call you back at the time you mentioned. Reply here if another time suits you better.',
  hi: 'नमस्ते {name}, मैं {business} से। आपके कहे अनुसार, हम आपके बताए समय पर आपको दोबारा कॉल करेंगे। कोई और समय बेहतर हो तो यहीं जवाब दें।',
  bn: 'নমস্কার {name}, {business} থেকে বলছি। আপনার কথামতো, আপনার বলা সময়ে আমরা আবার কল করব। অন্য সময় সুবিধা হলে এখানেই উত্তর দিন।',
};

export const PLAYBOOKS: Record<PlaybookId, Playbook> = {
  education: {
    id: 'education',
    name: { en: 'Coaching & education', hi: 'कोचिंग और शिक्षा', bn: 'কোচিং ও শিক্ষা' },
    qualifyingQuestions: [
      {
        en: 'Which class or exam is the student preparing for, and for which year?',
        hi: 'छात्र किस क्लास या परीक्षा की तैयारी कर रहा है, और किस साल के लिए?',
        bn: 'ছাত্র বা ছাত্রী কোন ক্লাস বা পরীক্ষার প্রস্তুতি নিচ্ছে, আর কোন বছরের জন্য?',
      },
      {
        en: 'Do they prefer online or classroom batches, and which timing suits them?',
        hi: 'उन्हें ऑनलाइन बैच पसंद है या क्लासरूम, और कौन-सा समय ठीक रहेगा?',
        bn: 'অনলাইন না ক্লাসরুম ব্যাচ পছন্দ, আর কোন সময়টা সুবিধাজনক?',
      },
      {
        en: 'Who decides on the admission – the student or a parent?',
        hi: 'एडमिशन का फ़ैसला कौन लेगा – छात्र या माता-पिता?',
        bn: 'ভর্তির সিদ্ধান্ত কে নেবেন – ছাত্র নিজে না অভিভাবক?',
      },
      {
        en: 'Is the fee within their budget, or do they need instalments?',
        hi: 'क्या फ़ीस उनके बजट में है, या उन्हें किस्तों में भुगतान चाहिए?',
        bn: 'ফি কি তাদের বাজেটের মধ্যে, নাকি কিস্তিতে দেওয়ার সুবিধা দরকার?',
      },
      {
        en: 'When would they like to attend a free demo class?',
        hi: 'वे फ़्री डेमो क्लास में कब आना चाहेंगे?',
        bn: 'তারা কবে ফ্রি ডেমো ক্লাসে আসতে চান?',
      },
    ],
    readyToBuy: {
      ...READY,
      description: {
        en: 'Knows the course and batch they want, the decision-maker is on board, and they agree to a demo class or ask how to pay the fee.',
        hi: 'उन्हें पता है कि कौन-सा कोर्स और बैच चाहिए, फ़ैसला लेने वाला सहमत है, और वे डेमो क्लास के लिए हाँ कहते हैं या फ़ीस भरने का तरीका पूछते हैं।',
        bn: 'কোন কোর্স আর ব্যাচ চান তা জানেন, যিনি সিদ্ধান্ত নেবেন তিনি রাজি, আর তারা ডেমো ক্লাসে আসতে রাজি হন বা ফি কীভাবে দেবেন জানতে চান।',
      },
    },
    objections: [
      {
        objection: { en: 'The fee is too high', hi: 'फ़ीस बहुत ज़्यादा है', bn: 'ফি খুব বেশি' },
        hint: {
          en: 'Mention instalments, scholarships or early-bird offers from the knowledge base; never invent a discount.',
          hi: 'नॉलेज में दी गई किस्तों, स्कॉलरशिप या अर्ली-बर्ड ऑफ़र का ज़िक्र करें; अपनी तरफ़ से कोई छूट न बनाएँ।',
          bn: 'নলেজে থাকা কিস্তি, স্কলারশিপ বা আর্লি-বার্ড অফারের কথা বলুন; নিজে থেকে কোনো ছাড় বানাবেন না।',
        },
      },
      {
        objection: { en: 'I need to ask my parents', hi: 'मुझे माता-पिता से पूछना होगा', bn: 'বাবা-মাকে জিজ্ঞেস করতে হবে' },
        hint: {
          en: 'Offer a call back when the parent is free, or invite both to the demo class.',
          hi: 'जब माता-पिता फ़्री हों तब कॉल बैक का समय तय करें, या दोनों को डेमो क्लास में बुलाएँ।',
          bn: 'অভিভাবক যখন ফাঁকা থাকবেন তখন আবার কল করার প্রস্তাব দিন, বা দুজনকেই ডেমো ক্লাসে আসতে বলুন।',
        },
      },
      {
        objection: { en: 'I am comparing other institutes', hi: 'मैं दूसरे इंस्टीट्यूट भी देख रहा हूँ', bn: 'অন্য ইনস্টিটিউটও দেখছি' },
        hint: {
          en: 'Ask what matters most to them (results, faculty, batch size) and share the matching facts.',
          hi: 'पूछें कि उनके लिए सबसे ज़रूरी क्या है (रिज़ल्ट, फ़ैकल्टी, बैच का साइज़), और उसी से जुड़ी जानकारी दें।',
          bn: 'জিজ্ঞেস করুন তাদের কাছে কোনটা সবচেয়ে জরুরি (রেজাল্ট, শিক্ষক, ব্যাচের আকার), তারপর সেই অনুযায়ী তথ্য দিন।',
        },
      },
    ],
    followups: {
      hot: {
        en: 'Hi {name}, thanks for speaking with {business}! As discussed, here are the details of your demo class. Reply here to confirm a time that suits you.',
        hi: 'नमस्ते {name}, {business} से बात करने के लिए धन्यवाद! जैसा तय हुआ, आपकी डेमो क्लास की जानकारी यहाँ है। अपना सुविधाजनक समय कन्फ़र्म करने के लिए यहीं जवाब दें।',
        bn: 'নমস্কার {name}, {business}-এর সঙ্গে কথা বলার জন্য ধন্যবাদ! কথামতো আপনার ডেমো ক্লাসের তথ্য এখানে দিলাম। আপনার সুবিধামতো সময় নিশ্চিত করতে এখানেই উত্তর দিন।',
      },
      warm: {
        en: 'Hi {name}, thanks for your interest in {business}. Sharing our course and batch details here – reply with any questions, or to book a free demo class.',
        hi: 'नमस्ते {name}, {business} में रुचि दिखाने के लिए धन्यवाद। हमारे कोर्स और बैच की जानकारी यहाँ भेज रहे हैं – कोई सवाल हो या फ़्री डेमो क्लास बुक करनी हो, तो यहीं जवाब दें।',
        bn: 'নমস্কার {name}, {business}-এ আগ্রহ দেখানোর জন্য ধন্যবাদ। আমাদের কোর্স আর ব্যাচের তথ্য এখানে পাঠালাম – কোনো প্রশ্ন থাকলে বা ফ্রি ডেমো ক্লাস বুক করতে চাইলে এখানেই উত্তর দিন।',
      },
      callback: CALLBACK,
      not_interested: {
        en: 'Hi {name}, thanks for your time today. If you need coaching later, just reply here and {business} will be happy to help.',
        hi: 'नमस्ते {name}, आज समय देने के लिए धन्यवाद। आगे कभी कोचिंग की ज़रूरत हो तो बस यहाँ जवाब दें, {business} ख़ुशी से मदद करेगा।',
        bn: 'নমস্কার {name}, আজ সময় দেওয়ার জন্য ধন্যবাদ। পরে কখনও কোচিংয়ের দরকার হলে এখানে উত্তর দিন, {business} সাহায্য করতে পেরে খুশি হবে।',
      },
    },
    callbackTiming: {
      startHour: 17,
      endHour: 20,
      hint: {
        en: 'Evenings, 5–8 pm, after school or college; weekends also work for parents.',
        hi: 'शाम 5–8 बजे, स्कूल या कॉलेज के बाद; माता-पिता के लिए वीकेंड भी ठीक रहता है।',
        bn: 'সন্ধ্যা 5–8টা, স্কুল বা কলেজের পরে; অভিভাবকদের জন্য সপ্তাহান্তও ভালো।',
      },
    },
  },

  healthcare: {
    id: 'healthcare',
    name: { en: 'Clinic & healthcare', hi: 'क्लिनिक और स्वास्थ्य', bn: 'ক্লিনিক ও স্বাস্থ্য' },
    qualifyingQuestions: [
      {
        en: 'What health concern or treatment are they asking about?',
        hi: 'वे किस स्वास्थ्य समस्या या इलाज के बारे में पूछ रहे हैं?',
        bn: 'তারা কোন স্বাস্থ্য সমস্যা বা চিকিৎসার ব্যাপারে জানতে চাইছেন?',
      },
      {
        en: 'Is it urgent? If it sounds like an emergency, tell them to go to the nearest hospital or call 108.',
        hi: 'क्या यह ज़रूरी है? अगर इमरजेंसी लगे, तो उन्हें नज़दीकी अस्पताल जाने या 108 पर कॉल करने को कहें।',
        bn: 'এটা কি জরুরি? জরুরি অবস্থা মনে হলে তাদের নিকটতম হাসপাতালে যেতে বা 108-এ কল করতে বলুন।',
      },
      {
        en: 'Is the appointment for themselves or a family member, and do they have a preferred doctor?',
        hi: 'अपॉइंटमेंट उनके लिए है या परिवार के किसी सदस्य के लिए, और क्या वे किसी ख़ास डॉक्टर से मिलना चाहते हैं?',
        bn: 'অ্যাপয়েন্টমেন্টটা নিজের জন্য না পরিবারের কারও জন্য, আর কোনো পছন্দের ডাক্তার আছেন কি?',
      },
      {
        en: 'Which day and time suits them for a visit?',
        hi: 'उन्हें किस दिन और किस समय आना ठीक रहेगा?',
        bn: 'কোন দিন আর কোন সময়ে আসতে সুবিধা হবে?',
      },
    ],
    readyToBuy: {
      ...READY,
      description: {
        en: 'Has a clear need and agrees to book an appointment, or asks for the earliest available slot.',
        hi: 'ज़रूरत साफ़ है और वे अपॉइंटमेंट बुक करने को तैयार हैं, या सबसे जल्दी मिलने वाला स्लॉट पूछते हैं।',
        bn: 'প্রয়োজন স্পষ্ট আর তারা অ্যাপয়েন্টমেন্ট বুক করতে রাজি, বা সবচেয়ে তাড়াতাড়ি পাওয়া যায় এমন স্লট জানতে চান।',
      },
    },
    objections: [
      {
        objection: { en: 'What does the consultation cost?', hi: 'कंसल्टेशन की फ़ीस कितनी है?', bn: 'কনসালটেশন ফি কত?' },
        hint: {
          en: 'Share the fee only if it is in the knowledge base; otherwise offer to have the clinic confirm it.',
          hi: 'फ़ीस तभी बताएँ जब वह नॉलेज में हो; नहीं तो कहें कि क्लिनिक से कन्फ़र्म करवा देंगे।',
          bn: 'ফি তখনই বলুন যখন সেটা নলেজে আছে; না হলে বলুন ক্লিনিক থেকে নিশ্চিত করে জানানো হবে।',
        },
      },
      {
        objection: { en: 'I will come if it gets worse', hi: 'तबीयत ज़्यादा ख़राब हुई तो आऊँगा', bn: 'শরীর বেশি খারাপ হলে আসব' },
        hint: {
          en: 'Gently explain that an early check-up helps, without giving medical advice.',
          hi: 'प्यार से समझाएँ कि जल्दी जाँच करवाना फ़ायदेमंद है, पर कोई मेडिकल सलाह न दें।',
          bn: 'নরমভাবে বোঝান যে আগে থেকে দেখিয়ে নেওয়া ভালো, তবে কোনো চিকিৎসা-পরামর্শ দেবেন না।',
        },
      },
      {
        objection: { en: 'The timings do not suit me', hi: 'समय मेरे लिए ठीक नहीं है', bn: 'সময়টা আমার সুবিধা হচ্ছে না' },
        hint: {
          en: 'Offer other slots or days when the clinic is open.',
          hi: 'क्लिनिक के खुले रहने के दूसरे स्लॉट या दिन बताएँ।',
          bn: 'ক্লিনিক খোলা থাকে এমন অন্য স্লট বা দিনের কথা বলুন।',
        },
      },
    ],
    followups: {
      hot: {
        en: 'Hi {name}, thanks for speaking with {business}. Please reply here to confirm your appointment time, and we will share the address and what to bring.',
        hi: 'नमस्ते {name}, {business} से बात करने के लिए धन्यवाद। अपनी अपॉइंटमेंट का समय कन्फ़र्म करने के लिए यहाँ जवाब दें, हम पता और साथ लाने वाली चीज़ें भेज देंगे।',
        bn: 'নমস্কার {name}, {business}-এর সঙ্গে কথা বলার জন্য ধন্যবাদ। অ্যাপয়েন্টমেন্টের সময় নিশ্চিত করতে এখানে উত্তর দিন, আমরা ঠিকানা আর কী কী আনতে হবে তা পাঠিয়ে দেব।',
      },
      warm: {
        en: 'Hi {name}, thanks for contacting {business}. Reply here whenever you would like to book an appointment, and we will find a slot that suits you.',
        hi: 'नमस्ते {name}, {business} से संपर्क करने के लिए धन्यवाद। जब भी अपॉइंटमेंट बुक करना हो, यहाँ जवाब दें, हम आपके लिए सही समय ढूँढ देंगे।',
        bn: 'নমস্কার {name}, {business}-এর সঙ্গে যোগাযোগ করার জন্য ধন্যবাদ। যখনই অ্যাপয়েন্টমেন্ট বুক করতে চান, এখানে উত্তর দিন, আমরা আপনার সুবিধামতো সময় খুঁজে দেব।',
      },
      callback: CALLBACK,
      not_interested: {
        en: 'Hi {name}, thanks for your time. If you ever need an appointment, just reply here and {business} will help. Take care!',
        hi: 'नमस्ते {name}, समय देने के लिए धन्यवाद। जब भी अपॉइंटमेंट चाहिए, बस यहाँ जवाब दें, {business} मदद करेगा। अपना ख़याल रखें!',
        bn: 'নমস্কার {name}, সময় দেওয়ার জন্য ধন্যবাদ। কখনও অ্যাপয়েন্টমেন্ট লাগলে এখানে উত্তর দিন, {business} সাহায্য করবে। ভালো থাকবেন!',
      },
    },
    callbackTiming: {
      startHour: 10,
      endHour: 13,
      hint: {
        en: 'Late morning, 10 am–1 pm, when the clinic can confirm slots; avoid late evenings.',
        hi: 'सुबह 10 से दोपहर 1 बजे के बीच, जब क्लिनिक स्लॉट कन्फ़र्म कर सके; देर शाम कॉल न करें।',
        bn: 'সকাল 10টা থেকে দুপুর 1টার মধ্যে, যখন ক্লিনিক স্লট নিশ্চিত করতে পারে; সন্ধ্যার পরে কল করবেন না।',
      },
    },
  },

  real_estate: {
    id: 'real_estate',
    name: { en: 'Real estate', hi: 'रियल एस्टेट', bn: 'রিয়েল এস্টেট' },
    qualifyingQuestions: [
      {
        en: 'Are they buying or renting, and which configuration do they need (e.g. 2 BHK, 3 BHK)?',
        hi: 'वे ख़रीदना चाहते हैं या किराए पर लेना, और कौन-सा कॉन्फ़िगरेशन चाहिए (जैसे 2 BHK, 3 BHK)?',
        bn: 'তারা কিনতে চান না ভাড়া নিতে, আর কোন কনফিগারেশন দরকার (যেমন 2 BHK, 3 BHK)?',
      },
      {
        en: 'What is their budget, and will they need a home loan?',
        hi: 'उनका बजट कितना है, और क्या उन्हें होम लोन चाहिए होगा?',
        bn: 'তাদের বাজেট কত, আর হোম লোন লাগবে কি?',
      },
      {
        en: 'Which locations do they prefer?',
        hi: 'उन्हें कौन-सी लोकेशन पसंद है?',
        bn: 'কোন এলাকা তাদের পছন্দ?',
      },
      {
        en: 'When do they plan to buy or move in?',
        hi: 'वे कब तक ख़रीदना या शिफ़्ट होना चाहते हैं?',
        bn: 'কবে নাগাদ কিনতে বা উঠতে চান?',
      },
      {
        en: 'When can they visit the site?',
        hi: 'वे साइट विज़िट के लिए कब आ सकते हैं?',
        bn: 'কবে সাইট ভিজিটে আসতে পারবেন?',
      },
    ],
    readyToBuy: {
      ...READY,
      description: {
        en: 'Budget and location match what is available, they plan to buy within 3 months, and they agree to a site visit.',
        hi: 'बजट और लोकेशन उपलब्ध प्रॉपर्टी से मेल खाते हैं, वे 3 महीने के अंदर ख़रीदना चाहते हैं, और साइट विज़िट के लिए तैयार हैं।',
        bn: 'বাজেট আর এলাকা হাতে থাকা প্রপার্টির সঙ্গে মেলে, তারা 3 মাসের মধ্যে কিনতে চান, আর সাইট ভিজিটে রাজি।',
      },
    },
    objections: [
      {
        objection: { en: 'The price is above my budget', hi: 'क़ीमत मेरे बजट से ज़्यादा है', bn: 'দাম আমার বাজেটের বাইরে' },
        hint: {
          en: 'Ask how flexible the budget is and mention other units or payment plans from the knowledge base.',
          hi: 'पूछें कि बजट में कितनी गुंजाइश है, और नॉलेज में दी गई दूसरी यूनिट या पेमेंट प्लान बताएँ।',
          bn: 'বাজেটে কতটা নড়চড় সম্ভব জিজ্ঞেস করুন, আর নলেজে থাকা অন্য ইউনিট বা পেমেন্ট প্ল্যানের কথা বলুন।',
        },
      },
      {
        objection: { en: 'I am just looking for now', hi: 'अभी बस देख रहा हूँ', bn: 'এখন শুধু দেখছি' },
        hint: {
          en: 'Offer to send the brochure on WhatsApp and suggest a no-obligation site visit.',
          hi: 'WhatsApp पर ब्रोशर भेजने की पेशकश करें और बिना किसी बाध्यता के साइट विज़िट का सुझाव दें।',
          bn: 'WhatsApp-এ ব্রোশিওর পাঠানোর প্রস্তাব দিন আর কোনো বাধ্যবাধকতা ছাড়াই সাইট ভিজিটের কথা বলুন।',
        },
      },
      {
        objection: { en: 'I need to discuss with my family', hi: 'परिवार से बात करनी होगी', bn: 'পরিবারের সঙ্গে কথা বলতে হবে' },
        hint: {
          en: 'Invite the family to the site visit and offer a weekend slot.',
          hi: 'परिवार को भी साइट विज़िट पर बुलाएँ और वीकेंड का स्लॉट ऑफ़र करें।',
          bn: 'পরিবারকেও সাইট ভিজিটে আসতে বলুন আর সপ্তাহান্তের স্লট অফার করুন।',
        },
      },
    ],
    followups: {
      hot: {
        en: 'Hi {name}, thanks for speaking with {business}! Sharing the property details and location here. Reply to confirm your site visit time.',
        hi: 'नमस्ते {name}, {business} से बात करने के लिए धन्यवाद! प्रॉपर्टी की जानकारी और लोकेशन यहाँ भेज रहे हैं। साइट विज़िट का समय कन्फ़र्म करने के लिए जवाब दें।',
        bn: 'নমস্কার {name}, {business}-এর সঙ্গে কথা বলার জন্য ধন্যবাদ! প্রপার্টির তথ্য আর লোকেশন এখানে পাঠালাম। সাইট ভিজিটের সময় নিশ্চিত করতে উত্তর দিন।',
      },
      warm: {
        en: 'Hi {name}, thanks for your interest in {business}. Here are the options that match what you told us. Reply here to see more or plan a visit.',
        hi: 'नमस्ते {name}, {business} में रुचि दिखाने के लिए धन्यवाद। आपने जो बताया, उससे मिलते-जुलते विकल्प यहाँ हैं। और देखने या विज़िट प्लान करने के लिए यहाँ जवाब दें।',
        bn: 'নমস্কার {name}, {business}-এ আগ্রহ দেখানোর জন্য ধন্যবাদ। আপনি যা বলেছেন, তার সঙ্গে মেলে এমন বিকল্পগুলো এখানে দিলাম। আরও দেখতে বা ভিজিটের পরিকল্পনা করতে এখানে উত্তর দিন।',
      },
      callback: CALLBACK,
      not_interested: {
        en: 'Hi {name}, thanks for your time. If you start looking for a property later, reply here and {business} will share the latest options.',
        hi: 'नमस्ते {name}, समय देने के लिए धन्यवाद। आगे कभी प्रॉपर्टी ढूँढें तो यहाँ जवाब दें, {business} आपको नए विकल्प भेजेगा।',
        bn: 'নমস্কার {name}, সময় দেওয়ার জন্য ধন্যবাদ। পরে কখনও প্রপার্টি খুঁজলে এখানে উত্তর দিন, {business} নতুন বিকল্পগুলো পাঠিয়ে দেবে।',
      },
    },
    callbackTiming: {
      startHour: 18,
      endHour: 20,
      hint: {
        en: 'Weekday evenings, 6–8 pm, or weekend mornings to plan site visits.',
        hi: 'हफ़्ते के दिनों में शाम 6–8 बजे, या साइट विज़िट प्लान करने के लिए वीकेंड की सुबह।',
        bn: 'সপ্তাহের দিনে সন্ধ্যা 6–8টা, অথবা সাইট ভিজিটের পরিকল্পনার জন্য সপ্তাহান্তের সকাল।',
      },
    },
  },

  salon: {
    id: 'salon',
    name: { en: 'Salon & spa', hi: 'सैलून और स्पा', bn: 'সেলুন ও স্পা' },
    qualifyingQuestions: [
      {
        en: 'Which service are they looking for (haircut, colour, facial, bridal, spa)?',
        hi: 'उन्हें कौन-सी सर्विस चाहिए (हेयरकट, कलर, फ़ेशियल, ब्राइडल, स्पा)?',
        bn: 'কোন পরিষেবা চান (হেয়ারকাট, কালার, ফেসিয়াল, ব্রাইডাল, স্পা)?',
      },
      {
        en: 'Which day and time would they like to come?',
        hi: 'वे किस दिन और किस समय आना चाहेंगे?',
        bn: 'কোন দিন আর কোন সময়ে আসতে চান?',
      },
      {
        en: 'Do they have a preferred stylist or therapist?',
        hi: 'क्या वे किसी ख़ास स्टाइलिस्ट या थेरेपिस्ट को पसंद करते हैं?',
        bn: 'কোনো পছন্দের স্টাইলিস্ট বা থেরাপিস্ট আছেন কি?',
      },
      {
        en: 'Is it for a special occasion, like a wedding or a party?',
        hi: 'क्या यह किसी ख़ास मौक़े के लिए है, जैसे शादी या पार्टी?',
        bn: 'এটা কি কোনো বিশেষ অনুষ্ঠানের জন্য, যেমন বিয়ে বা পার্টি?',
      },
    ],
    readyToBuy: {
      ...READY,
      description: {
        en: 'Knows the service they want and agrees to book a specific slot.',
        hi: 'उन्हें पता है कि कौन-सी सर्विस चाहिए, और वे एक तय स्लॉट बुक करने को तैयार हैं।',
        bn: 'কোন পরিষেবা চান তা জানেন, আর একটা নির্দিষ্ট স্লট বুক করতে রাজি।',
      },
    },
    objections: [
      {
        objection: { en: 'It is too expensive', hi: 'यह बहुत महँगा है', bn: 'খুব দামি' },
        hint: {
          en: 'Mention packages or current offers from the knowledge base.',
          hi: 'नॉलेज में दिए पैकेज या चल रहे ऑफ़र बताएँ।',
          bn: 'নলেজে থাকা প্যাকেজ বা চলতি অফারের কথা বলুন।',
        },
      },
      {
        objection: { en: 'I will just walk in when I am free', hi: 'फ़्री होकर सीधे आ जाऊँगा', bn: 'ফাঁকা হলে সরাসরি চলে আসব' },
        hint: {
          en: 'Explain that booking avoids waiting, and offer the next free slot.',
          hi: 'बताएँ कि बुकिंग से इंतज़ार नहीं करना पड़ता, और अगला ख़ाली स्लॉट ऑफ़र करें।',
          bn: 'বলুন যে বুক করলে অপেক্ষা করতে হয় না, আর পরের খালি স্লটটা অফার করুন।',
        },
      },
      {
        objection: { en: 'I already have a regular salon', hi: 'मेरा पहले से एक सैलून है', bn: 'আমার একটা নিয়মিত সেলুন আছে' },
        hint: {
          en: 'Mention a first-visit offer only if the knowledge base has one.',
          hi: 'पहली विज़िट का ऑफ़र तभी बताएँ जब वह नॉलेज में हो।',
          bn: 'প্রথমবারের অফার তখনই বলুন যখন সেটা নলেজে আছে।',
        },
      },
    ],
    followups: {
      hot: {
        en: 'Hi {name}, thanks for booking with {business}! Reply here to confirm your appointment, and let us know if you need to change the time.',
        hi: 'नमस्ते {name}, {business} में बुकिंग के लिए धन्यवाद! अपनी अपॉइंटमेंट कन्फ़र्म करने के लिए यहाँ जवाब दें, और समय बदलना हो तो बताएँ।',
        bn: 'নমস্কার {name}, {business}-এ বুক করার জন্য ধন্যবাদ! অ্যাপয়েন্টমেন্ট নিশ্চিত করতে এখানে উত্তর দিন, আর সময় বদলাতে হলে জানান।',
      },
      warm: {
        en: 'Hi {name}, thanks for asking about {business}. Here are our services and prices. Reply here whenever you would like to book a slot.',
        hi: 'नमस्ते {name}, {business} के बारे में पूछने के लिए धन्यवाद। हमारी सर्विस और रेट यहाँ हैं। जब भी स्लॉट बुक करना हो, यहाँ जवाब दें।',
        bn: 'নমস্কার {name}, {business} সম্পর্কে জানতে চাওয়ার জন্য ধন্যবাদ। আমাদের পরিষেবা আর দাম এখানে দিলাম। যখনই স্লট বুক করতে চান, এখানে উত্তর দিন।',
      },
      callback: CALLBACK,
      not_interested: {
        en: 'Hi {name}, thanks for your time. Whenever you need a salon visit, reply here and {business} will book you in.',
        hi: 'नमस्ते {name}, समय देने के लिए धन्यवाद। जब भी सैलून आना हो, यहाँ जवाब दें, {business} आपकी बुकिंग कर देगा।',
        bn: 'নমস্কার {name}, সময় দেওয়ার জন্য ধন্যবাদ। যখনই সেলুনে আসতে চান, এখানে উত্তর দিন, {business} আপনার বুকিং করে দেবে।',
      },
    },
    callbackTiming: {
      startHour: 11,
      endHour: 16,
      hint: {
        en: 'Late morning to afternoon, 11 am–4 pm, before the evening rush.',
        hi: 'सुबह 11 से शाम 4 बजे के बीच, शाम की भीड़ से पहले।',
        bn: 'বেলা 11টা থেকে বিকেল 4টার মধ্যে, সন্ধ্যার ভিড়ের আগে।',
      },
    },
  },

  fitness: {
    id: 'fitness',
    name: { en: 'Gym & fitness', hi: 'जिम और फ़िटनेस', bn: 'জিম ও ফিটনেস' },
    qualifyingQuestions: [
      {
        en: 'What is their fitness goal – weight loss, muscle gain, general fitness or a sport?',
        hi: 'उनका फ़िटनेस लक्ष्य क्या है – वज़न घटाना, मसल बनाना, फ़िट रहना या कोई खेल?',
        bn: 'তাদের ফিটনেসের লক্ষ্য কী – ওজন কমানো, পেশি বাড়ানো, সাধারণ ফিটনেস না কোনো খেলা?',
      },
      {
        en: 'Have they trained at a gym before?',
        hi: 'क्या उन्होंने पहले किसी जिम में ट्रेनिंग की है?',
        bn: 'আগে কখনও জিমে ট্রেনিং করেছেন কি?',
      },
      {
        en: 'At what time of day would they come to work out?',
        hi: 'वे दिन में किस समय वर्कआउट के लिए आएँगे?',
        bn: 'দিনের কোন সময়ে ওয়ার্কআউট করতে আসবেন?',
      },
      {
        en: 'Are they interested in personal training, or a monthly or yearly membership?',
        hi: 'क्या उन्हें पर्सनल ट्रेनिंग में रुचि है, या मंथली या सालाना मेंबरशिप में?',
        bn: 'পার্সোনাল ট্রেনিং চান, নাকি মাসিক বা বার্ষিক মেম্বারশিপ?',
      },
      {
        en: 'When can they come for a free trial session?',
        hi: 'वे फ़्री ट्रायल सेशन के लिए कब आ सकते हैं?',
        bn: 'কবে ফ্রি ট্রায়াল সেশনে আসতে পারবেন?',
      },
    ],
    readyToBuy: {
      ...READY,
      description: {
        en: 'Has a clear goal and agrees to a trial session, or asks about joining fees and plans.',
        hi: 'लक्ष्य साफ़ है और वे ट्रायल सेशन के लिए हाँ कहते हैं, या जॉइनिंग फ़ीस और प्लान के बारे में पूछते हैं।',
        bn: 'লক্ষ্য স্পষ্ট আর তারা ট্রায়াল সেশনে রাজি হন, বা ভর্তির ফি আর প্ল্যান সম্পর্কে জানতে চান।',
      },
    },
    objections: [
      {
        objection: { en: 'Membership is too expensive', hi: 'मेंबरशिप बहुत महँगी है', bn: 'মেম্বারশিপ খুব দামি' },
        hint: {
          en: 'Compare monthly and yearly plans and mention offers from the knowledge base.',
          hi: 'मंथली और सालाना प्लान की तुलना करें, और नॉलेज में दिए ऑफ़र बताएँ।',
          bn: 'মাসিক আর বার্ষিক প্ল্যান তুলনা করে দেখান, আর নলেজে থাকা অফারের কথা বলুন।',
        },
      },
      {
        objection: { en: 'I do not have time', hi: 'मेरे पास समय नहीं है', bn: 'আমার সময় নেই' },
        hint: {
          en: 'Mention early-morning or late-evening hours and short workouts.',
          hi: 'सुबह जल्दी या देर शाम के समय और छोटे वर्कआउट के बारे में बताएँ।',
          bn: 'ভোরবেলা বা রাতের দিকের সময় আর ছোট ওয়ার্কআউটের কথা বলুন।',
        },
      },
      {
        objection: { en: 'I will start next month', hi: 'अगले महीने से शुरू करूँगा', bn: 'পরের মাস থেকে শুরু করব' },
        hint: {
          en: 'Suggest a free trial this week so they can see the gym first.',
          hi: 'इसी हफ़्ते फ़्री ट्रायल का सुझाव दें, ताकि वे पहले जिम देख लें।',
          bn: 'এই সপ্তাহেই একটা ফ্রি ট্রায়ালের কথা বলুন, যাতে আগে জিমটা দেখে নিতে পারেন।',
        },
      },
    ],
    followups: {
      hot: {
        en: 'Hi {name}, great speaking with you! Your trial session at {business} is set. Reply here to confirm the time, and bring comfortable clothes and water.',
        hi: 'नमस्ते {name}, आपसे बात करके अच्छा लगा! {business} में आपका ट्रायल सेशन तय है। समय कन्फ़र्म करने के लिए यहाँ जवाब दें, और आरामदायक कपड़े और पानी साथ लाएँ।',
        bn: 'নমস্কার {name}, আপনার সঙ্গে কথা বলে ভালো লাগল! {business}-এ আপনার ট্রায়াল সেশন ঠিক হয়েছে। সময় নিশ্চিত করতে এখানে উত্তর দিন, আর আরামদায়ক পোশাক ও জল সঙ্গে আনবেন।',
      },
      warm: {
        en: 'Hi {name}, thanks for your interest in {business}. Here are our membership plans. Reply here to book a free trial session.',
        hi: 'नमस्ते {name}, {business} में रुचि दिखाने के लिए धन्यवाद। हमारे मेंबरशिप प्लान यहाँ हैं। फ़्री ट्रायल सेशन बुक करने के लिए यहाँ जवाब दें।',
        bn: 'নমস্কার {name}, {business}-এ আগ্রহ দেখানোর জন্য ধন্যবাদ। আমাদের মেম্বারশিপ প্ল্যান এখানে দিলাম। ফ্রি ট্রায়াল সেশন বুক করতে এখানে উত্তর দিন।',
      },
      callback: CALLBACK,
      not_interested: {
        en: 'Hi {name}, thanks for your time. Whenever you are ready to start training, reply here and {business} will help you begin.',
        hi: 'नमस्ते {name}, समय देने के लिए धन्यवाद। जब भी ट्रेनिंग शुरू करने के लिए तैयार हों, यहाँ जवाब दें, {business} शुरुआत में आपकी मदद करेगा।',
        bn: 'নমস্কার {name}, সময় দেওয়ার জন্য ধন্যবাদ। যখনই ট্রেনিং শুরু করতে তৈরি হবেন, এখানে উত্তর দিন, {business} শুরু করতে সাহায্য করবে।',
      },
    },
    callbackTiming: {
      startHour: 10,
      endHour: 12,
      hint: {
        en: 'Mid-morning, 10 am–12 pm, or early evening, 5–7 pm – outside peak workout hours.',
        hi: 'सुबह 10–12 बजे या शाम 5–7 बजे – वर्कआउट की भीड़ वाले समय से बाहर।',
        bn: 'সকাল 10–12টা বা সন্ধ্যা 5–7টা – ওয়ার্কআউটের ভিড়ের সময় বাদ দিয়ে।',
      },
    },
  },

  general: {
    id: 'general',
    name: { en: 'General', hi: 'सामान्य', bn: 'সাধারণ' },
    qualifyingQuestions: [
      {
        en: 'What product or service are they interested in?',
        hi: 'उन्हें किस प्रोडक्ट या सर्विस में रुचि है?',
        bn: 'কোন পণ্য বা পরিষেবায় আগ্রহী?',
      },
      {
        en: 'What do they need it for, and by when?',
        hi: 'उन्हें यह किस काम के लिए और कब तक चाहिए?',
        bn: 'এটা কী কাজে আর কবের মধ্যে দরকার?',
      },
      {
        en: 'Do they have a budget in mind?',
        hi: 'क्या उनके मन में कोई बजट है?',
        bn: 'মনে কোনো বাজেট আছে কি?',
      },
      {
        en: 'Who else is involved in the decision?',
        hi: 'फ़ैसले में और कौन शामिल है?',
        bn: 'সিদ্ধান্তে আর কে কে আছেন?',
      },
    ],
    readyToBuy: {
      ...READY,
      description: {
        en: 'Has a clear need and timeline, the budget fits, and they ask for the next step (a quote, a visit or a booking).',
        hi: 'ज़रूरत और समय-सीमा साफ़ है, बजट ठीक बैठता है, और वे अगला कदम पूछते हैं (कोटेशन, विज़िट या बुकिंग)।',
        bn: 'প্রয়োজন আর সময়সীমা স্পষ্ট, বাজেট মেলে, আর তারা পরের ধাপ জানতে চান (কোটেশন, ভিজিট বা বুকিং)।',
      },
    },
    objections: [
      {
        objection: { en: 'It is too expensive', hi: 'यह बहुत महँगा है', bn: 'খুব দামি' },
        hint: {
          en: 'Explain the value and mention offers or options from the knowledge base; never invent prices.',
          hi: 'समझाएँ कि इसमें क्या फ़ायदा है, और नॉलेज में दिए ऑफ़र या विकल्प बताएँ; कभी अपनी तरफ़ से दाम न बनाएँ।',
          bn: 'এতে কী সুবিধা তা বোঝান, আর নলেজে থাকা অফার বা বিকল্পের কথা বলুন; নিজে থেকে কখনও দাম বানাবেন না।',
        },
      },
      {
        objection: { en: 'Just send me the details', hi: 'मुझे डिटेल भेज दीजिए', bn: 'আমাকে বিস্তারিত পাঠিয়ে দিন' },
        hint: {
          en: 'Agree to send the details on WhatsApp, and ask one question to understand their need.',
          hi: 'WhatsApp पर डिटेल भेजने के लिए हाँ कहें, और उनकी ज़रूरत समझने के लिए एक सवाल पूछें।',
          bn: 'WhatsApp-এ বিস্তারিত পাঠাতে রাজি হন, আর তাদের প্রয়োজন বুঝতে একটা প্রশ্ন করুন।',
        },
      },
      {
        objection: { en: 'I am busy right now', hi: 'मैं अभी व्यस्त हूँ', bn: 'আমি এখন ব্যস্ত' },
        hint: {
          en: 'Ask for a better time and schedule a call back.',
          hi: 'बेहतर समय पूछें और कॉल बैक तय करें।',
          bn: 'সুবিধামতো সময় জিজ্ঞেস করে আবার কল করার সময় ঠিক করুন।',
        },
      },
    ],
    followups: {
      hot: {
        en: 'Hi {name}, thanks for speaking with {business}! As discussed, here are the details for your next step. Reply here to confirm.',
        hi: 'नमस्ते {name}, {business} से बात करने के लिए धन्यवाद! जैसा तय हुआ, अगले कदम की जानकारी यहाँ है। कन्फ़र्म करने के लिए यहाँ जवाब दें।',
        bn: 'নমস্কার {name}, {business}-এর সঙ্গে কথা বলার জন্য ধন্যবাদ! কথামতো পরের ধাপের তথ্য এখানে দিলাম। নিশ্চিত করতে এখানে উত্তর দিন।',
      },
      warm: {
        en: 'Hi {name}, thanks for your interest in {business}. Sharing the details here – reply with any questions.',
        hi: 'नमस्ते {name}, {business} में रुचि दिखाने के लिए धन्यवाद। जानकारी यहाँ भेज रहे हैं – कोई सवाल हो तो यहीं जवाब दें।',
        bn: 'নমস্কার {name}, {business}-এ আগ্রহ দেখানোর জন্য ধন্যবাদ। তথ্য এখানে পাঠালাম – কোনো প্রশ্ন থাকলে এখানেই উত্তর দিন।',
      },
      callback: CALLBACK,
      not_interested: {
        en: 'Hi {name}, thanks for your time today. If you need anything later, just reply here and {business} will be happy to help.',
        hi: 'नमस्ते {name}, आज समय देने के लिए धन्यवाद। आगे कभी कुछ चाहिए तो बस यहाँ जवाब दें, {business} ख़ुशी से मदद करेगा।',
        bn: 'নমস্কার {name}, আজ সময় দেওয়ার জন্য ধন্যবাদ। পরে কিছু দরকার হলে এখানে উত্তর দিন, {business} সাহায্য করতে পেরে খুশি হবে।',
      },
    },
    callbackTiming: {
      startHour: 16,
      endHour: 19,
      hint: {
        en: 'Weekdays, 11 am–1 pm or 4–7 pm; never before 9 am or after 9 pm.',
        hi: 'हफ़्ते के दिनों में सुबह 11 से 1 बजे या शाम 4–7 बजे; सुबह 9 से पहले या रात 9 के बाद कभी नहीं।',
        bn: 'সপ্তাহের দিনে বেলা 11টা–1টা বা বিকেল 4–7টা; সকাল 9টার আগে বা রাত 9টার পরে কখনও নয়।',
      },
    },
  },
};

/**
 * Business category (businesses.category, the app's BusinessCategory wire value, or a free-text
 * synonym) -> playbook. Anything unknown gets the general playbook.
 */
const CATEGORY_PLAYBOOK: Record<string, PlaybookId> = {
  coaching: 'education', education: 'education', school: 'education', tuition: 'education', college: 'education',
  clinic: 'healthcare', diagnostic: 'healthcare', healthcare: 'healthcare', hospital: 'healthcare', dental: 'healthcare',
  real_estate: 'real_estate', realestate: 'real_estate', property: 'real_estate',
  salon: 'salon', spa: 'salon', beauty: 'salon',
  gym: 'fitness', fitness: 'fitness', yoga: 'fitness',
};

export function playbookIdFor(category?: string | null): PlaybookId {
  const key = (category ?? '').trim().toLowerCase().replace(/[\s-]+/g, '_');
  return CATEGORY_PLAYBOOK[key] ?? 'general';
}

export function playbookFor(category?: string | null): Playbook {
  return PLAYBOOKS[playbookIdFor(category)];
}

/** Outcome of a connected call, from the agent's normalized output. */
export function followupOutcome(o: { temperature?: string | null; intent?: string | null; callbackAt?: string | null }): FollowupOutcome {
  if (o.callbackAt || o.intent === 'callback_requested') return 'callback';
  if (o.intent === 'not_interested' || o.intent === 'opt_out') return 'not_interested';
  if (o.temperature === 'hot') return 'hot';
  if (o.temperature === 'cold') return 'not_interested';
  return 'warm';
}

function firstName(name: string | null | undefined): string {
  return (name ?? '').trim().split(/\s+/)[0] ?? '';
}

/** Fills {name} and {business}. An empty name drops the placeholder together with the space/comma before it. */
export function fillTemplate(template: string, vars: { name?: string | null; business?: string | null }): string {
  const name = firstName(vars.name);
  const business = (vars.business ?? '').trim() || 'us';
  const withName = name
    ? template.replace(/\{name\}/g, () => name)
    : template.replace(/[ ,]*\{name\}/g, '');
  // Function replacements: a name or business containing "$&" must stay literal.
  return withName.replace(/\{business\}/g, () => business);
}

/** The playbook's default WhatsApp follow-up for one call, ready for the owner to review. */
export function playbookFollowupMessage(
  playbook: Playbook,
  outcome: FollowupOutcome,
  lang: PlaybookLang,
  vars: { name?: string | null; business?: string | null },
): string {
  return fillTemplate(playbook.followups[outcome][lang], vars);
}

/**
 * Compact English block for the call agent's business_context: the qualifying questions and what
 * ready-to-buy means. Kept short; the caller still caps the whole context.
 */
export function playbookCallContext(playbook: Playbook): string {
  const qs = playbook.qualifyingQuestions.map((q, i) => `${i + 1}) ${q.en}`).join(' ');
  return `Qualify (${playbook.name.en} playbook), naturally, one at a time: ${qs}\nReady to buy: ${playbook.readyToBuy.description.en}`;
}

/** Longer English block for the in-app chat system prompt. */
export function playbookPromptBlock(playbook: Playbook): string {
  return [
    `CALL PLAYBOOK (${playbook.name.en}):`,
    'Qualifying questions (ask naturally, one at a time, skip what the customer already told you):',
    ...playbook.qualifyingQuestions.map((q, i) => `${i + 1}. ${q.en}`),
    `Ready to buy means: ${playbook.readyToBuy.description.en}`,
    'Objection handling:',
    ...playbook.objections.map((o) => `- "${o.objection.en}": ${o.hint.en}`),
  ].join('\n');
}

/** JSON for GET /playbooks/current, in one language. */
export function formatPlaybook(playbook: Playbook, lang: PlaybookLang, category: string | null) {
  return {
    id: playbook.id,
    category,
    language: lang,
    name: playbook.name[lang],
    qualifying_questions: playbook.qualifyingQuestions.map((q) => q[lang]),
    ready_to_buy: {
      description: playbook.readyToBuy.description[lang],
      temperature: playbook.readyToBuy.temperature,
      intents: [...playbook.readyToBuy.intents],
      min_score: playbook.readyToBuy.minScore,
    },
    objections: playbook.objections.map((o) => ({ objection: o.objection[lang], hint: o.hint[lang] })),
    followup_templates: Object.fromEntries(FOLLOWUP_OUTCOMES.map((k) => [k, playbook.followups[k][lang]])) as Record<FollowupOutcome, string>,
    callback_timing: {
      hint: playbook.callbackTiming.hint[lang],
      start_hour: playbook.callbackTiming.startHour,
      end_hour: playbook.callbackTiming.endHour,
    },
  };
}

/**
 * Default WhatsApp draft after a connected call when the agent returned no whatsapp_message: the
 * business's playbook template for the call's outcome, in the language the call was held in
 * (the agent's reported `language`, else the employee's first language). Never sent by itself;
 * the owner reviews it and taps send.
 */
export async function defaultFollowupDraft(
  db: D1Database,
  businessId: string,
  call: { leadName?: string | null; temperature?: string | null; intent?: string | null; callbackAt?: string | null; language?: unknown },
): Promise<string> {
  const [business, agent] = await Promise.all([
    db.prepare('SELECT name, category FROM businesses WHERE id = ?').bind(businessId).first<{ name: string | null; category: string | null }>(),
    db.prepare('SELECT languages FROM agents WHERE business_id = ? ORDER BY created_at LIMIT 1').bind(businessId).first<{ languages: string | null }>(),
  ]);
  const spoken = typeof call.language === 'string' ? businessPageLang([call.language]) : null;
  const lang = spoken ?? callLang(agent?.languages);
  return playbookFollowupMessage(playbookFor(business?.category), followupOutcome(call), lang, {
    name: call.leadName, business: business?.name,
  });
}
