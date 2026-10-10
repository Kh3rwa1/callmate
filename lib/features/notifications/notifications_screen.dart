import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

/// Splits a backend title like "🔥 Hot lead detected" into its leading
/// emoji (rendered as a line icon) and the plain words.
(String, String) splitNotificationTitle(String title) {
  final chars = title.characters;
  if (chars.isEmpty) return ('', title);
  final first = chars.first;
  final isLetter = RegExp(r'^[\p{L}\p{N}]', unicode: true).hasMatch(first);
  if (isLetter) return ('', title);
  return (first, chars.skip(1).toString().trim());
}

/// The notification title without its emoji prefix.
String plainNotificationTitle(String title) => splitNotificationTitle(title).$2;

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: AsyncView<List<AppNotification>>(
        value: n,
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (items) => items.isEmpty
            ? const EmptyState(
                title: 'All caught up',
                message: 'Nothing needs you right now.',
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
                            _NotificationRow(
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
    final t = Theme.of(context).textTheme;
    final (emoji, title) = splitNotificationTitle(n.title);
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
      label: '${n.read ? '' : 'Unread. '}$title. ${n.body}. ${n.actionLabel}',
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
                child: emoji.isEmpty
                    ? Icon(Icons.notifications_none_rounded, color: color)
                    : Emoji(emoji, size: 19, color: color),
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
                                  : FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          Fmt.relative(n.createdAt),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 8,
                child: n.read
                    ? null
                    : Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.brand,
                          shape: BoxShape.circle,
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
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
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
                    Text(
                      plainNotificationTitle(n.title),
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
                  foregroundColor: AppColors.ink,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontFamily: AppTheme.fontFamily,

                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
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
