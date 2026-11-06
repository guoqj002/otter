import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/lock_provider.dart';
import '../../application/services/lock_service.dart';
import '../../core/theme/app_theme.dart';
import 'pin_pad.dart';

enum PinSetupMode {
  /// 首次开启密码锁
  create,

  /// 修改密码：先验证旧的，再设置新的
  change,

  /// 仅验证（用于关闭密码锁等敏感操作）
  verify,
}

/// 设置 / 修改 / 验证密码的全屏页
class PinSetupPage extends ConsumerStatefulWidget {
  const PinSetupPage({super.key, required this.mode});

  final PinSetupMode mode;

  static Future<bool?> push(BuildContext context, PinSetupMode mode) {
    return Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PinSetupPage(mode: mode),
      ),
    );
  }

  @override
  ConsumerState<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends ConsumerState<PinSetupPage>
    with SingleTickerProviderStateMixin {
  final StringBuffer _pin = StringBuffer();
  String? _error;
  bool _busy = false;

  /// 0 = 验证旧密码（change/verify）、1 = 输入新密码、2 = 确认新密码
  int _stage = 0;
  String? _firstNewPin;

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
    if (widget.mode == PinSetupMode.create) _stage = 1;
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  (String, String) get _copy {
    switch (widget.mode) {
      case PinSetupMode.create:
        return _stage == 1
            ? ('设置密码', '请输入 6 位数字密码')
            : ('确认密码', '请再次输入相同的密码');
      case PinSetupMode.change:
        return switch (_stage) {
          0 => ('验证当前密码', '修改前需要先验证身份'),
          1 => ('设置新密码', '请输入 6 位数字密码'),
          _ => ('确认新密码', '请再次输入相同的密码'),
        };
      case PinSetupMode.verify:
        return ('输入密码', '请输入当前 6 位密码');
    }
  }

  void _onDigit(String d) {
    if (_busy || _pin.length >= LockService.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin.write(d);
      _error = null;
    });
    if (_pin.length == LockService.pinLength) {
      _handleComplete(_pin.toString());
    }
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

  void _fail(String message, {bool shake = true}) {
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _pin.clear();
      _error = message;
    });
    if (shake) _shakeCtrl.forward(from: 0);
  }

  Future<void> _handleComplete(String pin) async {
    setState(() => _busy = true);
    final notifier = ref.read(lockProvider.notifier);

    // 1) 验证旧密码阶段
    if (widget.mode == PinSetupMode.verify ||
        (widget.mode == PinSetupMode.change && _stage == 0)) {
      final ok = await notifier.verifyPin(pin);
      if (!mounted) return;
      if (!ok) {
        _fail('密码不正确，请重试');
        return;
      }
      if (widget.mode == PinSetupMode.verify) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _busy = false;
        _pin.clear();
        _stage = 1;
      });
      return;
    }

    // 2) 输入新密码阶段
    if (_stage == 1) {
      setState(() {
        _busy = false;
        _firstNewPin = pin;
        _pin.clear();
        _stage = 2;
      });
      return;
    }

    // 3) 确认阶段
    if (pin != _firstNewPin) {
      setState(() {
        _firstNewPin = null;
        _stage = 1;
      });
      _fail('两次输入不一致，请重新设置');
      return;
    }

    await notifier.setPin(pin);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (title, subtitle) = _copy;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 64,
                        height: 64,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.seed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Image.asset(
                          'assets/habit_icons/otter_face.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Column(
                          key: ValueKey('$title-$_stage'),
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 19, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text(subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      AnimatedBuilder(
                        animation: _shake,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(_shake.value, 0),
                          child: child,
                        ),
                        child:
                            PinDots(filled: _pin.length, error: _error != null),
                      ),
                      const SizedBox(height: 14),
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
                      const SizedBox(height: 10),
                      PinPad(
                        onDigit: _onDigit,
                        onBackspace: _onBackspace,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        widget.mode == PinSetupMode.verify
                            ? '密码只保存在本机'
                            : '密码仅保存在本机，忘记后需清除 App 数据才能重设',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
