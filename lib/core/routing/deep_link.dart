import 'package:go_router/go_router.dart';

/// Opens an in-app route from a notification (local or push) with a sensible
/// back stack: the owning tab first, then the detail on top of it.
void openDeepLink(GoRouter router, String route) {
  if (!route.startsWith('/') || route.endsWith('/')) {
    router.go('/home');
    return;
  }
  if (route.startsWith('/followups/')) {
    router.go('/followups');
  } else if (route.startsWith('/leads/')) {
    router.go('/leads');
  } else if (route.startsWith('/calls/')) {
    router.go('/calls');
  }
  if (route.split('/').length > 2 ||
      route.contains('/campaigns/') ||
      route == '/callbacks') {
    router.push(route);
  } else {
    router.go(route);
  }
}
