import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// "Connect a lead source" on the Get-leads-automatically screen: Google Ads
/// lead forms, IndiaMART and Facebook & Instagram Lead Ads. Leads from each
/// go through the same instant-call pipeline as the enquiry form
/// (backend: services/lead_integrations.ts, API.md §10b).
const integrationKinds = [
  LeadSourceKind.googleAds,
  LeadSourceKind.indiaMart,
  LeadSourceKind.meta,
];

extension LeadSourceKindText on LeadSourceKind {
  String title(S s) => switch (this) {
    LeadSourceKind.googleAds => s.googleAdsName,
    LeadSourceKind.indiaMart => s.indiaMartName,
    LeadSourceKind.meta => s.metaName,
    LeadSourceKind.webhook => s.websiteConnection,
    LeadSourceKind.form => s.enquiryForm,
  };

  String hint(S s) => switch (this) {
    LeadSourceKind.googleAds => s.googleAdsTileHint,
    LeadSourceKind.indiaMart => s.indiaMartTileHint,
    LeadSourceKind.meta => s.metaTileHint,
    _ => '',
  };

  List<String> steps(S s) => switch (this) {
    LeadSourceKind.googleAds => s.googleAdsSteps,
    LeadSourceKind.indiaMart => s.indiaMartSteps,
    LeadSourceKind.meta => s.metaSteps,
    _ => const [],
  };

  IconData get icon => switch (this) {
    LeadSourceKind.googleAds => Icons.campaign_outlined,
    LeadSourceKind.indiaMart => Icons.storefront_outlined,
    LeadSourceKind.meta => Icons.thumb_up_alt_outlined,
    LeadSourceKind.webhook => Icons.language_rounded,
    LeadSourceKind.form => Icons.dynamic_form_outlined,
  };
}

/// One tile per integration: "Connect" when not connected, otherwise its
/// status (enquiries, last check, problem), auto-call switch and turn off.
class IntegrationTile extends StatelessWidget {
  const IntegrationTile({
    super.key,
    required this.kind,
    required this.source,
    required this.busy,
    required this.onConnect,
    required this.onAutoCall,
    required this.onRevoke,
  });

  final LeadSourceKind kind;

  /// The active source of this kind, or null when not connected.
  final LeadSource? source;
  final bool busy;
  final VoidCallback onConnect;
  final ValueChanged<bool> onAutoCall;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final src = source;
    return AppCard(
      key: Key('lead-source-tile-${kind.wire}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(kind.icon, color: AppColors.brand, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind.title(s), style: t.titleSmall),
                    Text(
                      src == null
                          ? kind.hint(s)
                          : '${s.connected} · ${s.enquiriesCount(src.leadsCount)}',
                      style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              if (src == null)
                TextButton(
                  key: Key('lead-source-connect-${kind.wire}'),
                  onPressed: onConnect,
                  child: Text(s.connect),
                )
              else
                TextButton(
                  key: Key('lead-capture-revoke-${src.id}'),
                  onPressed: busy ? null : onRevoke,
                  child: Text(s.turnOff),
                ),
            ],
          ),
          if (src != null) ...[
            if (src.lastSyncedAt != null)
              Padding(
                padding: const EdgeInsets.only(left: 34, top: 2),
                child: Text(
                  s.lastChecked(s.relative(src.lastSyncedAt!)),
                  style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ),
            if (src.hasProblem) ...[
              const SizedBox(height: 8),
              Container(
                key: Key('lead-source-problem-${src.id}'),
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.warmSoft,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Text(
                  s.sourceProblem(src.lastError!),
                  style: t.bodySmall?.copyWith(color: AppColors.warmInk),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: Key('lead-source-reconnect-${src.id}'),
                  onPressed: onConnect,
                  child: Text(s.connect),
                ),
              ),
            ],
            SwitchListTile(
              key: Key('lead-capture-autocall-${src.id}'),
              contentPadding: const EdgeInsets.only(right: 8),
              title: Text(s.autoCallNewEnquiries),
              subtitle: Text(s.autoCallHint),
              value: src.autoCall,
              onChanged: busy ? null : onAutoCall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Plain-language steps, the fields the integration needs, and after
/// connecting the one-time URL / key with copy buttons. Errors show inside
/// the sheet (a snackbar would sit behind the modal). When [replaces] is set
/// (reconnecting a broken source), the old source is turned off once the new
/// one is connected.
Future<void> showIntegrationSheet(
  BuildContext context,
  LeadSourceKind kind, {
  LeadSource? replaces,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => IntegrationSheet(kind: kind, replaces: replaces),
  );
}

class IntegrationSheet extends ConsumerStatefulWidget {
  const IntegrationSheet({super.key, required this.kind, this.replaces});
  final LeadSourceKind kind;
  final LeadSource? replaces;

  @override
  ConsumerState<IntegrationSheet> createState() => _IntegrationSheetState();
}

class _IntegrationSheetState extends ConsumerState<IntegrationSheet> {
  final _crmKey = TextEditingController();
  final _appSecret = TextEditingController();
  final _pageToken = TextEditingController();
  bool _busy = false;
  String? _error;
  LeadSource? _created;
  String? _copied;

  static final _appSecretPattern = RegExp(r'^[A-Za-z0-9]{16,128}$');

  @override
  void dispose() {
    _crmKey.dispose();
    _appSecret.dispose();
    _pageToken.dispose();
    super.dispose();
  }

  /// Same rules as the backend schema, with friendlier words.
  String? _validate(S s) {
    switch (widget.kind) {
      case LeadSourceKind.indiaMart:
        return _crmKey.text.trim().length < 8 ? s.crmKeyMissing : null;
      case LeadSourceKind.meta:
        final token = _pageToken.text.trim();
        final ok =
            _appSecretPattern.hasMatch(_appSecret.text.trim()) &&
            token.length >= 20 &&
            !token.contains(RegExp(r'\s'));
        return ok ? null : s.metaSecretsInvalid;
      default:
        return null;
    }
  }

  Future<void> _connect() async {
    final s = context.s;
    final invalid = _validate(s);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(leadSourceRepoProvider);
      final created = await repo.create(
        widget.kind,
        secrets: LeadSourceSecrets(
          crmKey: widget.kind == LeadSourceKind.indiaMart ? _crmKey.text : null,
          appSecret: widget.kind == LeadSourceKind.meta
              ? _appSecret.text
              : null,
          pageAccessToken: widget.kind == LeadSourceKind.meta
              ? _pageToken.text
              : null,
        ),
      );
      final old = widget.replaces;
      if (old != null) await repo.revoke(old.id);
      ref.invalidate(leadSourcesProvider);
      if (!mounted) return;
      setState(() {
        _created = created;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e, s);
      });
    }
  }

  void _copy(String what, String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = what);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.page,
          0,
          AppSpace.page,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: Key('integration-sheet-${widget.kind.wire}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(widget.kind.icon, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.kind.title(s), style: t.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._created == null ? _form(s, t) : _result(s, t, _created!),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _form(S s, TextTheme t) {
    final steps = widget.kind.steps(s);
    InputDecoration deco(String label) => InputDecoration(labelText: label);
    return [
      Text(s.howToConnect, style: t.labelLarge),
      const SizedBox(height: 6),
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 22, child: Text('${i + 1}.', style: t.bodySmall)),
              Expanded(child: Text(steps[i], style: t.bodySmall)),
            ],
          ),
        ),
      const SizedBox(height: 8),
      if (widget.kind == LeadSourceKind.indiaMart)
        TextField(
          key: const Key('integration-sheet-crm-key'),
          controller: _crmKey,
          decoration: deco(s.crmKeyLabel),
          autocorrect: false,
          enableSuggestions: false,
        ),
      if (widget.kind == LeadSourceKind.meta) ...[
        TextField(
          key: const Key('integration-sheet-app-secret'),
          controller: _appSecret,
          decoration: deco(s.appSecretLabel),
          autocorrect: false,
          enableSuggestions: false,
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('integration-sheet-page-token'),
          controller: _pageToken,
          decoration: deco(s.pageTokenLabel),
          autocorrect: false,
          enableSuggestions: false,
          maxLines: 2,
          minLines: 1,
        ),
      ],
      if (widget.kind != LeadSourceKind.googleAds) ...[
        const SizedBox(height: 6),
        Text(
          s.secretsStoredSafely,
          style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(
          _error!,
          key: const Key('integration-sheet-error'),
          style: t.bodySmall?.copyWith(color: AppColors.hot),
        ),
      ],
      const SizedBox(height: 16),
      PrimaryButton(
        key: const Key('integration-sheet-connect'),
        label: s.connect,
        icon: Icons.link_rounded,
        loading: _busy,
        onPressed: _busy ? null : _connect,
      ),
    ];
  }

  List<Widget> _result(S s, TextTheme t, LeadSource src) {
    final token = src.token ?? '';
    final fields = <(String, String, String)>[
      ...switch (widget.kind) {
        LeadSourceKind.googleAds => [
          (s.webhookUrl, src.url, 'url'),
          (s.googleKeyLabel, token, 'token'),
        ],
        LeadSourceKind.meta => [
          (s.callbackUrlLabel, src.url, 'url'),
          (s.verifyTokenLabel, token, 'token'),
        ],
        LeadSourceKind.indiaMart => [
          (s.pushUrlLabel, src.pushUrl ?? '${src.url}?key=$token', 'push'),
        ],
        _ => <(String, String, String)>[],
      },
    ];
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Text(
          '${s.connected}. ${s.integrationShownOnce}',
          key: const Key('integration-sheet-connected'),
          style: t.bodySmall,
        ),
      ),
      const SizedBox(height: 16),
      for (final (label, value, key) in fields) ...[
        Text(label, style: t.labelLarge),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                value,
                key: Key('integration-sheet-field-$key'),
                style: t.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
            IconButton(
              key: Key('integration-sheet-copy-$key'),
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
      if (_copied != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            s.copied,
            key: const Key('integration-sheet-copied'),
            style: t.bodySmall?.copyWith(color: AppColors.success),
          ),
        ),
      PrimaryButton(
        key: const Key('integration-sheet-done'),
        label: s.done,
        onPressed: () => Navigator.pop(context),
      ),
    ];
  }
}
