import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
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

  @override
  void dispose() {
    for (final c in [_offer, _fees, _hours, _loc, _wa, _cn]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _phone(String? v, {bool required = false}) {
    if ((v ?? '').trim().isEmpty) return required ? 'Required' : null;
    return PhoneUtils.isValid(v) ? null : 'Enter a valid mobile number';
  }

  void _next() {
    if (!_form.currentState!.validate()) return;
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
    final wf = ref.watch(onboardingProvider).template.workflow;
    Widget field(
      String label,
      TextEditingController c,
      String hint, {
      bool optional = false,
      TextInputType? type,
      String? Function(String?)? validator,
      int lines = 1,
      IconData? icon,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label, optional: optional),
          TextFormField(
            controller: c,
            keyboardType: type,
            maxLines: lines,
            minLines: 1,
            validator: validator,
            textInputAction: lines > 1
                ? TextInputAction.newline
                : TextInputAction.next,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: icon == null
                  ? null
                  : Icon(icon, color: AppColors.inkFaint),
            ),
          ),
        ],
      ),
    );

    return OnboardingScaffold(
      step: 4,
      title: 'What does your business offer?',
      subtitle:
          'Your AI employee uses this to answer customer questions on calls.',
      cta: PrimaryButton(label: 'Continue', onPressed: _next),
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              field(
                wf.offeringsLabel,
                _offer,
                wf.offeringsHint,
                lines: 2,
                icon: Icons.storefront_outlined,
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Add at least one ${wf.interestLabel.toLowerCase()}'
                    : null,
              ),
              field(
                'Pricing',
                _fees,
                'e.g. Starting from ₹999 · Packages available',
                icon: Icons.currency_rupee_rounded,
                optional: true,
              ),
              field(
                'Opening hours',
                _hours,
                'e.g. Mon–Sat, 9 AM – 8 PM',
                icon: Icons.schedule_rounded,
                optional: true,
              ),
              field(
                'Location',
                _loc,
                'e.g. Park Street, Kolkata',
                icon: Icons.place_outlined,
                optional: true,
              ),
              field(
                'WhatsApp number',
                _wa,
                '98300 12345',
                type: TextInputType.phone,
                icon: Icons.chat_outlined,
                validator: (v) => _phone(v),
              ),
              field(
                '${wf.humanLabel} number',
                _cn,
                'Who closes hot leads',
                type: TextInputType.phone,
                icon: Icons.support_agent_rounded,
                validator: (v) => _phone(v),
                optional: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
