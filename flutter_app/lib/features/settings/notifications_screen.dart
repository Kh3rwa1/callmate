import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_rows.dart';

/// Which notifications the owner wants. Stored on the device, since they are a
/// personal preference rather than business data.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Map<String, bool> _enabled = {
    'calls': true,
    'bookings': true,
    'followUps': true,
    'payments': true,
  };

  static const _meta = {
    'calls': ('Call updates', 'When a calling round finishes', Icons.phone_in_talk_rounded),
    'bookings': ('New bookings', 'When a customer books an appointment', Icons.event_available_rounded),
    'followUps': ('Follow-ups due', 'A reminder when a follow-up is waiting', Icons.alarm_rounded),
    'payments': ('Payments recovered', 'When a pending payment is collected', Icons.savings_rounded),
  };

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Notifications',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What should we tell you about?', style: AppText.hero),
          const SizedBox(height: AppSpacing.lg),
          for (final entry in _meta.entries)
            SwitchRow(
              icon: entry.value.$3,
              tone: Tone.blue,
              label: entry.value.$1,
              description: entry.value.$2,
              value: _enabled[entry.key] ?? true,
              onChanged: (value) {
                setState(() => _enabled[entry.key] = value);
                showAppToast(context, '${entry.value.$1} ${value ? 'on' : 'off'}');
              },
            ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'These preferences are kept on this device.',
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
