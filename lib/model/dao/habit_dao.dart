import 'package:drift/drift.dart';

import '../../domain/entities/habit.dart' as domain;
import '../db/app_database.dart';
import '../row_mappers.dart';

class HabitDao {
  HabitDao(this.db);
  final AppDatabase db;

  Stream<List<domain.HabitModel>> watchActive() {
    final q = db.select(db.habits)
      ..where((t) => t.archivedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.createdAt),
      ]);
    return q.watch().map((rows) => rows.map((e) => e.toEntity()).toList());
  }

  Future<List<domain.HabitModel>> getActive() async {
    final q = db.select(db.habits)
      ..where((t) => t.archivedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]);
    return (await q.get()).map((e) => e.toEntity()).toList();
  }

  Future<domain.HabitModel?> getById(String id) async {
    final row = await (db.select(db.habits)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.toEntity();
  }

  Future<void> upsert(domain.HabitModel habit) async {
    await db.into(db.habits).insertOnConflictUpdate(habit.toCompanion());
  }

  Future<void> archive(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (db.update(db.habits)..where((t) => t.id.equals(id))).write(
      HabitsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
    );
  }

  Future<void> restore(String id) async {
    await (db.update(db.habits)..where((t) => t.id.equals(id))).write(
      HabitsCompanion(
        archivedAt: const Value(null),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> deletePermanently(String id) async {
    await (db.delete(db.habits)..where((t) => t.id.equals(id))).go();
  }

  Future<void> updateSortOrders(List<String> orderedIds) async {
    await db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (db.update(db.habits)..where((t) => t.id.equals(orderedIds[i])))
            .write(HabitsCompanion(sortOrder: Value(i)));
      }
    });
  }

  Future<List<domain.HabitModel>> getArchived() async {
    final q = db.select(db.habits)
      ..where((t) => t.archivedAt.isNotNull())
      ..orderBy([(t) => OrderingTerm(expression: t.archivedAt, mode: OrderingMode.desc)]);
    return (await q.get()).map((e) => e.toEntity()).toList();
  }
}

class CheckInDao {
  CheckInDao(this.db);
  final AppDatabase db;

  /// 所有未删除打卡记录，按习惯分组
  Future<Map<String, Set<String>>> loadDateSets({String? habitId}) async {
    final q = db.select(db.checkIns)..where((t) => t.deletedAt.isNull());
    if (habitId != null) q.where((t) => t.habitId.equals(habitId));
    final rows = await q.get();
    final map = <String, Set<String>>{};
    for (final r in rows) {
      map.putIfAbsent(r.habitId, () => <String>{}).add(r.localDate);
    }
    return map;
  }

  Future<List<domain.CheckInModel>> getByHabit(String habitId, {int limit = 400}) async {
    final q = db.select(db.checkIns)
      ..where((t) => t.habitId.equals(habitId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.localDate, mode: OrderingMode.desc)])
      ..limit(limit);
    return (await q.get()).map((e) => e.toEntity()).toList();
  }

  Future<domain.CheckInModel?> findByDate(String habitId, String localDate) async {
    final q = db.select(db.checkIns)
      ..where((t) =>
          t.habitId.equals(habitId) & t.localDate.equals(localDate) & t.deletedAt.isNull());
    final row = await q.getSingleOrNull();
    return row?.toEntity();
  }

  /// 幂等打卡：同习惯同一天只会有一条有效记录
  Future<void> upsertCheckIn({
    required String id,
    required String habitId,
    required String localDate,
    required int doneAt,
    double? value,
    String? note,
  }) async {
    await db.into(db.checkIns).insert(
          CheckInsCompanion.insert(
            id: id,
            habitId: habitId,
            localDate: localDate,
            doneAt: doneAt,
            value: Value(value),
            note: Value(note),
          ),
          onConflict: DoUpdate(
            (_) => CheckInsCompanion(
              doneAt: Value(doneAt),
              value: Value(value),
              note: Value(note),
              deletedAt: const Value(null),
            ),
            target: [db.checkIns.habitId, db.checkIns.localDate],
          ),
        );
  }

  Future<void> softDelete(String habitId, String localDate) async {
    await (db.update(db.checkIns)
          ..where((t) => t.habitId.equals(habitId) & t.localDate.equals(localDate)))
        .write(CheckInsCompanion(deletedAt: Value(DateTime.now().millisecondsSinceEpoch)));
  }

  /// 窗口内完成数聚合（GROUP BY 下推到 SQL，不捞全表）
  Future<Map<String, int>> countByHabit(String from, String to) async {
    final rows = await db.customSelect(
      '''
      SELECT habit_id AS hid, COUNT(*) AS c
      FROM check_ins
      WHERE deleted_at IS NULL AND local_date BETWEEN ?1 AND ?2
      GROUP BY habit_id
      ''',
      variables: [Variable<String>(from), Variable<String>(to)],
      readsFrom: {db.checkIns},
    ).get();
    return {for (final r in rows) r.read<String>('hid'): r.read<int>('c')};
  }

  /// 某天打卡（首页进度环用）
  Future<Map<String, domain.CheckInModel>> byDate(String localDate) async {
    final q = db.select(db.checkIns)
      ..where((t) => t.localDate.equals(localDate) & t.deletedAt.isNull());
    final rows = await q.get();
    return {for (final r in rows) r.habitId: r.toEntity()};
  }

  /// 近 N 天的总打卡数（统计页柱状图）
  Future<Map<String, int>> dailyTotals(String from, String to) async {
    final rows = await db.customSelect(
      '''
      SELECT local_date AS d, COUNT(*) AS c
      FROM check_ins
      WHERE deleted_at IS NULL AND local_date BETWEEN ?1 AND ?2
      GROUP BY local_date ORDER BY local_date
      ''',
      variables: [Variable<String>(from), Variable<String>(to)],
      readsFrom: {db.checkIns},
    ).get();
    return {for (final r in rows) r.read<String>('d'): r.read<int>('c')};
  }

  Future<Map<String, int>> allTotals() async {
    final rows = await db.customSelect(
      '''
      SELECT habit_id AS hid, COUNT(*) AS c
      FROM check_ins WHERE deleted_at IS NULL GROUP BY habit_id
      ''',
      readsFrom: {db.checkIns},
    ).get();
    return {for (final r in rows) r.read<String>('hid'): r.read<int>('c')};
  }

  Future<int> totalCount() async {
    final rows = await db.customSelect(
      'SELECT COUNT(*) AS c FROM check_ins WHERE deleted_at IS NULL',
      readsFrom: {db.checkIns},
    ).getSingle();
    return rows.read<int>('c');
  }

  /// 全部原始记录（导出用）
  Future<List<domain.CheckInModel>> allForExport() async {
    final q = db.select(db.checkIns)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.localDate)]);
    return (await q.get()).map((e) => e.toEntity()).toList();
  }
}

class MilestoneDao {
  MilestoneDao(this.db);
  final AppDatabase db;

  Future<Set<String>> achievedKinds(String habitId) async {
    final rows =
        await (db.select(db.milestones)..where((t) => t.habitId.equals(habitId))).get();
    return rows.map((e) => e.kind).toSet();
  }

  Future<void> mark(String habitId, String kind) async {
    await db.into(db.milestones).insertOnConflictUpdate(
          MilestonesCompanion.insert(
            habitId: habitId,
            kind: kind,
            achievedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }
}
