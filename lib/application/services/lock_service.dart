import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机安全配置：密码锁 / 指纹 / 自动锁定
class LockConfig {
  const LockConfig({
    this.pinEnabled = false,
    this.biometricEnabled = false,
    this.autoLock = true,
  });

  final bool pinEnabled;
  final bool biometricEnabled;
  final bool autoLock;

  LockConfig copyWith({
    bool? pinEnabled,
    bool? biometricEnabled,
    bool? autoLock,
  }) =>
      LockConfig(
        pinEnabled: pinEnabled ?? this.pinEnabled,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        autoLock: autoLock ?? this.autoLock,
      );
}

/// 生物识别结果
class BiometricResult {
  const BiometricResult.ok()
      : success = true,
        message = null;

  const BiometricResult.failed(this.message) : success = false;

  final bool success;
  final String? message;
}

/// 密码（PIN）与生物识别的本地实现。
///
/// 设计原则：
/// - 密码只保存「随机盐 + 多轮 SHA-256」摘要，绝不落明文；
/// - 所有数据仅存本机，不联网、不上传；
/// - 指纹调用系统能力，App 本身拿不到任何指纹数据。
class LockService {
  LockService({this.hashRounds = 12000});

  /// 密码位数
  static const int pinLength = 6;

  static const _kPinEnabled = 'sec_pin_enabled';
  static const _kPinHash = 'sec_pin_hash';
  static const _kPinSalt = 'sec_pin_salt';
  static const _kBioEnabled = 'sec_biometric_enabled';
  static const _kAutoLock = 'sec_auto_lock';

  /// 摘要迭代轮数（越大越慢，可有效拖慢暴力尝试）
  final int hashRounds;
  final LocalAuthentication _auth = LocalAuthentication();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ---------------------------------------------------------------- 配置读取

  Future<LockConfig> readConfig() async {
    final p = await _p;
    final pinEnabled =
        (p.getBool(_kPinEnabled) ?? false) && (p.getString(_kPinHash) ?? '').isNotEmpty;
    return LockConfig(
      pinEnabled: pinEnabled,
      // 没有密码时指纹解锁无意义，一并视为关闭
      biometricEnabled: pinEnabled && (p.getBool(_kBioEnabled) ?? false),
      autoLock: p.getBool(_kAutoLock) ?? true,
    );
  }

  Future<void> setAutoLock(bool value) async {
    final p = await _p;
    await p.setBool(_kAutoLock, value);
  }

  Future<void> setBiometricEnabled(bool value) async {
    final p = await _p;
    await p.setBool(_kBioEnabled, value);
  }

  // ------------------------------------------------------------------ 密码

  /// 设置（或重置）密码，同时视为开启密码锁
  Future<void> savePin(String pin) async {
    final p = await _p;
    final salt = _randomSalt();
    await p.setString(_kPinSalt, salt);
    await p.setString(_kPinHash, _hash(pin, salt));
    await p.setBool(_kPinEnabled, true);
  }

  Future<bool> verifyPin(String pin) async {
    final p = await _p;
    final salt = p.getString(_kPinSalt);
    final stored = p.getString(_kPinHash);
    if (salt == null || salt.isEmpty || stored == null || stored.isEmpty) {
      return false;
    }
    return _constantTimeEquals(_hash(pin, salt), stored);
  }

  /// 关闭密码锁（同时关闭指纹解锁并抹掉摘要）
  Future<void> clearPin() async {
    final p = await _p;
    await p.remove(_kPinHash);
    await p.remove(_kPinSalt);
    await p.setBool(_kPinEnabled, false);
    await p.setBool(_kBioEnabled, false);
  }

  // ---------------------------------------------------------------- 生物识别

  /// 设备是否具备可用的指纹 / 面容（已录入）
  Future<bool> supportsBiometrics() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      // 桌面端 / 未配置指纹的设备会抛异常，一律降级为不支持
      return false;
    }
  }

  /// 调起系统指纹验证
  Future<BiometricResult> authenticateBiometric({
    String reason = '请验证指纹以解锁水獭管家',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return ok
          ? const BiometricResult.ok()
          : const BiometricResult.failed('指纹验证未通过，请重试');
    } on LocalAuthException catch (e) {
      return BiometricResult.failed(_describe(e.code));
    } catch (_) {
      return const BiometricResult.failed('当前设备不支持指纹验证，请用密码解锁');
    }
  }

  String _describe(LocalAuthExceptionCode code) {
    switch (code) {
      case LocalAuthExceptionCode.userCanceled:
        return '已取消指纹验证';
      case LocalAuthExceptionCode.systemCanceled:
        return '验证被系统中断，请重试';
      case LocalAuthExceptionCode.timeout:
        return '验证超时，请重试';
      case LocalAuthExceptionCode.authInProgress:
        return '验证正在进行中';
      case LocalAuthExceptionCode.noBiometricsEnrolled:
        return '尚未在系统设置中录入指纹';
      case LocalAuthExceptionCode.noBiometricHardware:
        return '此设备不支持指纹识别';
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        return '指纹硬件暂时不可用';
      case LocalAuthExceptionCode.biometricLockout:
      case LocalAuthExceptionCode.temporaryLockout:
        return '指纹验证被暂时锁定，请稍后再试或改用密码';
      case LocalAuthExceptionCode.noCredentialsSet:
        return '设备未设置任何解锁方式';
      case LocalAuthExceptionCode.uiUnavailable:
        return '无法唤起指纹验证，请稍后再试';
      case LocalAuthExceptionCode.userRequestedFallback:
        return '请改用密码解锁';
      default:
        return '指纹验证失败，请用密码解锁';
    }
  }

  // ------------------------------------------------------------------ 工具

  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt|$pin|fitstreak');
    for (var i = 0; i < hashRounds; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
