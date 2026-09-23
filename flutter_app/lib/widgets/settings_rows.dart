import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common.dart';

/// A settings row that navigates or fires an action.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.description,
    this.tone = Tone.neutral,
    this.trailing,
    this.onTap,
    this.trailingWidget,
  });

  final IconData icon;
  final String label;
  final String? description;
  final Tone tone;
  final String? trailing;
  final VoidCallback? onTap;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SurfaceCard(
        onTap: onTap,
        radius: AppRadius.xl,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            IconTile(icon: icon, tone: tone),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
                  if (description != null)
                    Text(
                      description!,
                      style: AppText.caption.copyWith(color: AppColors.inkSoft),
                    ),
                ],
              ),
            ),
            if (trailingWidget != null)
              trailingWidget!
            else ...[
              if (trailing != null)
                Text(trailing!, style: AppText.caption.copyWith(color: AppColors.inkSoft)),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft, size: 20),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// A settings row with a switch.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.icon,
    required this.label,
    this.description,
    this.tone = Tone.neutral,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String? description;
  final Tone tone;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      label: label,
      description: description,
      tone: tone,
      trailingWidget: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// A plain labelled value, used on the usage and subscription screens.
class KeyValueTile extends StatelessWidget {
  const KeyValueTile({super.key, required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SurfaceCard(
        radius: AppRadius.lg,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Text(label, style: AppText.caption.copyWith(color: AppColors.inkSoft)),
            const Spacer(),
            Text(
              value,
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w700,
                color: tone?.foreground ?? AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled text field styled like the rest of the app.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.controller,
    required this.label,
    this.keyboard,
    this.lines = 1,
    this.filled = true,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboard;
  final int lines;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: lines,
      enabled: filled,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.caption.copyWith(color: AppColors.inkSoft),
        filled: filled,
        fillColor: filled ? AppColors.surface : AppColors.secondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
      style: AppText.body,
    );
  }
}
