import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/lock_provider.dart';
import '../../core/theme/app_theme.dart';
import 'pin_pad.dart';

/// 锁屏：6 位密码 + 指纹快捷解锁
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, this.autoPromptBiometric = true});

  /// 进入后自动唤起指纹（用户取消后不再打扰）
  final bool autoPromptBiometric;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with SingleTickerProviderStateMixin {
  final StringBuffer _pin = StringBuffer();
  String? _error;
  bool _busy = false;
  bool _bioBusy = false;

  late final AnimationController _shakeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _shake = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -8.0, end: 6.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    if (widget.autoPromptBiometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 420), () {
          if (!mounted) return;
          final lock = ref.read(lockProvider);
          if (lock.locked && lock.biometricEnabled) _promptBiometric();
        });
      });
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onDigit(String d) {
    if (_busy || _pin.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin.write(d);
      _error = null;
    });
    if (_pin.length == 6) _submit();
  }

  void _onBackspace() {
    if (_busy || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      final s = _pin.toString();
      _pin
        ..clear()
        ..write(s.substring(0, s.length - 1));
      _error = null;
    });
  }

  Future<void> _submit() async {
    final pin = _pin.toString();
    setState(() => _busy = true);
    final ok = await ref.read(lockProvider.notifier).unlockWithPin(pin);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      return; // 解锁后由 LockGate 移除本页
    }
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _pin.clear();
      _error = '密码不正确，请重试';
    });
    _shakeCtrl.forward(from: 0);
  }

  Future<void> _promptBiometric() async {
    if (_bioBusy || _busy) return;
    setState(() {
      _bioBusy = true;
      _error = null;
    });
    final r = await ref.read(lockProvider.notifier).unlockWithBiometric();
    if (!mounted) return;
    if (r.success) {
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() {
      _bioBusy = false;
      // 用户主动取消时不提示错误
      _error = r.message == '已取消指纹验证' ? null : r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lock = ref.watch(lockProvider);

    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.seed.withValues(alpha: 0.10),
              scheme.surface,
              scheme.surface,
            ],
            stops: const [0, 0.42, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 640;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: compact ? 20 : 40),
                        _avatar(context, compact),
                        SizedBox(height: compact ? 14 : 22),
                        Text(
                          '水獭管家已锁定',
                          style: TextStyle(
                            fontSize: compact ? 17 : 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '输入 6 位密码，或使用指纹解锁',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: compact ? 22 : 30),
                        AnimatedBuilder(
                          animation: _shake,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(_shake.value, 0),
                            child: child,
                          ),
                          child: PinDots(filled: _pin.length, error: _error != null),
                        ),
                        SizedBox(height: compact ? 12 : 18),
                        // 错误提示占位，避免键盘跳动
                        SizedBox(
                          height: 20,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _error == null
                                ? const SizedBox.shrink()
                                : Text(
                                    _error!,
                                    key: ValueKey(_error),
                                    style: TextStyle(
                                        fontSize: 13, color: scheme.error),
                                  ),
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 14),
                        PinPad(
                          onDigit: _onDigit,
                          onBackspace: _onBackspace,
                          onBiometric:
                              lock.biometricEnabled ? _promptBiometric : null,
                          biometricBusy: _bioBusy,
                          enabled: !_busy,
                        ),
                        SizedBox(height: compact ? 16 : 26),
                        Text(
                          '密码与指纹仅在本机校验，不会上传',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, bool compact) {
    final size = compact ? 72.0 : 88.0;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: AppColors.seed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: AppColors.seed.withValues(alpha: 0.18)),
      ),
      child: Image.asset(
        'assets/habit_icons/otter_face.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
