import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../../services/notifications/notification_service.dart';

export '../../services/notifications/notification_service.dart'
    show splitNotificationTitle, plainNotificationTitle, notificationTitleFor;

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final n = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.notifications)),
      body: AsyncView<List<AppNotification>>(
        value: n,
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (items) => items.isEmpty
            ? EmptyState(
                title: s.allCaughtUp,
                message: s.nothingNeedsYou,
                mascot: MascotState.success,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  8,
                  AppSpace.page,
                  32,
                ),
                children: [
                  Reveal(
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                height: 1,
                                indent: 70,
                                endIndent: 16,
                              ),
                            Reveal(
                              id: 'notif-${items[i].id}',
                              index: i < 8 ? i : 0,
                              offset: 8,
                              child: _NotificationRow(
                                n: items[i],
                                onTap: () async {
                                  final x = items[i];
                                  await ref
                                      .read(notificationRepoProvider)
                                      .markRead(x.id);
                                  ref.invalidate(notificationsProvider);
                                  if (context.mounted) context.push(x.route);
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final title = notificationTitleFor(s, n);
    final (color, tint) = switch (n.type) {
      NotificationType.hotLead => (AppColors.hot, AppColors.hotSoft),
      NotificationType.followUpReady => (
        AppColors.whatsapp,
        AppColors.whatsappSoft,
      ),
      NotificationType.callback => (AppColors.info, AppColors.infoSoft),
      NotificationType.campaign => (AppColors.success, AppColors.successSoft),
    };
    return Semantics(
      button: true,
      label: '${n.read ? '' : '${s.unread}. '}$title. ${n.body}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              IconBubble(
                color: tint,
                size: 40,
                child: Icon(
                  AppIcons.notification(n.type),
                  size: 19,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: t.titleSmall?.copyWith(
                              fontWeight: n.read
                                  ? FontWeight.w600
                                  : FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          s.relative(n.createdAt),
                          style: t.bodySmall?.copyWith(
                            color: AppColors.inkFaint,
                          ),
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.body,
                      style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 8,
                child: PopSwitcher(
                  child: n.read
                      ? const SizedBox(key: ValueKey('read'))
                      : Container(
                          key: const ValueKey('unread'),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.brand,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Foreground in-app banner shown when a notification arrives.
class InAppNotificationBanner extends StatelessWidget {
  const InAppNotificationBanner({
    super.key,
    required this.n,
    required this.onOpen,
    required this.onClose,
  });
  final AppNotification n;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final (color, _) = _tone(n.type);
    return Material(
      color: Colors.transparent,
      child: Dismissible(
        key: ValueKey(n.id),
        direction: DismissDirection.up,
        onDismissed: (_) => onClose(),
        child: Pressable(
          onTap: onOpen,
          scale: 0.97,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            decoration: BoxDecoration(
              color: AppColors.strong,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MascotAvatar(
                      size: 42,
                      state: n.type == NotificationType.hotLead
                          ? MascotState.hotLead
                          : MascotState.success,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: PopIn(
                        delay: const Duration(milliseconds: 220),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.strong,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            AppIcons.notification(n.type),
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        notificationTitleFor(s, n),
                        style: t.titleSmall?.copyWith(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n.body,
                        style: t.bodySmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1D4FD8),
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontFamilyFallback: AppTheme.fontFallback,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: onOpen,
                  child: Text(s.isEn ? n.actionLabel : s.open),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// (accent, tint) per notification type, readable in both themes.
(Color, Color) _tone(NotificationType t) => switch (t) {
  NotificationType.hotLead => (AppColors.hotFill, AppColors.hotSoft),
  NotificationType.followUpReady => (
    AppColors.whatsappFill,
    AppColors.whatsappSoft,
  ),
  NotificationType.callback => (AppColors.info, AppColors.infoSoft),
  NotificationType.campaign => (AppColors.success, AppColors.successSoft),
};
