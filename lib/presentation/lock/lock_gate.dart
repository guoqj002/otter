import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/lock_provider.dart';
import 'lock_screen.dart';

/// 锁屏守卫：以覆盖层方式拦在 App 之上。
///
/// 用覆盖层而不是路由跳转，好处是解锁后能回到原来的位置，
/// 底部页面（含表单草稿、滚动位置）不会被销毁。
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  /// 切到后台超过这个时长，回来后重新上锁
  static const Duration _grace = Duration(seconds: 30);

  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    final leftAt = _leftAt;
    _leftAt = null;
    if (leftAt == null) return;
    final lock = ref.read(lockProvider);
    if (!lock.pinEnabled || !lock.autoLock || lock.locked) return;
    if (DateTime.now().difference(leftAt) >= _grace) {
      ref.read(lockProvider.notifier).lockNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 上锁瞬间收起系统键盘，避免盖在锁屏上
    ref.listen(lockProvider.select((s) => s.locked), (previous, next) {
      if (next) FocusManager.instance.primaryFocus?.unfocus();
    });
    final locked = ref.watch(lockProvider.select((s) => s.locked));

    return Stack(
      fit: StackFit.expand,
      children: [
        // 保持子树常驻，锁屏时被不透明的锁屏页完全盖住
        TickerMode(enabled: !locked, child: widget.child),
        if (locked) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}
