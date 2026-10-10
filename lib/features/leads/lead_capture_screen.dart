import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// Customers → "Get leads automatically": the hosted enquiry form (link,
/// share, QR code), auto-call toggle, and website/Google Forms webhooks whose
/// secret key is shown once. Every new enquiry is AI-called within about a
/// minute (backend: services/lead_capture.ts).
class LeadCaptureScreen extends ConsumerStatefulWidget {
  const LeadCaptureScreen({super.key});

  @override
  ConsumerState<LeadCaptureScreen> createState() => _LeadCaptureScreenState();
}

class _LeadCaptureScreenState extends ConsumerState<LeadCaptureScreen> {
  bool _creatingForm = false;
  bool _creatingHook = false;
  final Set<String> _busy = {};

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) _snack(friendlyError(e, context.s));
    }
  }

  Future<void> _createForm() async {
    setState(() => _creatingForm = true);
    await _run(() async {
      await ref.read(leadSourceRepoProvider).create(LeadSourceKind.form);
      ref.invalidate(leadSourcesProvider);
    });
    if (mounted) setState(() => _creatingForm = false);
  }

  Future<void> _createWebhook() async {
    setState(() => _creatingHook = true);
    LeadSource? created;
    await _run(() async {
      created = await ref
          .read(leadSourceRepoProvider)
          .create(LeadSourceKind.webhook);
      ref.invalidate(leadSourcesProvider);
    });
    if (!mounted) return;
    setState(() => _creatingHook = false);
    if (created != null) await showWebhookTokenSheet(context, created!);
  }

  Future<void> _setAutoCall(LeadSource src, bool on) async {
    setState(() => _busy.add(src.id));
    await _run(() async {
      await ref.read(leadSourceRepoProvider).setAutoCall(src.id, autoCall: on);
      ref.invalidate(leadSourcesProvider);
    });
    if (mounted) setState(() => _busy.remove(src.id));
  }

  Future<void> _revoke(LeadSource src) async {
    final s = context.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.turnOffLinkTitle),
        content: Text(s.turnOffLinkBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(s.cancel),
          ),
          TextButton(
            key: const Key('lead-capture-confirm-revoke'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(s.turnOff),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(src.id));
    await _run(() async {
      await ref.read(leadSourceRepoProvider).revoke(src.id);
      ref.invalidate(leadSourcesProvider);
    });
    if (mounted) setState(() => _busy.remove(src.id));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final sources = ref.watch(leadSourcesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.getLeadsAutomatically)),
      body: AsyncView<List<LeadSource>>(
        value: sources,
        onRetry: () => ref.invalidate(leadSourcesProvider),
        data: (list) => _body(context, list),
      ),
    );
  }

  Widget _body(BuildContext context, List<LeadSource> list) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final form = list.where((x) => x.isForm).firstOrNull;
    final hooks = list.where((x) => !x.isForm).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 36),
      children: [
        Text(
          s.leadCaptureIntro,
          style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
        SectionLabel(s.enquiryForm),
        if (form == null)
          AppCard(
            key: const Key('lead-capture-empty'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.enquiryFormHint, style: t.bodyMedium),
                const SizedBox(height: 16),
                PrimaryButton(
                  key: const Key('lead-capture-create-form'),
                  label: s.createFormLink,
                  icon: Icons.link_rounded,
                  loading: _creatingForm,
                  onPressed: _creatingForm ? null : _createForm,
                ),
              ],
            ),
          )
        else
          _FormCard(
            source: form,
            busy: _busy.contains(form.id),
            onCopy: () {
              Clipboard.setData(ClipboardData(text: form.url));
              _snack(s.linkCopied);
            },
            onShare: () {
              final biz = ref.read(businessProvider).value?.name ?? '';
              SharePlus.instance.share(
                ShareParams(text: s.shareFormText(biz, form.url)),
              );
            },
            onAutoCall: (v) => _setAutoCall(form, v),
            onRevoke: () => _revoke(form),
          ),
        SectionLabel(s.websiteConnections),
        Text(
          s.websiteConnectionsHint,
          style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 12),
        for (final h in hooks) ...[
          _WebhookCard(
            source: h,
            busy: _busy.contains(h.id),
            onAutoCall: (v) => _setAutoCall(h, v),
            onRevoke: () => _revoke(h),
          ),
          const SizedBox(height: 10),
        ],
        SecondaryButton(
          key: const Key('lead-capture-add-webhook'),
          label: s.addWebsiteConnection,
          icon: Icons.add_link_rounded,
          onPressed: _creatingHook ? null : _createWebhook,
        ),
      ],
    );
  }
}

class _AutoCallSwitch extends StatelessWidget {
  const _AutoCallSwitch({
    required this.source,
    required this.busy,
    required this.onChanged,
  });
  final LeadSource source;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SwitchListTile(
      key: Key('lead-capture-autocall-${source.id}'),
      contentPadding: EdgeInsets.zero,
      title: Text(s.autoCallNewEnquiries),
      subtitle: Text(s.autoCallHint),
      value: source.autoCall,
      onChanged: busy ? null : onChanged,
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.source,
    required this.busy,
    required this.onCopy,
    required this.onShare,
    required this.onAutoCall,
    required this.onRevoke,
  });
  final LeadSource source;
  final bool busy;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final ValueChanged<bool> onAutoCall;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return AppCard(
      key: const Key('lead-capture-form'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.enquiryFormHint, style: t.bodySmall),
          const SizedBox(height: 12),
          SelectableText(
            source.url,
            key: const Key('lead-capture-form-url'),
            style: t.titleSmall?.copyWith(color: AppColors.brand),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                // QR codes need dark-on-light to scan, in both themes.
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Semantics(
                label: s.showQr,
                image: true,
                child: QrImageView(
                  key: const Key('lead-capture-qr'),
                  data: source.url,
                  size: 168,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  key: const Key('lead-capture-copy'),
                  label: s.copyLink,
                  icon: Icons.copy_rounded,
                  onPressed: onCopy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(
                  key: const Key('lead-capture-share'),
                  label: s.shareLink,
                  icon: Icons.share_outlined,
                  onPressed: onShare,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AutoCallSwitch(source: source, busy: busy, onChanged: onAutoCall),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.enquiriesCount(source.leadsCount),
                  style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ),
              TextButton(
                key: Key('lead-capture-revoke-${source.id}'),
                onPressed: busy ? null : onRevoke,
                child: Text(s.turnOff),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WebhookCard extends StatelessWidget {
  const _WebhookCard({
    required this.source,
    required this.busy,
    required this.onAutoCall,
    required this.onRevoke,
  });
  final LeadSource source;
  final bool busy;
  final ValueChanged<bool> onAutoCall;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return AppCard(
      key: Key('lead-capture-webhook-${source.id}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.language_rounded, color: AppColors.inkSoft, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(s.websiteConnection, style: t.titleSmall)),
              TextButton(
                key: Key('lead-capture-revoke-${source.id}'),
                onPressed: busy ? null : onRevoke,
                child: Text(s.turnOff),
              ),
            ],
          ),
          Text(
            source.url,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
          Text(
            s.enquiriesCount(source.leadsCount),
            style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
          _AutoCallSwitch(source: source, busy: busy, onChanged: onAutoCall),
        ],
      ),
    );
  }
}

/// Shows a new webhook's address and secret key. The key is never shown
/// again, so the sheet says so and offers one-tap copies.
Future<void> showWebhookTokenSheet(BuildContext context, LeadSource source) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _WebhookTokenSheet(source: source),
  );
}

class _WebhookTokenSheet extends StatefulWidget {
  const _WebhookTokenSheet({required this.source});
  final LeadSource source;

  @override
  State<_WebhookTokenSheet> createState() => _WebhookTokenSheetState();
}

class _WebhookTokenSheetState extends State<_WebhookTokenSheet> {
  String? _copied;

  void _copy(String what, String text) {
    Clipboard.setData(ClipboardData(text: text));
    // Feedback inside the sheet: a snackbar would show behind the modal.
    setState(() => _copied = what);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final src = widget.source;
    final token = src.token ?? '';
    final setup =
        'POST ${src.url}\nAuthorization: Bearer $token\n'
        'Content-Type: application/json\n\n'
        '{"name": "...", "phone": "+91...", "interest": "...", "consent": true}';

    Widget field(String label, String value, String key) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: t.labelLarge),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                value,
                key: Key('lead-capture-sheet-$key'),
                style: t.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
            IconButton(
              tooltip: _copied == key ? s.copied : label,
              icon: Icon(
                _copied == key ? Icons.check_rounded : Icons.copy_rounded,
              ),
              onPressed: () => _copy(key, value),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.websiteConnection, style: t.titleLarge),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warmSoft,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Text(
                  s.tokenShownOnce,
                  key: const Key('lead-capture-sheet-warning'),
                  style: t.bodySmall?.copyWith(color: AppColors.warmInk),
                ),
              ),
              const SizedBox(height: 16),
              field(s.webhookUrl, src.url, 'url'),
              field(s.secretKey, token, 'token'),
              if (_copied != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    s.copied,
                    key: const Key('lead-capture-sheet-copied'),
                    style: t.bodySmall?.copyWith(color: AppColors.success),
                  ),
                ),
              SecondaryButton(
                key: const Key('lead-capture-sheet-copy-setup'),
                label: s.copyForDeveloper,
                icon: Icons.code_rounded,
                onPressed: () => _copy('setup', setup),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: s.done,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
