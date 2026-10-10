import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/widgets/app_card.dart';
import '../../l10n/l10n.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// ===================================================== 3. Business details
class BusinessDetailsScreen extends ConsumerStatefulWidget {
  const BusinessDetailsScreen({super.key});
  @override
  ConsumerState<BusinessDetailsScreen> createState() =>
      _BusinessDetailsScreenState();
}

class _BusinessDetailsScreenState extends ConsumerState<BusinessDetailsScreen> {
  late final _name = TextEditingController(
    text: ref.read(onboardingProvider).businessName,
  );
  late final _address = TextEditingController(
    text: ref.read(onboardingProvider).address,
  );
  final _form = GlobalKey<FormState>();
  int _shakes = 0;

  @override
  void initState() {
    super.initState();
    // Phone sign-up already asked for the business name: start from it.
    if (_name.text.isEmpty) {
      ref
          .read(businessProvider.future)
          .then((b) {
            if (mounted && _name.text.isEmpty && b != null) _name.text = b.name;
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
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
            businessName: _name.text.trim(),
            address: _address.text.trim(),
          ),
        );
    context.push('/onboarding/offer');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return OnboardingScaffold(
      step: 3,
      title: s.obDetailsTitle,
      subtitle: s.obDetailsSub,
      revealChildren: false,
      cta: PrimaryButton(label: s.continueLabel, onPressed: _next),
      children: [
        Shake(
          trigger: _shakes,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OnboardingField(
                  index: 2,
                  label: s.nameLabel,
                  child: TextFormField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    style: Theme.of(context).textTheme.titleMedium,
                    decoration: InputDecoration(
                      hintText: s.obBizNameHint,
                      prefixIcon: const Icon(Icons.storefront_outlined),
                    ),
                    validator: (v) => (v ?? '').trim().length < 2
                        ? s.obBizNameRequired
                        : null,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                OnboardingField(
                  index: 3,
                  label: s.obAddress,
                  optional: true,
                  child: TextFormField(
                    controller: _address,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: s.obAddressHint,
                      prefixIcon: const Icon(Icons.place_outlined),
                    ),
                    onFieldSubmitted: (_) => _next(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
