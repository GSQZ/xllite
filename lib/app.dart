import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/home/app_shell.dart';
import 'ui/xl_theme.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => const AuthGate())],
  );
});

class XinliLiteApp extends ConsumerWidget {
  const XinliLiteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: '新理Lite',
      debugShowCheckedModeBanner: false,
      theme: XLTheme.light,
      routerConfig: router,
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return authState.when(
      data: (session) => session == null ? const LoginPage() : const AppShell(),
      loading: () => const SplashScreen(),
      error: (error, stackTrace) => LoginPage(initialError: error.toString()),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/branding/xinli_lite_app_icon_1024.png',
                width: 72,
                height: 72,
              ),
            ),
            const SizedBox(height: 18),
            const Text('新理Lite', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
