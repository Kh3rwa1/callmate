import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/employee_avatar.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../l10n/l10n.dart';
import '../../services/voice/voice_persona.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// ============================================ 2/3. Business name + voice
/// Business name (prefilled from sign-up) and a woman's or man's voice.
/// Continue saves the business and creates the employee with the business
/// type's defaults; everything else can be added later.
class NameVoiceScreen extends ConsumerStatefulWidget {
  const NameVoiceScreen({super.key});
  @override
  ConsumerState<NameVoiceScreen> createState() => _NameVoiceScreenState();
}

class _NameVoiceScreenState extends ConsumerState<NameVoiceScreen> {
  late final _name = TextEditingController(
    text: ref.read(onboardingProvider).businessName,
  );
  final _form = GlobalKey<FormState>();
  int _shakes = 0;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Sign-up already asked for the business name: start from it.
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
    super.dispose();
  }

  void _setVoice(bool male) {
    Haptics.tap();
    ref
        .read(onboardingProvider.notifier)
        .update(
          (d) => d.copyWith(employeeVoice: male ? maleVoice : femaleVoice),
        );
  }

  Future<void> _next() async {
    final s = context.s;
    if (!_form.currentState!.validate()) {
      Haptics.warn();
      setState(() => _shakes++);
      return;
    }
    final notifier = ref.read(onboardingProvider.notifier);
    notifier.update((d) => d.copyWith(businessName: _name.text.trim()));
    final prefs = ref.read(localPrefsProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await notifier.finishSetup();
      // The business and employee now exist: a relaunch from step 3 lands
      // on Home instead of redoing the first run.
      await prefs.setOnboarded(true);
      if (mounted) context.push('/onboarding/hear');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, s));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final draft = ref.watch(onboardingProvider);
    final male = draft.maleVoiceChosen;
    final at = draft.suggestedAgent;
    final name = draft.resolvedEmployeeName;
    return OnboardingScaffold(
      mascot: MascotState.thinking,
      step: 2,
      title: s.obNameTitle,
      subtitle: s.obNameSub,
      revealChildren: false,
      cta: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                key: const Key('setup-error'),
                style: t.bodyLarge?.copyWith(color: AppColors.hot),
              ),
            ),
          PrimaryButton(
            label: s.continueLabel,
            trailingArrow: true,
            loading: _saving,
            onPressed: _saving ? null : _next,
          ),
        ],
      ),
      children: [
        Shake(
          trigger: _shakes,
          child: Form(
            key: _form,
            child: TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              style: t.titleLarge,
              decoration: InputDecoration(
                hintText: s.obBizNameHint,
                prefixIcon: const Icon(Icons.storefront_outlined),
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? s.obBizNameRequired : null,
              textInputAction: TextInputAction.done,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(s.obVoiceQuestion, style: t.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _VoiceTile(
                label: s.obVoiceFemale,
                icon: Icons.face_3_rounded,
                selected: !male,
                onTap: () => _setVoice(false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _VoiceTile(
                label: s.obVoiceMale,
                icon: Icons.face_6_rounded,
                selected: male,
                onTap: () => _setVoice(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Row(
            children: [
              EmployeeAvatar(name: name, role: at.roleKind, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: SwapFade(
                  child: Text(
                    s.obEmployeeIntro(name, s.data(at.role)),
                    key: ValueKey(name),
                    style: t.bodyLarge,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One big "Woman's voice" / "Man's voice" choice.
class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: AppMotion.standard,
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border,
              width: selected ? 2 : 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 36,
                color: selected ? AppColors.brand : AppColors.inkSoft,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: t.titleMedium?.copyWith(
                  color: selected ? AppColors.brandDeep : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
