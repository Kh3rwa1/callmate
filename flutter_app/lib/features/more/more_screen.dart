import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_rows.dart';
import '../ai/ai_employee_screen.dart';
import '../followups/followups_screen.dart';
import '../settings/business_settings_screen.dart';
import '../settings/notifications_screen.dart';
import '../settings/phone_number_screen.dart';
import '../settings/subscription_screen.dart';
import '../settings/usage_screen.dart';

/// The "More" tab: everything that is not a daily action.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final data = repo.data;
    final usage = data.usage;
    final agent = data.agent;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 32),
        children: [
          Text('More', style: AppText.hero),
          Text(
            'Your AI employee and your account',
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          ),

          const SizedBox(height: AppSpacing.lg),

          SurfaceCard(
            onTap: () => context.open(const AiEmployeeScreen()),
            child: Row(
              children: [
                const Mascot(mood: MascotMood.happy, size: 54),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(agent?.name ?? agentName, style: AppText.title),
                      Text(
                        'Voice, language and working hours',
                        style: AppText.caption.copyWith(color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Your business'),
          SettingsRow(
            icon: Icons.chat_bubble_rounded,
            tone: Tone.green,
            label: 'Follow-ups',
            trailing: '${data.pendingFollowUps.length} pending',
            onTap: () => context.open(const FollowUpsScreen()),
          ),
          SettingsRow(
            icon: Icons.phone_in_talk_rounded,
            tone: Tone.blue,
            label: 'Phone number',
            trailing: data.phoneNumber?.number ?? 'Not set',
            onTap: () => context.open(const PhoneNumberScreen()),
          ),
          SettingsRow(
            icon: Icons.storefront_rounded,
            tone: Tone.purple,
            label: 'Business details',
            trailing: data.organisation.name,
            onTap: () => context.open(const BusinessSettingsScreen()),
          ),
          SettingsRow(
            icon: Icons.notifications_active_rounded,
            tone: Tone.amber,
            label: 'Notifications',
            onTap: () => context.open(const NotificationsScreen()),
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Plan and usage'),
          SettingsRow(
            icon: Icons.insights_rounded,
            tone: Tone.blue,
            label: 'Usage',
            trailing: usage == null ? null : '${usage.minutesUsed} min used',
            onTap: () => context.open(const UsageScreen()),
          ),
          SettingsRow(
            icon: Icons.workspace_premium_rounded,
            tone: Tone.green,
            label: 'Subscription',
            trailing: usage?.planName,
            onTap: () => context.open(const SubscriptionScreen()),
          ),

          const SizedBox(height: AppSpacing.xl),
          Text(
            'Calls are placed by our backend, which keeps your voice service '
            'credentials safe. They never touch this app.',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
