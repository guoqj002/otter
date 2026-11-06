import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitstreak/application/services/backup_service.dart';
import 'package:fitstreak/model/db/app_database.dart';

void main() {
  late AppDatabase db;
  late BackupService service;
  late Directory tmp;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = BackupService(db);
    tmp = Directory.systemTemp.createTempSync('backup_test');
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<Habit> insertHabit(String id, String name) async {
    final row = Habit.fromJson({
      'id': id,
      'name': name,
      'iconCode': 0x1F525,
      'colorHex': 0xFF22C55E,
      'type': 'check',
      'frequency': 'daily',
      'weeklyTarget': 7,
      'weekdaysMask': 127,
      'sortOrder': 0,
      'createdAt': 1700000000000,
      'updatedAt': 1700000000000,
    });
    await db.into(db.habits).insert(row);
    return row;
  }

  test('导出 payload 含全部表与设置，回环导入后数据一致', () async {
    await insertHabit('h1', '俯卧撑');
    await db.into(db.checkIns).insert(CheckIn.fromJson({
      'id': 'c1',
      'habitId': 'h1',
      'localDate': '2026-11-05',
      'doneAt': 1700000000000,
      'value': null,
      'deletedAt': null,
    }));
    await db.into(db.expenses).insert(Expense.fromJson({
      'id': 'e1',
      'category': 'food',
      'amountCents': 1250,
      'type': 'expense',
      'localDate': '2026-11-05',
      'createdAt': 1700000000000,
    }));

    final payload = await service.buildPayload();
    expect(payload['app'], '水獭管家');
    expect(payload['version'], 2);
    expect((payload['habits'] as List).length, 1);
    expect((payload['checkIns'] as List).length, 1);
    expect((payload['expenses'] as List).length, 1);

    // 写文件（writeExportFile 依赖 path_provider，这里手动落盘）→ 清库 → 导入 → 校验
    final file = File('${tmp.path}/roundtrip.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    expect(await file.exists(), isTrue);

    // 清空现有数据（模拟换机）
    await db.delete(db.checkIns).go();
    await db.delete(db.expenses).go();
    await db.delete(db.habits).go();

    final summary = await service.importFrom(file.path);
    expect(summary.habits, 1);
    expect(summary.checkIns, 1);
    expect(summary.expenses, 1);

    expect(await db.select(db.habits).get(), hasLength(1));
    final habit = await db.select(db.habits).getSingle();
    expect(habit.name, '俯卧撑');
    final expense = await db.select(db.expenses).getSingle();
    expect(expense.amountCents, 1250);
    expect(expense.type, 'expense');
    final checkIn = await db.select(db.checkIns).getSingle();
    expect(checkIn.habitId, 'h1');
    expect(checkIn.localDate, '2026-11-05');
  });

  test('兼容 v1 格式：补默认字段、打卡无 id 自动生成', () async {
    final v1 = {
      'app': '水獭管家',
      'version': 1,
      'exportedAt': '2026-10-01T10:00:00',
      'habits': [
        {
          'id': 'h9',
          'name': '读书',
          'type': 'check',
          'frequency': 'daily',
          'archived': false,
          'createdAt': 1700000000000,
        }
      ],
      'checkIns': [
        {'habitId': 'h9', 'localDate': '2026-10-01', 'doneAt': 1700000000000},
      ],
    };
    final f = File('${tmp.path}/v1.json');
    await f.writeAsString(jsonEncode(v1));

    final summary = await service.importFrom(f.path);
    expect(summary.version, 1);
    expect(summary.habits, 1);

    final habit = await db.select(db.habits).getSingle();
    expect(habit.name, '读书');
    expect(habit.iconCode, 0x1F525); // v1 缺 iconCode → 默认火焰
    expect(habit.updatedAt, 1700000000000);
    final checkIn = await db.select(db.checkIns).getSingle();
    expect(checkIn.id, isNotEmpty); // v1 无 id → 自动生成
  });

  test('非备份文件 / 错误 app 标签 / 更高版本被拒绝', () async {
    final bad1 = File('${tmp.path}/bad1.json');
    await bad1.writeAsString('not json');
    expect(() => service.inspect(bad1.path), throwsFormatException);

    final bad2 = File('${tmp.path}/bad2.json');
    await bad2.writeAsString(jsonEncode({'app': '别的App', 'habits': []}));
    expect(() => service.inspect(bad2.path), throwsFormatException);

    final bad3 = File('${tmp.path}/bad3.json');
    await bad3
        .writeAsString(jsonEncode({'app': '水獭管家', 'version': 99}));
    expect(() => service.inspect(bad3.path), throwsFormatException);
  });

  test('导入覆盖旧数据而非叠加', () async {
    await insertHabit('old', '旧习惯');
    final backup = {
      'app': '水獭管家',
      'version': 2,
      'exportedAt': '2026-11-05T11:00:00',
      'settings': {'nickname': '小水獭'},
      'habits': [
        {
          'id': 'new',
          'name': '新习惯',
          'iconCode': 0x1F4DA,
          'colorHex': 0xFF0EA5E9,
          'type': 'check',
          'frequency': 'daily',
          'weeklyTarget': 7,
          'weekdaysMask': 127,
          'sortOrder': 0,
          'createdAt': 1700000000000,
          'updatedAt': 1700000000000,
        }
      ],
      'checkIns': [],
      'milestones': [],
      'expenses': [],
    };
    final f = File('${tmp.path}/v2.json');
    await f.writeAsString(jsonEncode(backup));

    final summary = await service.importFrom(f.path);
    expect(summary.nickname, '小水獭');
    final habits = await db.select(db.habits).get();
    expect(habits, hasLength(1)); // 旧习惯被覆盖
    expect(habits.single.name, '新习惯');
  });
}
