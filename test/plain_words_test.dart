import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('plain words', () {
    test('lead details: known keys are translated, others humanised', () {
      expect(S.en.attributeLabel('city'), 'City');
      expect(const S(AppLang.hi).attributeLabel('city'), 'शहर');
      expect(const S(AppLang.bn).attributeLabel('email'), 'ইমেল');
      expect(S.en.attributeLabel('google_campaign_id'), 'Google ad number');
      expect(S.en.attributeLabel('preferred_time'), 'Preferred time');
      expect(S.en.attributeLabel('shop_size'), 'Shop size');
      expect(S.en.attributeLabel(''), '');
    });

    test('one all-in price and a plan name, never "Founding Plan"', () {
      expect(S.en.priceInclGst('₹5,899'), '₹5,899 (incl. GST)');
      expect(const S(AppLang.hi).priceInclGst('₹5,899'), '₹5,899 (GST सहित)');
      expect(S.en.planDisplayName('Founding Plan'), 'Starter');
      expect(S.en.planDisplayName(''), 'Starter');
      expect(S.en.planDisplayName('Growth'), 'Growth');
      expect(
        const S(AppLang.hi).planDisplayName('Founding Plan'),
        'स्टार्टर प्लान',
      );
    });

    test('no developer jargon in the website connection labels', () {
      for (final lang in AppLang.values) {
        final s = S(lang);
        for (final label in [
          s.secretKey,
          s.webhookUrl,
          s.copyForDeveloper,
          s.importCsv,
          s.ctHaveFile,
          s.sendOtp,
          s.consentHistory,
          s.signals,
          s.transcript,
        ]) {
          expect(label, isNot(matches(RegExp(r'URL|CSV|OTP|[Ss]ecret'))));
        }
      }
      expect(S.en.leadStatus(LeadStatus.converted), 'Became a customer');
    });
  });
}
