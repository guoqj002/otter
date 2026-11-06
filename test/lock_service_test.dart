import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitstreak/application/services/lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 测试里用较小的轮数，避免拖慢用例；轮数不影响逻辑正确性
  LockService svc() => LockService(hashRounds: 64);

  test('未设置密码时：密码锁关闭、默认开启自动锁定', () async {
    final cfg = await svc().readConfig();
    expect(cfg.pinEnabled, isFalse);
    expect(cfg.biometricEnabled, isFalse);
    expect(cfg.autoLock, isTrue);
  });

  test('设置密码后可校验，错误密码不通过', () async {
    final s = svc();
    await s.savePin('123456');

    expect(await s.verifyPin('123456'), isTrue);
    expect(await s.verifyPin('123455'), isFalse);
    expect(await s.verifyPin('12345'), isFalse);
    expect(await s.verifyPin(''), isFalse);

    final cfg = await s.readConfig();
    expect(cfg.pinEnabled, isTrue);
  });

  test('密码不落明文，且两次设置产生不同摘要（随机盐）', () async {
    final s = svc();
    await s.savePin('654321');
    final prefs = await SharedPreferences.getInstance();
    final firstHash = prefs.getString('sec_pin_hash');
    final firstSalt = prefs.getString('sec_pin_salt');

    expect(firstHash, isNotNull);
    expect(firstSalt, isNotNull);
    expect(firstHash!.contains('654321'), isFalse);

    await s.savePin('654321');
    expect(prefs.getString('sec_pin_salt'), isNot(firstSalt));
    expect(prefs.getString('sec_pin_hash'), isNot(firstHash));
    // 换了盐之后，同一个密码依然能通过校验
    expect(await s.verifyPin('654321'), isTrue);
  });

  test('关闭密码锁会清空摘要并连带关闭指纹', () async {
    final s = svc();
    await s.savePin('111111');
    await s.setBiometricEnabled(true);
    expect((await s.readConfig()).biometricEnabled, isTrue);

    await s.clearPin();
    final cfg = await s.readConfig();
    expect(cfg.pinEnabled, isFalse);
    expect(cfg.biometricEnabled, isFalse);
    expect(await s.verifyPin('111111'), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sec_pin_hash'), isNull);
    expect(prefs.getString('sec_pin_salt'), isNull);
  });

  test('自动锁定开关可持久化', () async {
    final s = svc();
    await s.setAutoLock(false);
    expect((await s.readConfig()).autoLock, isFalse);

    // 新建实例重新读取（模拟重启）
    expect((await svc().readConfig()).autoLock, isFalse);
  });

  test('改密码后旧密码失效、新密码生效', () async {
    final s = svc();
    await s.savePin('000000');
    await s.savePin('999999');
    expect(await s.verifyPin('000000'), isFalse);
    expect(await s.verifyPin('999999'), isTrue);
  });
}
