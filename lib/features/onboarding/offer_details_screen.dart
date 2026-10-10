import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../l10n/l10n.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// ======================================================= 4. Offer details
class OfferDetailsScreen extends ConsumerStatefulWidget {
  const OfferDetailsScreen({super.key});
  @override
  ConsumerState<OfferDetailsScreen> createState() => _OfferDetailsScreenState();
}

class _OfferDetailsScreenState extends ConsumerState<OfferDetailsScreen> {
  final _form = GlobalKey<FormState>();
  late final OnboardingDraft d = ref.read(onboardingProvider);
  late final _offer = TextEditingController(text: d.offerings);
  late final _fees = TextEditingController(text: d.pricing);
  late final _hours = TextEditingController(text: d.hours);
  late final _loc = TextEditingController(
    text: d.location.isEmpty ? d.address : d.location,
  );
  late final _wa = TextEditingController(text: d.whatsapp);
  late final _cn = TextEditingController(text: d.humanNumber);
  int _shakes = 0;

  @override
  void dispose() {
    for (final c in [_offer, _fees, _hours, _loc, _wa, _cn]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _phone(S s, String? v, {bool required = false}) {
    if ((v ?? '').trim().isEmpty) return required ? s.obRequired : null;
    return PhoneUtils.isValid(v) ? null : s.validPhoneShort;
  }

  void _next() {
    if (!_form.currentState!.validate()) {
      Haptics.warn();
      setState(() => _shakes++);
      return;
    }
    ref
        .read(onboardingProvider.notifier)
        .update(
          (d) => d.copyWith(
            offerings: _offer.text,
            pricing: _fees.text,
            hours: _hours.text,
            location: _loc.text,
            whatsapp: _wa.text,
            humanNumber: _cn.text,
          ),
        );
    context.push('/onboarding/teach');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final wf = ref.watch(onboardingProvider).template.workflow;
    var cascade = 2;
    Widget field(
      String label,
      TextEditingController c,
      String hint, {
      bool optional = false,
      TextInputType? type,
      String? Function(String?)? validator,
      int lines = 1,
      required IconData icon,
    }) => OnboardingField(
      index: cascade++,
      label: label,
      optional: optional,
      child: TextFormField(
        controller: c,
        keyboardType: type,
        maxLines: lines,
        minLines: 1,
        validator: validator,
        textInputAction: lines > 1
            ? TextInputAction.newline
            : TextInputAction.next,
        decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon)),
      ),
    );

    return OnboardingScaffold(
      step: 4,
      title: s.obOfferTitle,
      subtitle: s.obOfferSub,
      revealChildren: false,
      cta: PrimaryButton(label: s.continueLabel, onPressed: _next),
      children: [
        Shake(
          trigger: _shakes,
          child: Form(
            key: _form,
            child: Column(
              children: [
                field(
                  s.data(wf.offeringsLabel),
                  _offer,
                  s.data(wf.offeringsHint),
                  lines: 2,
                  icon: Icons.storefront_outlined,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? s.obAddAtLeastOne(s.data(wf.interestLabel))
                      : null,
                ),
                field(
                  s.obPricing,
                  _fees,
                  s.obPricingHint,
                  icon: Icons.currency_rupee_rounded,
                  optional: true,
                ),
                field(
                  s.obHours,
                  _hours,
                  s.obHoursHint,
                  icon: Icons.schedule_rounded,
                  optional: true,
                ),
                field(
                  s.obLocation,
                  _loc,
                  s.obLocationHint,
                  icon: Icons.place_outlined,
                  optional: true,
                ),
                field(
                  s.whatsapp,
                  _wa,
                  '98300 12345',
                  type: TextInputType.phone,
                  icon: Icons.chat_outlined,
                  validator: (v) => _phone(s, v),
                ),
                field(
                  s.obHumanNumber(s.data(wf.humanLabel)),
                  _cn,
                  s.obHumanNumberHint,
                  type: TextInputType.phone,
                  icon: Icons.support_agent_rounded,
                  validator: (v) => _phone(s, v),
                  optional: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
