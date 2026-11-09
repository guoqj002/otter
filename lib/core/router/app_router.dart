import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/ai/otter_chat_page.dart';
import '../../presentation/expense/expense_page.dart';
import '../../presentation/home/home_page.dart';
import '../../presentation/habit/habit_edit_page.dart';
import '../../presentation/habit/habit_detail_page.dart';
import '../../presentation/invest/invest_page.dart';
import '../../presentation/onboarding/onboarding_page.dart';
import '../../presentation/onboarding/welcome_page.dart';
import '../../presentation/settings/settings_page.dart';
import '../../presentation/shell/main_shell.dart';
import '../../presentation/stats/stats_page.dart';
import '../../application/providers/settings_provider.dart';
import '../theme/app_theme.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashPage(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomePage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => OnboardingPage(
          isQuickCreate: state.uri.queryParameters['quick'] == '1',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const NoTransitionPage(child: HomePage()),
          ),
          GoRoute(
            path: '/expense',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ExpensePage()),
          ),
          GoRoute(
            path: '/invest',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: InvestPage()),
          ),
          GoRoute(
            path: '/ai',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: OtterChatPage()),
          ),
          GoRoute(
            path: '/stats',
            pageBuilder: (context, state) => const NoTransitionPage(child: StatsPage()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(child: SettingsPage()),
          ),
        ],
      ),
      GoRoute(
        path: '/habit/new',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const HabitEditPage(),
      ),
      GoRoute(
        path: '/habit/:id/edit',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => HabitEditPage(habitId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/habit/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => HabitDetailPage(habitId: state.pathParameters['id']!),
      ),
    ],
  );
});

/// 启动页：读取设置决定进入欢迎页还是主页
class _SplashPage extends ConsumerStatefulWidget {
  const _SplashPage();

  @override
  ConsumerState<_SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<_SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    // 等待 settings 从 SharedPreferences 加载完成
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    final s = ref.read(settingsProvider);
    if (!mounted) return;
    // 未完成引导或还没起昵称 → 先去欢迎页起昵称
    context.go(s.onboarded && s.hasNickname ? '/' : '/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.seed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Image.asset(
                'assets/habit_icons/otter_face.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(height: 20),
            Text('水獭管家',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('每天一点点',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ],
        ),
      ),
    );
  }
}
