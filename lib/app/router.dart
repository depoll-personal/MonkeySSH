import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/screens/home_screen.dart';

/// Provider for the app router.
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  ),
);

/// Route names for type-safe navigation.
abstract final class Routes {
  /// Home screen route.
  static const home = 'home';

  /// Hosts list route.
  static const hosts = 'hosts';

  /// Host detail/edit route.
  static const hostDetail = 'host-detail';

  /// Terminal session route.
  static const terminal = 'terminal';

  /// SFTP browser route.
  static const sftp = 'sftp';

  /// Keys management route.
  static const keys = 'keys';

  /// Snippets route.
  static const snippets = 'snippets';

  /// Settings route.
  static const settings = 'settings';
}
