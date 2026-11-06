import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers/data_providers.dart';
import 'application/providers/settings_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/date_utils.dart';
import 'presentation/lock/lock_gate.dart';

class FitStreakApp extends ConsumerStatefulWidget {
  const FitStreakApp({super.key});

  @override
  ConsumerState<FitStreakApp> createState() => _FitStreakAppState();
}

class _FitStreakAppState extends ConsumerState<FitStreakApp>
    with WidgetsBindingObserver {
  Timer? _dayTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayTicker?.cancel();
    super.dispose();
  }

  /// 跨天检测：回到前台 + 定时器双保险，避免"昨天"的 UI 残留
  void _scheduleMidnightCheck() {
    _dayTicker?.cancel();
    _dayTicker = Timer.periodic(const Duration(seconds: 30), (_) => _refreshDay());
  }

  void _refreshDay() {
    final key = Dates.todayStr();
    final notifier = ref.read(todayProvider.notifier);
    if (ref.read(todayProvider) != key) {
      notifier.state = key;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDay();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '水獭管家',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      routerConfig: router,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // 限制文字缩放上限，防止极端字号破坏布局
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3),
          ),
          child: ScrollConfiguration(
            behavior: const _NoGlowBehavior(),
            // 密码 / 指纹锁覆盖在整棵路由之上
            child: LockGate(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}

class _NoGlowBehavior extends MaterialScrollBehavior {
  const _NoGlowBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
