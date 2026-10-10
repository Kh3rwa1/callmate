import 's.dart';

/// Calls log, call result and transcripts.
extension SCalls on S {
  // ------------------------------------------------------------ List
  String get aiCallsTitle => pick('AI Calls', 'AI कॉल्स', 'AI কল');
  String get filterConnected => pick('Connected', 'बात हुई', 'কথা হয়েছে');
  String get filterNoAnswer => pick('No Answer', 'जवाब नहीं', 'উত্তর নেই');
  String noCallsYetBy(String agent) => pick(
    '$agent hasn\'t made any calls yet.',
    '$agent ने अभी तक कोई कॉल नहीं की।',
    '$agent এখনও কোনো কল করেনি।',
  );
  String get startCampaignToSeeCalls => pick(
    'Start a campaign to see calls here.',
    'कॉल्स यहाँ देखने के लिए कैंपेन शुरू करें।',
    'এখানে কল দেখতে ক্যাম্পেন শুরু করুন।',
  );

  // ------------------------------------------------------------ Result
  String get callDetails =>
      pick('Call details', 'कॉल की जानकारी', 'কলের বিবরণ');
  String whatUnderstood(String agent) =>
      pick('What $agent understood', '$agent ने क्या समझा', '$agent যা বুঝেছে');
  String get noSummary => pick(
    'No summary available.',
    'सारांश उपलब्ध नहीं है।',
    'সারাংশ পাওয়া যায়নি।',
  );
  String get leadScoreTitle => pick('Lead score', 'लीड स्कोर', 'লিড স্কোর');
  String tempLead(String temp) => pick('$temp lead', '$temp लीड', '$temp লিড');
  String get nextStep => pick('Next step', 'अगला कदम', 'পরের পদক্ষেপ');
  String callBackAt(String when) =>
      pick('Call back $when', 'वापस कॉल: $when', 'আবার কল: $when');
  String get scheduleCallback =>
      pick('Schedule Callback', 'कॉलबैक तय करें', 'কলব্যাক ঠিক করুন');
  String get prepareWhatsapp =>
      pick('Prepare WhatsApp', 'WhatsApp तैयार करें', 'WhatsApp তৈরি করুন');
  String get openLead => pick('Open lead', 'लीड खोलें', 'লিড খুলুন');
  String get status => pick('Status', 'स्थिति', 'অবস্থা');
  String get when => pick('When', 'कब', 'কখন');
  String get durationLabel => pick('Duration', 'अवधि', 'সময়কাল');
  String get outcome => pick('Outcome', 'नतीजा', 'ফলাফল');
  String get nextLabel => pick('Next', 'आगे', 'এরপর');
  String get willRetryNextCampaign => pick(
    'Your AI employee will try again in the next campaign.',
    'आपका AI कर्मचारी अगले कैंपेन में फिर कोशिश करेगा।',
    'আপনার AI কর্মী পরের ক্যাম্পেনে আবার চেষ্টা করবে।',
  );

  // ------------------------------------------------------------ Transcript
  String showFullTranscript(int n) => pick(
    'Show full transcript ($n lines)',
    'पूरी बातचीत देखें ($n लाइनें)',
    'পুরো কথোপকথন দেখুন ($n লাইন)',
  );
  String said(String who, String text) =>
      pick('$who said: $text', '$who ने कहा: $text', '$who বলেছেন: $text');
  String get you => pick('You', 'आप', 'আপনি');
}
