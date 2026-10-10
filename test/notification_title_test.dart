import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:callpilot/services/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _n(NotificationType type, String title) => AppNotification(
  id: 'n',
  type: type,
  title: title,
  body: '',
  route: '/home',
  createdAt: DateTime(2026),
);

void main() {
  test('backend jargon never reaches the owner', () {
    final hot = _n(NotificationType.hotLead, '🔥 Hot lead detected');
    expect(notificationTitleFor(S.en, hot), 'Customer ready to buy');
    expect(
      notificationTitleFor(const S(AppLang.hi), hot),
      'खरीदने को तैयार ग्राहक मिला',
    );
    final cb = _n(NotificationType.callback, '📅 Callback requested');
    expect(notificationTitleFor(S.en, cb), 'Call back requested');
  });

  test('calling updates keep the English title that names the employee', () {
    final done = _n(NotificationType.campaign, '✅ Riya finished calling');
    expect(notificationTitleFor(S.en, done), 'Riya finished calling');
    expect(notificationTitleFor(const S(AppLang.bn), done), 'কলিং আপডেট');
  });

  test('splitNotificationTitle separates the emoji', () {
    expect(splitNotificationTitle('🔥 Hot'), ('🔥', 'Hot'));
    expect(splitNotificationTitle('Plain'), ('', 'Plain'));
  });
}
