import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets/app_card.dart';
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
    if (!_form.currentState!.validate()) return;
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
    return OnboardingScaffold(
      step: 3,
      title: 'What\'s your business called?',
      subtitle:
          'Your AI employee will introduce itself on behalf of this name.',
      cta: PrimaryButton(label: 'Continue', onPressed: _next),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('Business name'),
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: Theme.of(context).textTheme.titleMedium,
                decoration: const InputDecoration(
                  hintText: 'e.g. Sharma Realty, Smile Dental, ABC Coaching',
                ),
                validator: (v) => (v ?? '').trim().length < 2
                    ? 'Please enter your business name'
                    : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              const FieldLabel('Business address', optional: true),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. 12 Park Street, Kolkata',
                ),
                onFieldSubmitted: (_) => _next(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
