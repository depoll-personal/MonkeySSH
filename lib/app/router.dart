import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/services/auth_service.dart';
import '../presentation/screens/auth_setup_screen.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/screens/lock_screen.dart';

/// Provider for the app router.
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLocked = authState == AuthState.locked;
      final isNotConfigured = authState == AuthState.notConfigured;
      final isOnLockScreen = state.matchedLocation == '/lock';
      final isOnSetupScreen = state.matchedLocation == '/auth-setup';

      if (isLocked && !isOnLockScreen) {
        return '/lock';
      }

      if (isNotConfigured && !isOnSetupScreen && !isOnLockScreen) {
        // Allow skipping setup, so don't force redirect
        return null;
      }

      if (!isLocked &&
          !isNotConfigured &&
          (isOnLockScreen || isOnSetupScreen)) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/lock',
        name: 'lock',
        builder: (context, state) => const LockScreen(),
      ),
      GoRoute(
        path: '/auth-setup',
        name: 'auth-setup',
        builder: (context, state) => const AuthSetupScreen(),
      ),
    ],
  );
});

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
