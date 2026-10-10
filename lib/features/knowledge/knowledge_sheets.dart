import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// Bottom sheet that collects website / FAQ / pasted text.
Future<KnowledgeInput?> showKnowledgeInputSheet(
  BuildContext context,
  KnowledgeType type,
) {
  return showModalBottomSheet<KnowledgeInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _KnowledgeSheet(type: type),
  );
}

class _KnowledgeSheet extends StatefulWidget {
  const _KnowledgeSheet({required this.type});
  final KnowledgeType type;
  @override
  State<_KnowledgeSheet> createState() => _KnowledgeSheetState();
}

class _KnowledgeSheetState extends State<_KnowledgeSheet> {
  final _c = TextEditingController();
  final _title = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _c.dispose();
    _title.dispose();
    super.dispose();
  }

  bool get _isWeb => widget.type == KnowledgeType.website;

  void _save() {
    final s = context.s;
    if (!_form.currentState!.validate()) return;
    final v = _c.text.trim();
    KnowledgeInput input;
    if (_isWeb) {
      final url = v.startsWith('http') ? v : 'https://$v';
      input = KnowledgeInput(
        type: KnowledgeType.website,
        title: s.websiteTitle,
        url: url,
      );
    } else {
      final title = _title.text.trim().isNotEmpty
          ? _title.text.trim()
          : (widget.type == KnowledgeType.faq ? s.faqTitle : s.notesTitle);
      input = KnowledgeInput(type: widget.type, title: title, content: v);
    }
    Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final (title, hint) = switch (widget.type) {
      KnowledgeType.website => (s.addWebsite, 'yourbusiness.in'),
      KnowledgeType.faq => (s.addFaq, s.hintFaq),
      KnowledgeType.businessInfo => (s.addBusinessInfo, s.hintBusinessInfo),
      _ => (s.pasteInformation, s.hintServices),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.titleLarge),
              const SizedBox(height: 16),
              if (!_isWeb) ...[
                TextFormField(
                  controller: _title,
                  decoration: InputDecoration(hintText: s.titleOptional),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _c,
                autofocus: true,
                keyboardType: _isWeb
                    ? TextInputType.url
                    : TextInputType.multiline,
                maxLines: _isWeb ? 1 : 8,
                minLines: _isWeb ? 1 : 5,
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: _isWeb
                      ? const Icon(Icons.language_rounded)
                      : null,
                ),
                validator: (v) {
                  final v2 = (v ?? '').trim();
                  if (v2.isEmpty) return s.pleaseAddSomething;
                  if (_isWeb &&
                      !RegExp(
                        r'^(https?://)?[\w-]+(\.[\w-]+)+(/\S*)?$',
                      ).hasMatch(v2)) {
                    return s.enterValidWebsite;
                  }
                  if (!_isWeb && v2.length < 10) {
                    return s.addMoreDetail;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              PrimaryButton(label: s.addToKnowledge, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
