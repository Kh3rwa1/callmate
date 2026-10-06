import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final n = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: AsyncView<List<AppNotification>>(
        value: n,
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (items) => items.isEmpty
            ? const EmptyState(
                title: 'All caught up 🎉',
                message: 'We only notify you when something needs your attention.',
                mascot: MascotState.success,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 32),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final x = items[i];
                  return AppCard(
                    padding: const EdgeInsets.all(16),
                    border: x.read ? null : Border.all(color: AppColors.brand.withValues(alpha: 0.35), width: 1.5),
                    onTap: () async {
                      await ref.read(notificationRepoProvider).markRead(x.id);
                      ref.invalidate(notificationsProvider);
                      if (context.mounted) context.push(x.route);
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconBubble(
                          color: switch (x.type) {
                            NotificationType.hotLead => AppColors.hotSoft,
                            NotificationType.followUpReady => AppColors.whatsappSoft,
                            NotificationType.callback => AppColors.infoSoft,
                            NotificationType.campaign => AppColors.successSoft,
                          },
                          size: 44,
                          child: Emoji(x.title.characters.first, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(x.title.characters.skip(2).toString(), style: t.titleSmall)),
                                  Text(Fmt.relative(x.createdAt), style: t.bodySmall),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(x.body, style: t.bodyMedium),
                              const SizedBox(height: 8),
                              Text('${x.actionLabel} →', style: t.labelMedium?.copyWith(color: AppColors.brand, fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Foreground in-app banner shown when a notification arrives.
class InAppNotificationBanner extends StatelessWidget {
  const InAppNotificationBanner({super.key, required this.n, required this.onOpen, required this.onClose});
  final AppNotification n;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: Dismissible(
        key: ValueKey(n.id),
        direction: DismissDirection.up,
        onDismissed: (_) => onClose(),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: Row(
            children: [
              const MascotAvatar(size: 42, state: MascotState.hotLead),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(n.title, style: t.titleSmall?.copyWith(color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      n.body,
                      style: t.bodySmall?.copyWith(color: Colors.white70, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.ink,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                onPressed: onOpen,
                child: Text(n.actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
