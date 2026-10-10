import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';

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
    if (!_form.currentState!.validate()) return;
    final v = _c.text.trim();
    KnowledgeInput input;
    if (_isWeb) {
      final url = v.startsWith('http') ? v : 'https://$v';
      input = KnowledgeInput(
        type: KnowledgeType.website,
        title: 'Website',
        url: url,
      );
    } else {
      final title = _title.text.trim().isNotEmpty
          ? _title.text.trim()
          : (widget.type == KnowledgeType.faq ? 'FAQ' : 'Notes');
      input = KnowledgeInput(type: widget.type, title: title, content: v);
    }
    Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (title, hint) = switch (widget.type) {
      KnowledgeType.website => ('Add website', 'abccoaching.in'),
      KnowledgeType.faq => ('Add FAQ', 'Q: Do you accept UPI?\nA: Yes.'),
      KnowledgeType.businessInfo => (
        'Add business information',
        'Hours, location, payments…',
      ),
      _ => ('Paste information', 'Services, pricing, policies…'),
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
                  decoration: const InputDecoration(
                    hintText: 'Title (optional)',
                  ),
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
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Please add something';
                  if (_isWeb &&
                      !RegExp(
                        r'^(https?://)?[\w-]+(\.[\w-]+)+(/\S*)?$',
                      ).hasMatch(s)) {
                    return 'Enter a valid website';
                  }
                  if (!_isWeb && s.length < 10) {
                    return 'Add a little more detail';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Add to your AI\'s knowledge',
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
