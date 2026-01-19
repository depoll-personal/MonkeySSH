import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

/// The root widget of the Flutty application.
class FluttyApp extends ConsumerWidget {
  /// Creates a new [FluttyApp].
  const FluttyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Flutty',
      debugShowCheckedModeBanner: false,
      theme: FluttyTheme.light,
      darkTheme: FluttyTheme.dark,
      routerConfig: router,
    );
  }
}
