import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/brand.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../data/models/models.dart';
import '../../data/templates/templates.dart';
import '../knowledge/knowledge_sheets.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// Flow: Welcome → Business type → Employee skills → Business name → Offer →
//       Teach → Meet your AI employee → Test → Home

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
                    const BrandWordmark(size: 19),
                    const SizedBox(height: 22),
                    Text('Welcome to ${Brand.appName}', style: t.headlineSmall),
                    const SizedBox(height: 4),
                    Text('${Brand.tagline}.', style: t.bodyLarge?.copyWith(color: AppColors.inkSoft)),
                    SizedBox(height: c.maxHeight * 0.02),
                    Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutBack,
                        builder: (_, v, child) => Transform.scale(
                          scale: 0.85 + 0.15 * v,
                          child: Opacity(opacity: v.clamp(0, 1), child: child),
                        ),
                        child: Mascot(state: MascotState.welcome, size: (c.maxHeight * 0.3).clamp(180, 260)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('HIRE YOUR AI EMPLOYEE', style: t.labelSmall?.copyWith(color: AppColors.brand, fontSize: 13)),
                    const SizedBox(height: 8),
                    Text('Call leads, qualify customers, and follow up for your business.', style: t.headlineSmall?.copyWith(height: 1.25)),
                    const SizedBox(height: 20),
                    const _LoopStrip(),
                    const SizedBox(height: 26),
                    PrimaryButton(
                      label: 'Create My AI Employee',
                      trailingArrow: true,
                      onPressed: () => context.push('/onboarding/business-type'),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(Brand.description, style: t.bodySmall, textAlign: TextAlign.center),
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

/// Visual reinforcement of the core loop.
class _LoopStrip extends StatelessWidget {
  const _LoopStrip();
  @override
  Widget build(BuildContext context) {
    const steps = [('📞', 'Calls'), ('🧠', 'Analyses'), ('🔥', 'Scores'), ('💬', 'Drafts'), ('🤝', 'You close')];
    return Semantics(
      label: 'Calls, analyses, scores, drafts a follow-up, you close',
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
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: AppShadows.card),
                      child: Text(steps[i].$1, style: const TextStyle(fontSize: 19)),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        steps[i].$2,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.inkSoft, fontSize: 11.5),
                      ),
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
    return OnboardingScaffold(
      step: 1,
      title: 'What type of business do you run?',
      subtitle: 'We\'ll set up your AI employee with the right defaults. You can change anything later.',
      cta: PrimaryButton(label: 'Continue', onPressed: draft.category == null ? null : () => context.push('/onboarding/skills')),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            for (final tpl in businessTemplates)
              _ChoiceCard(
                emoji: tpl.category.emoji,
                title: tpl.category.label,
                subtitle: tpl.agent.role,
                selected: draft.category == tpl.category,
                onTap: () => ref.read(onboardingProvider.notifier).selectCategory(tpl.category),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.emoji,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.multi = false,
  });
  final String emoji;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      label: title,
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
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Emoji(emoji, size: 26),
                      const Spacer(),
                      if (selected)
                        Icon(multi ? Icons.check_box_rounded : Icons.check_circle_rounded, color: AppColors.brand)
                      else if (multi)
                        const Icon(Icons.check_box_outline_blank_rounded, color: AppColors.border),
                    ],
                  ),
                  const Spacer(),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, style: t.titleSmall, maxLines: 1)),
                  if (subtitle != null)
                    Text(subtitle!, style: t.bodySmall?.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================ 2b. What should it do?
class EmployeeSkillsScreen extends ConsumerWidget {
  const EmployeeSkillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(onboardingProvider);
    final t = Theme.of(context).textTheme;
    final suggested = d.suggestedAgent;
    return OnboardingScaffold(
      step: 2,
      title: 'What should your AI employee do?',
      subtitle: 'Pick everything that applies.',
      cta: PrimaryButton(label: 'Continue', onPressed: d.skills.isEmpty ? null : () => context.push('/onboarding/details')),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.75,
          children: [
            for (final s in EmployeeSkill.values)
              _ChoiceCard(
                emoji: s.emoji,
                title: s.label,
                multi: true,
                selected: d.skills.contains(s),
                onTap: () => ref.read(onboardingProvider.notifier).toggleSkill(s),
              ),
          ],
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: AppCard(
            key: ValueKey(suggested.role),
            color: AppColors.surfaceMuted,
            shadow: false,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                RoleBadge(role: suggested.roleKind, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Text('We\'ll set up a ${suggested.role} for you.', style: t.titleSmall)),
              ],
            ),
          ),
        ),
      ],
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
      step: 3,
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
                decoration: const InputDecoration(hintText: 'e.g. Sharma Realty, Smile Dental, ABC Coaching'),
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
  late final _fees = TextEditingController(text: d.pricing);
  late final _hours = TextEditingController(text: d.hours);
  late final _loc = TextEditingController(text: d.location.isEmpty ? d.address : d.location);
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
      step: 4,
      title: 'What does your business offer?',
      subtitle: 'Your AI employee uses this to answer customer questions on calls.',
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
                validator: (v) => (v ?? '').trim().isEmpty ? 'Add at least one ${wf.interestLabel.toLowerCase()}' : null,
              ),
              field('Pricing', _fees, 'e.g. Starting from ₹999 · Packages available', icon: Icons.currency_rupee_rounded, optional: true),
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
      step: 5,
      title: 'Teach Your AI',
      subtitle: 'The more your AI employee knows, the better it answers. You can always add more later.',
      cta: PrimaryButton(label: d.knowledge.isEmpty ? 'Skip for now' : 'Continue', onPressed: () => context.push('/onboarding/create')),
      children: [
        _TeachOption(
          emoji: '📄',
          title: 'Upload brochure PDF',
          subtitle: 'Services, pricing, brochure',
          onTap: () => add(KnowledgeType.pdf),
        ),
        _TeachOption(emoji: '🌐', title: 'Add website', subtitle: 'We\'ll read your public pages', onTap: () => add(KnowledgeType.website)),
        _TeachOption(emoji: '❓', title: 'Add FAQ', subtitle: 'Common questions customers ask', onTap: () => add(KnowledgeType.faq)),
        _TeachOption(
          emoji: '📍',
          title: 'Add business information',
          subtitle: 'Opening hours, location, policies',
          onTap: () => add(KnowledgeType.businessInfo),
        ),
        _TeachOption(
          emoji: '📝',
          title: 'Paste text',
          subtitle: 'Services, pricing, offers – anything else',
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

// =========================================== 6. Meet your AI employee
class CreateAgentScreen extends ConsumerStatefulWidget {
  const CreateAgentScreen({super.key});
  @override
  ConsumerState<CreateAgentScreen> createState() => _CreateAgentScreenState();
}

class _CreateAgentScreenState extends ConsumerState<CreateAgentScreen> {
  int _phase = 0; // 0 learning → 1 meet
  bool _activating = false;
  Object? _error;
  late final TextEditingController _name;
  late final TextEditingController _role;
  static const _learning = ['Reading your business details…', 'Learning what you offer…', 'Practising customer calls…'];
  int _line = 0;

  @override
  void initState() {
    super.initState();
    final a = ref.read(onboardingProvider).suggestedAgent;
    _name = TextEditingController(text: ref.read(onboardingProvider).employeeName ?? a.defaultName);
    _role = TextEditingController(text: ref.read(onboardingProvider).employeeRole ?? a.role);
    _run();
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _phase = 0;
      _line = 0;
    });
    try {
      final f = ref.read(onboardingProvider.notifier).saveBusiness();
      for (var i = 1; i < _learning.length; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 850));
        if (!mounted) return;
        setState(() => _line = i);
      }
      await f;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _phase = 1);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _activate() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _activating = true);
    ref.read(onboardingProvider.notifier).update((d) => d.copyWith(employeeName: _name.text.trim(), employeeRole: _role.text.trim()));
    try {
      await ref.read(onboardingProvider.notifier).activateEmployee();
      if (mounted) context.push('/onboarding/test');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong. Try again.')));
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = ref.watch(onboardingProvider);
    final at = d.suggestedAgent;
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
                  Text('We couldn\'t set up your AI employee', style: t.titleLarge, textAlign: TextAlign.center),
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
    final roleKind = EmployeeRoleKind.fromRole(_role.text);
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
              : Column(
                  key: const ValueKey('meet'),
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpace.page),
                        child: Column(
                          children: [
                            Text('Meet your AI employee 👋', style: t.headlineSmall, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.elasticOut,
                              builder: (_, v, child) => Transform.scale(scale: 0.6 + 0.4 * v, child: child),
                              child: Mascot(state: MascotState.success, size: 190, role: roleKind),
                            ),
                            const SizedBox(height: 6),
                            ValueListenableBuilder(
                              valueListenable: _name,
                              builder: (_, v, __) =>
                                  Text(v.text.isEmpty ? 'Name your employee' : v.text, style: t.displaySmall, textAlign: TextAlign.center),
                            ),
                            ValueListenableBuilder(
                              valueListenable: _role,
                              builder: (_, v, __) => Text(v.text, style: t.titleMedium?.copyWith(color: AppColors.brand)),
                            ),
                            const SizedBox(height: 20),
                            AppCard(
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _name,
                                          textCapitalization: TextCapitalization.words,
                                          decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.badge_outlined)),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _role,
                                    textCapitalization: TextCapitalization.words,
                                    decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.work_outline_rounded)),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  const Divider(height: 32),
                                  _Trait(label: 'Languages', value: at.languages.join(' · ')),
                                  const SizedBox(height: 14),
                                  const _Trait(label: 'Personality', value: 'Friendly · Professional'),
                                  const SizedBox(height: 14),
                                  _Trait(label: 'Goal', value: at.goal),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Your AI employee always introduces itself as an AI assistant.',
                              style: t.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpace.page, 8, AppSpace.page, 16),
                      child: PrimaryButton(
                        label: 'Activate Employee',
                        icon: Icons.bolt_rounded,
                        color: AppColors.success,
                        loading: _activating,
                        onPressed: _activate,
                      ),
                    ),
                  ],
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
    final name = ref.watch(employeeNameProvider);
    final wf = ref.watch(workflowProvider);
    final parts = wf.sampleLeadName.split(' ');
    final initials = parts.map((p) => p[0]).take(2).join();
    return OnboardingScaffold(
      step: 6,
      title: 'Make your first AI call',
      subtitle: '${wf.testCallerHint} Hear how $name handles it.',
      cta: PrimaryButton(
        label: 'Talk to $name',
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
                    child: Text(initials, style: t.titleMedium?.copyWith(color: AppColors.hot)),
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
                child: Text(wf.sampleLeadQuote, style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const EmployeeMascot(state: MascotState.calling, size: 96, halo: false),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$name introduces itself as an AI assistant, answers questions, and offers a ${wf.humanLabel.toLowerCase()} follow-up.',
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
