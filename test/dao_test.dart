
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitstreak/model/db/app_database.dart';
import 'package:fitstreak/model/dao/habit_dao.dart';

/// 数据层集成测试：用内存 SQLite 验证唯一约束与聚合 SQL
void main() {
  late AppDatabase db;
  late CheckInDao checkInDao;
  late HabitDao habitDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    checkInDao = CheckInDao(db);
    habitDao = HabitDao(db);
  });

  tearDown(() async => db.close());

  Future<void> seedHabit(String id) async {
    await db.into(db.habits).insert(
          HabitsCompanion.insert(
            id: id,
            name: '俯卧撑 $id',
            iconCode: 0xe4f5,
            colorHex: 0xFF22C55E,
            type: 'count',
            frequency: 'daily',
            createdAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
            updatedAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
          ),
        );
  }

  group('唯一约束', () {
    test('同习惯同一天重复打卡只会有一条记录', () async {
      await seedHabit('h1');
      await checkInDao.upsertCheckIn(
        id: 'c1',
        habitId: 'h1',
        localDate: '2026-10-22',
        doneAt: 1000,
        value: 30,
      );
      // 第二次（不同 id）走 onConflict 更新
      await checkInDao.upsertCheckIn(
        id: 'c2',
        habitId: 'h1',
        localDate: '2026-10-22',
        doneAt: 2000,
        value: 45,
      );

      final rows = await db.select(db.checkIns).get();
      expect(rows.length, 1, reason: '唯一约束必须阻止重复行');
      expect(rows.first.value, 45, reason: '应更新为最新值');
      expect(rows.first.doneAt, 2000);
    });

    test('不同习惯同一天互不影响', () async {
      await seedHabit('h1');
      await seedHabit('h2');
      await checkInDao.upsertCheckIn(
          id: 'c1', habitId: 'h1', localDate: '2026-10-22', doneAt: 1000);
      await checkInDao.upsertCheckIn(
          id: 'c2', habitId: 'h2', localDate: '2026-10-22', doneAt: 1000);
      expect((await db.select(db.checkIns).get()).length, 2);
    });
  });

  group('软删除', () {
    test('撤销后不再计入查询', () async {
      await seedHabit('h1');
      await checkInDao.upsertCheckIn(
          id: 'c1', habitId: 'h1', localDate: '2026-10-22', doneAt: 1000);
      await checkInDao.softDelete('h1', '2026-10-22');

      expect(await checkInDao.totalCount(), 0);
      expect((await checkInDao.loadDateSets())['h1'], isNull);
    });

    test('撤销后可重新打卡（唯一约束不冲突）', () async {
      await seedHabit('h1');
      await checkInDao.upsertCheckIn(
          id: 'c1', habitId: 'h1', localDate: '2026-10-22', doneAt: 1000);
      await checkInDao.softDelete('h1', '2026-10-22');
      await checkInDao.upsertCheckIn(
          id: 'c3', habitId: 'h1', localDate: '2026-10-22', doneAt: 3000);

      final rows = await db.select(db.checkIns).get();
      expect(rows.length, 1);
      expect(rows.first.deletedAt, isNull, reason: '重新打卡应清除墓碑');
    });
  });

  group('聚合 SQL', () {
    setUp(() async {
      await seedHabit('h1');
      await seedHabit('h2');
      for (var i = 0; i < 5; i++) {
        final day = '2026-10-${(20 + i).toString().padLeft(2, '0')}';
        await checkInDao.upsertCheckIn(
            id: 'a$i', habitId: 'h1', localDate: day, doneAt: i);
      }
      await checkInDao.upsertCheckIn(
          id: 'b1', habitId: 'h2', localDate: '2026-10-22', doneAt: 0);
      // 窗口外的记录
      await checkInDao.upsertCheckIn(
          id: 'b2', habitId: 'h1', localDate: '2026-09-01', doneAt: 0);
    });

    test('countByHabit 只统计窗口内', () async {
      final m = await checkInDao.countByHabit('2026-10-01', '2026-10-31');
      expect(m['h1'], 5);
      expect(m['h2'], 1);
    });

    test('dailyTotals 按日聚合', () async {
      final m = await checkInDao.dailyTotals('2026-10-01', '2026-10-31');
      expect(m['2026-10-22'], 2, reason: '10-22 两个习惯都打了');
      expect(m.length, 5);
    });

    test('allTotals 含全部历史', () async {
      final m = await checkInDao.allTotals();
      expect(m['h1'], 6);
    });
  });

  group('级联删除', () {
    test('删除习惯时打卡记录一并删除', () async {
      await seedHabit('h1');
      await checkInDao.upsertCheckIn(
          id: 'c1', habitId: 'h1', localDate: '2026-10-22', doneAt: 1000);
      await habitDao.deletePermanently('h1');
      expect((await db.select(db.checkIns).get()).isEmpty, true,
          reason: 'foreign_keys=ON 应触发级联');
    });
  });
}
