// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flutty/presentation/screens/home_screen.dart';

void main() {
  group('HomeScreen', () {
    testWidgets('displays app bar with title', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/keys',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/port-forwards',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts/add',
                builder: (context, state) => const Scaffold(),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Flutty'), findsOneWidget);
    });

    testWidgets('displays settings icon button', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/keys',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/port-forwards',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts/add',
                builder: (context, state) => const Scaffold(),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('displays quick connect card', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/keys',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/port-forwards',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts/add',
                builder: (context, state) => const Scaffold(),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Quick Connect'), findsOneWidget);
      expect(find.text('SSH to any host'), findsOneWidget);
    });

    testWidgets('displays navigation cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/keys',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/port-forwards',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts/add',
                builder: (context, state) => const Scaffold(),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Hosts'), findsOneWidget);
      expect(find.text('Keys'), findsOneWidget);
      expect(find.text('Snippets'), findsOneWidget);
      expect(find.text('Port Forward'), findsOneWidget);
    });

    testWidgets('displays manage section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/keys',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/port-forwards',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts/add',
                builder: (context, state) => const Scaffold(),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Manage'), findsOneWidget);
    });

    testWidgets('shows quick connect dialog on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/keys',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/port-forwards',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts/add',
                builder: (context, state) => const Scaffold(),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Quick Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('displays correct icons for navigation cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/keys',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/port-forwards',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts/add',
                builder: (context, state) => const Scaffold(),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
      expect(find.byIcon(Icons.vpn_key_outlined), findsOneWidget);
      expect(find.byIcon(Icons.code_outlined), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz_outlined), findsOneWidget);
    });

    testWidgets('displays card subtitles', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/keys',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/port-forwards',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts/add',
                builder: (context, state) => const Scaffold(),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Manage connections'), findsOneWidget);
      expect(find.text('SSH keys'), findsOneWidget);
      expect(find.text('Saved commands'), findsOneWidget);
      expect(find.text('Tunnels'), findsOneWidget);
    });

    testWidgets('has GridView for navigation cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/keys',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/port-forwards',
                builder: (context, state) => const Scaffold(),
              ),
              GoRoute(
                path: '/hosts/add',
                builder: (context, state) => const Scaffold(),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
    });
  });
}
