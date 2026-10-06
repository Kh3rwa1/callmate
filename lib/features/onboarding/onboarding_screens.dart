import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../data/models/models.dart';
import '../../data/templates/templates.dart';
import '../knowledge/knowledge_sheets.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// ============================================================ 1. Welcome
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const MascotAvatar(size: 36),
                        const SizedBox(width: 10),
                        Text('Riya AI', style: t.titleMedium),
                      ],
                    ),
                    SizedBox(height: c.maxHeight * 0.05),
                    Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutBack,
                        builder: (_, v, child) => Transform.scale(
                          scale: 0.85 + 0.15 * v,
                          child: Opacity(opacity: v.clamp(0, 1), child: child),
                        ),
                        child: Mascot(state: MascotState.welcome, size: (c.maxHeight * 0.36).clamp(200, 300)),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text('Hire your\nAI employee', style: t.displaySmall),
                    const SizedBox(height: 14),
                    Text(
                      'It calls your leads, answers questions, and prepares follow-ups automatically.',
                      style: t.bodyLarge?.copyWith(color: AppColors.inkSoft, fontSize: 17),
                    ),
                    const SizedBox(height: 22),
                    const _LoopStrip(),
                    const SizedBox(height: 28),
                    PrimaryButton(
                      label: 'Create My AI Employee',
                      trailingArrow: true,
                      onPressed: () => context.push('/onboarding/business-type'),
                    ),
                    const SizedBox(height: 10),
                    Center(child: Text('Takes about 2 minutes · No setup fees', style: t.bodySmall)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual reinforcement of the core loop.
class _LoopStrip extends StatelessWidget {
  const _LoopStrip();
  @override
  Widget build(BuildContext context) {
    const steps = [('📞', 'Calls'), ('🧠', 'Learns'), ('🔥', 'Scores'), ('💬', 'Drafts'), ('🤝', 'You close')];
    return Semantics(
      label: 'Calls, understands, scores, drafts a follow-up, you close',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: AppShadows.card),
                      child: Text(steps[i].$1, style: const TextStyle(fontSize: 19)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      steps[i].$2,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.inkSoft, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.inkFaint),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ======================================================== 2. Business type
class BusinessTypeScreen extends ConsumerWidget {
  const BusinessTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingProvider);
    final t = Theme.of(context).textTheme;
    return OnboardingScaffold(
      step: 1,
      title: 'What kind of business do you run?',
      subtitle: 'We\'ll train your AI employee for your industry.',
      cta: PrimaryButton(
        label: 'Continue',
        onPressed: templateFor(draft.category).available ? () => context.push('/onboarding/details') : null,
      ),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: [
            for (final tpl in businessTemplates)
              _CategoryCard(
                category: tpl.category,
                available: tpl.available,
                selected: draft.category == tpl.category,
                onTap: tpl.available
                    ? () => ref.read(onboardingProvider.notifier).update((d) => d.copyWith(category: tpl.category))
                    : () => ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(content: Text('${tpl.category.label} is coming soon. Coaching Centres are live today!'))),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('More industries are on the way.', style: t.bodySmall),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.available, required this.selected, required this.onTap});
  final BusinessCategory category;
  final bool available;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      label: '${category.label}${available ? '' : ', coming soon'}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandSoft : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.cardSm),
          border: Border.all(color: selected ? AppColors.brand : AppColors.border, width: selected ? 2 : 1.5),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.cardSm),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Opacity(
              opacity: available ? 1 : 0.5,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Emoji(category.emoji, size: 28),
                        const Spacer(),
                        if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.brand),
                      ],
                    ),
                    const Spacer(),
                    Text(category.label, style: t.titleSmall),
                    const SizedBox(height: 4),
                    if (!available)
                      Text('Coming soon', style: t.bodySmall)
                    else
                      Text(
                        'Admissions Assistant',
                        style: t.bodySmall?.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================== 3. Business details
class BusinessDetailsScreen extends ConsumerStatefulWidget {
  const BusinessDetailsScreen({super.key});
  @override
  ConsumerState<BusinessDetailsScreen> createState() => _BusinessDetailsScreenState();
}

class _BusinessDetailsScreenState extends ConsumerState<BusinessDetailsScreen> {
  late final _name = TextEditingController(text: ref.read(onboardingProvider).businessName);
  late final _address = TextEditingController(text: ref.read(onboardingProvider).address);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _next() {
    if (!_form.currentState!.validate()) return;
    ref.read(onboardingProvider.notifier).update((d) => d.copyWith(businessName: _name.text.trim(), address: _address.text.trim()));
    context.push('/onboarding/offer');
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 2,
      title: 'What\'s your business called?',
      subtitle: 'Your AI employee will introduce itself on behalf of this name.',
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
                decoration: const InputDecoration(hintText: 'e.g. ABC Coaching Centre'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Please enter your business name' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              const FieldLabel('Business address', optional: true),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'e.g. 12 Park Street, Kolkata'),
                onFieldSubmitted: (_) => _next(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
  late final _fees = TextEditingController(text: d.fees);
  late final _hours = TextEditingController(text: d.hours);
  late final _loc = TextEditingController(text: d.location.isEmpty ? d.address : d.location);
  late final _wa = TextEditingController(text: d.whatsapp);
  late final _cn = TextEditingController(text: d.counsellor);

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
            fees: _fees.text,
            hours: _hours.text,
            location: _loc.text,
            whatsapp: _wa.text,
            counsellor: _cn.text,
          ),
        );
    context.push('/onboarding/teach');
  }

  @override
  Widget build(BuildContext context) {
    final wf = templateFor(ref.watch(onboardingProvider).category).workflow ?? coachingWorkflowTemplate;
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
            textInputAction: lines > 1 ? TextInputAction.newline : TextInputAction.next,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: icon == null ? null : Icon(icon, color: AppColors.inkFaint),
            ),
          ),
        ],
      ),
    );

    return OnboardingScaffold(
      step: 3,
      title: 'What does your business offer?',
      subtitle: 'Riya uses this to answer questions on calls.',
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
                icon: Icons.school_outlined,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Add at least one ${wf.interestLabel.toLowerCase()}' : null,
              ),
              field('Fees', _fees, 'e.g. NEET ₹52,000/yr · Boards ₹24,000/yr', icon: Icons.currency_rupee_rounded, optional: true),
              field('Opening hours', _hours, 'e.g. Mon–Sat, 9 AM – 8 PM', icon: Icons.schedule_rounded, optional: true),
              field('Location', _loc, 'e.g. Park Street, Kolkata', icon: Icons.place_outlined, optional: true),
              field(
                'WhatsApp number',
                _wa,
                '98300 12345',
                type: TextInputType.phone,
                icon: Icons.chat_outlined,
                validator: (v) => _phone(v),
              ),
              field(
                '${wf.counsellorLabel} number',
                _cn,
                'For hot-lead transfers',
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

// ========================================================== 5. Teach AI
class TeachAiOnboardingScreen extends ConsumerWidget {
  const TeachAiOnboardingScreen({super.key});

  Future<void> _pickPdf(BuildContext context, WidgetRef ref) async {
    try {
      final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
      final f = r?.files.firstOrNull;
      if (f == null) return;
      ref
          .read(onboardingProvider.notifier)
          .addKnowledge(KnowledgeInput(type: KnowledgeType.pdf, title: f.name.replaceAll('.pdf', ''), fileName: f.name, bytes: f.bytes));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open that file. Try another PDF.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(onboardingProvider);
    final t = Theme.of(context).textTheme;
    final n = ref.read(onboardingProvider.notifier);

    Future<void> add(KnowledgeType type) async {
      if (type == KnowledgeType.pdf) return _pickPdf(context, ref);
      final input = await showKnowledgeInputSheet(context, type);
      if (input != null) n.addKnowledge(input);
    }

    return OnboardingScaffold(
      step: 4,
      title: 'Teach your AI',
      subtitle: 'The more Riya knows, the better she answers. You can always add more later.',
      cta: PrimaryButton(label: d.knowledge.isEmpty ? 'Skip for now' : 'Continue', onPressed: () => context.push('/onboarding/create')),
      children: [
        _TeachOption(
          emoji: '📄',
          title: 'Upload brochure PDF',
          subtitle: 'Courses, fees, batch details',
          onTap: () => add(KnowledgeType.pdf),
        ),
        _TeachOption(emoji: '🌐', title: 'Add website', subtitle: 'We\'ll read your public pages', onTap: () => add(KnowledgeType.website)),
        _TeachOption(emoji: '❓', title: 'Add FAQ', subtitle: 'Common questions parents ask', onTap: () => add(KnowledgeType.faq)),
        _TeachOption(
          emoji: '📝',
          title: 'Paste information',
          subtitle: 'Anything else Riya should know',
          onTap: () => add(KnowledgeType.text),
        ),
        _TeachOption(
          emoji: '📥',
          title: 'Import CSV leads later',
          subtitle: 'You can add leads from the Leads tab',
          trailing: const Pill(label: 'Later'),
          onTap: () => ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(content: Text('You\'ll be able to import leads right after setup.'))),
        ),
        if (d.knowledge.isNotEmpty) ...[
          const SectionLabel('Added'),
          for (final k in d.knowledge)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                shadow: false,
                border: Border.all(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(k.title, style: t.titleSmall, overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(tooltip: 'Remove', onPressed: () => n.removeKnowledge(k), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _TeachOption extends StatelessWidget {
  const _TeachOption({required this.emoji, required this.title, required this.subtitle, required this.onTap, this.trailing});
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconBubble(color: AppColors.surfaceMuted, child: Emoji(emoji)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.bodySmall),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.add_rounded, color: AppColors.brand),
          ],
        ),
      ),
    );
  }
}

// ===================================================== 6. Create agent
class CreateAgentScreen extends ConsumerStatefulWidget {
  const CreateAgentScreen({super.key});
  @override
  ConsumerState<CreateAgentScreen> createState() => _CreateAgentScreenState();
}

class _CreateAgentScreenState extends ConsumerState<CreateAgentScreen> {
  int _phase = 0; // 0 learning → 1 ready
  Agent? _agent;
  Object? _error;
  static const _learning = ['Reading your business details…', 'Learning your courses & fees…', 'Practising admissions calls…'];
  int _line = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _phase = 0;
      _line = 0;
    });
    try {
      final f = ref.read(onboardingProvider.notifier).createAgent();
      for (var i = 1; i < _learning.length; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        setState(() => _line = i);
      }
      final a = await f;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _agent = a;
        _phase = 1;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Mascot(state: MascotState.error, size: 170),
                  const SizedBox(height: 16),
                  Text('We couldn\'t set up Riya', style: t.titleLarge),
                  const SizedBox(height: 8),
                  Text('Something went wrong. Try again.', style: t.bodyMedium),
                  const SizedBox(height: 24),
                  PrimaryButton(label: 'Try again', onPressed: _run),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final a = _agent;
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _phase == 0
              ? Center(
                  key: const ValueKey('learning'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Mascot(state: MascotState.thinking, size: 200),
                      const SizedBox(height: 28),
                      const SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(9))),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(_learning[_line], key: ValueKey(_line), style: t.titleMedium),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  key: const ValueKey('ready'),
                  padding: const EdgeInsets.all(AppSpace.page),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.elasticOut,
                        builder: (_, v, child) => Transform.scale(scale: 0.6 + 0.4 * v, child: child),
                        child: const Mascot(state: MascotState.success, size: 220),
                      ),
                      const SizedBox(height: 16),
                      Text('Meet ${a?.name ?? 'Riya'} 👋', style: t.displaySmall, textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      Text(a?.role ?? 'Admissions Assistant', style: t.titleMedium?.copyWith(color: AppColors.brand)),
                      const SizedBox(height: 14),
                      Text(
                        '${a?.name ?? 'Riya'} has learned about your business and is ready to call your leads.',
                        style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      AppCard(
                        child: Column(
                          children: [
                            _Trait(label: 'Languages', value: (a?.languages ?? const ['Bengali', 'Hindi', 'English']).join(' · ')),
                            const Divider(height: 28),
                            _Trait(label: 'Personality', value: a?.personalityLabel ?? 'Friendly · Professional'),
                            const Divider(height: 28),
                            _Trait(label: 'Goal', value: a?.goal ?? coachingAgentTemplate.goal),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: 'Activate ${a?.name ?? 'Riya'}',
                        icon: Icons.bolt_rounded,
                        color: AppColors.success,
                        onPressed: () => context.push('/onboarding/test'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Trait extends StatelessWidget {
  const _Trait({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 104, child: Text(label, style: t.bodyMedium)),
        Expanded(child: Text(value, style: t.titleSmall)),
      ],
    );
  }
}

// ===================================================== 7. First AI call
class FirstCallScreen extends ConsumerWidget {
  const FirstCallScreen({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    await ref.read(localPrefsProvider).setOnboarded(true);
    await ref.read(notificationServiceProvider).requestPermission();
    if (context.mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final agent = ref.watch(agentProvider).value;
    final name = agent?.name ?? 'Riya';
    final wf = coachingWorkflowTemplate;
    return OnboardingScaffold(
      step: 6,
      title: 'Make your first AI call',
      subtitle: 'Pretend to be a parent enquiring about admission. Hear how $name handles it.',
      cta: PrimaryButton(
        label: 'Test $name',
        icon: Icons.mic_rounded,
        onPressed: () async {
          await context.push('/voice-test?from=onboarding');
          await ref.read(localPrefsProvider).setAgentTested(true);
        },
      ),
      secondary: TextButton(onPressed: () => _finish(context, ref), child: const Text('Go to my dashboard')),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SAMPLE LEAD', style: t.labelSmall),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.hotSoft, shape: BoxShape.circle),
                    child: Text('RK', style: t.titleMedium?.copyWith(color: AppColors.hot)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(wf.sampleLeadName, style: t.titleLarge),
                        Text(wf.sampleLeadInterest, style: t.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  '“Hi, I filled a form for NEET coaching. What are the fees?”',
                  style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Mascot(state: MascotState.calling, size: 96, halo: false),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$name will introduce herself as an AI assistant, answer questions, and offer a counsellor callback.',
                style: t.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          color: AppColors.successSoft,
          shadow: false,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Test calls are free and never contact real leads.', style: t.bodyMedium?.copyWith(color: AppColors.ink)),
              ),
            ],
          ),
        ),
        if (ref.watch(localPrefsProvider).agentTested) ...[
          const SizedBox(height: 16),
          PrimaryButton(label: 'Looks great – go to dashboard', color: AppColors.success, onPressed: () => _finish(context, ref)),
        ],
      ],
    );
  }
}
