import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/lock_service.dart';

final lockServiceProvider = Provider<LockService>((ref) => LockService());

/// 设备是否支持（且已录入）指纹
final biometricSupportProvider = FutureProvider<bool>((ref) async {
  return ref.read(lockServiceProvider).supportsBiometrics();
});

/// 屏幕锁状态
class LockState {
  const LockState({
    this.ready = false,
    this.pinEnabled = false,
    this.biometricEnabled = false,
    this.autoLock = true,
    this.locked = false,
  });

  /// 是否已从本地读取完配置
  final bool ready;
  final bool pinEnabled;
  final bool biometricEnabled;

  /// 离开 App 超过阈值后自动上锁
  final bool autoLock;

  /// 当前是否处于锁定态
  final bool locked;

  bool get hasPin => pinEnabled;

  LockState copyWith({
    bool? ready,
    bool? pinEnabled,
    bool? biometricEnabled,
    bool? autoLock,
    bool? locked,
  }) =>
      LockState(
        ready: ready ?? this.ready,
        pinEnabled: pinEnabled ?? this.pinEnabled,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        autoLock: autoLock ?? this.autoLock,
        locked: locked ?? this.locked,
      );
}

class LockNotifier extends Notifier<LockState> {
  @override
  LockState build() {
    _restore();
    return const LockState();
  }

  LockService get _svc => ref.read(lockServiceProvider);

  Future<void> _restore() async {
    final cfg = await _svc.readConfig();
    state = LockState(
      ready: true,
      pinEnabled: cfg.pinEnabled,
      biometricEnabled: cfg.biometricEnabled,
      autoLock: cfg.autoLock,
      // 冷启动：只要开了密码锁就先拦住
      locked: cfg.pinEnabled,
    );
  }

  /// 立即上锁（用于切后台回来、或手动锁定）
  void lockNow() {
    if (state.pinEnabled && !state.locked) {
      state = state.copyWith(locked: true);
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    final ok = await _svc.verifyPin(pin);
    if (ok) state = state.copyWith(locked: false);
    return ok;
  }

  Future<BiometricResult> unlockWithBiometric() async {
    final r = await _svc.authenticateBiometric();
    if (r.success) state = state.copyWith(locked: false);
    return r;
  }

  /// 开启 / 重置密码
  Future<void> setPin(String pin) async {
    await _svc.savePin(pin);
    state = state.copyWith(pinEnabled: true, locked: false);
  }

  Future<bool> verifyPin(String pin) => _svc.verifyPin(pin);

  Future<void> disablePin() async {
    await _svc.clearPin();
    state = state.copyWith(
      pinEnabled: false,
      biometricEnabled: false,
      locked: false,
    );
  }

  /// 指纹解锁开关（只有开了密码锁才允许启用）
  Future<void> setBiometric(bool value) async {
    final enabled = state.pinEnabled && value;
    await _svc.setBiometricEnabled(enabled);
    state = state.copyWith(biometricEnabled: enabled);
  }

  Future<void> setAutoLock(bool value) async {
    await _svc.setAutoLock(value);
    state = state.copyWith(autoLock: value);
  }
}

final lockProvider = NotifierProvider<LockNotifier, LockState>(LockNotifier.new);
