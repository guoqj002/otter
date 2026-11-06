import '../../application/services/streak_calculator.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/habit.dart';
import '../dao/habit_dao.dart';
import '../db/app_database.dart';

class HabitRepository {
  HabitRepository(AppDatabase db)
      : habitDao = HabitDao(db),
        checkInDao = CheckInDao(db),
        milestoneDao = MilestoneDao(db);

  factory HabitRepository.forTest(AppDatabase db) => HabitRepository(db);
  final HabitDao habitDao;
  final CheckInDao checkInDao;
  final MilestoneDao milestoneDao;

  // ------------------------------------------------------------- queries

  Stream<List<HabitModel>> watchActive() => habitDao.watchActive();

  Future<List<HabitModel>> activeHabits() => habitDao.getActive();

  Future<List<HabitModel>> archivedHabits() => habitDao.getArchived();

  Future<Map<String, Set<String>>> dateSets() => checkInDao.loadDateSets();

  Future<String?> habitIdAt(String habitId, DateTime day) async {
    final r = await checkInDao.findByDate(habitId, Dates.fmt(day));
    return r?.id;
  }

  Future<Map<String, CheckInModel>> todayMap([DateTime? now]) =>
      checkInDao.byDate(Dates.todayStr(now));

  Future<List<CheckInModel>> history(String habitId) => checkInDao.getByHabit(habitId);

  Future<int> totalCheckIns() => checkInDao.totalCount();

  Future<Map<String, int>> dailyTotals(DateTime from, DateTime to) =>
      checkInDao.dailyTotals(Dates.fmt(from), Dates.fmt(to));

  // ------------------------------------------------------------ commands

  Future<void> saveHabit(HabitModel habit) => habitDao.upsert(habit);

  Future<void> archiveHabit(String id) => habitDao.archive(id);

  Future<void> restoreHabit(String id) => habitDao.restore(id);

  Future<void> deleteHabit(String id) => habitDao.deletePermanently(id);

  Future<void> reorder(List<String> ids) => habitDao.updateSortOrders(ids);

  /// 打卡（幂等）。返回是否触发了「新」打卡
  Future<bool> checkIn(
    HabitModel habit, {
    double? value,
    DateTime? when,
    bool allowBackfill = false,
  }) async {
    final now = when ?? DateTime.now();
    final key = Dates.fmt(now);
    if (!allowBackfill) {
      final today = Dates.dateOnly(DateTime.now());
      final target = Dates.dateOnly(now);
      if (!target.isAtSameMomentAs(today)) {
        throw StateError('只能为今天打卡');
      }
    }

    final existing = await checkInDao.findByDate(habit.id, key);
    if (existing != null) return false;

    await checkInDao.upsertCheckIn(
      id: _newId(),
      habitId: habit.id,
      localDate: key,
      doneAt: now.millisecondsSinceEpoch,
      value: value ?? (habit.type == HabitType.check ? null : habit.targetValue),
    );
    return true;
  }

  Future<void> undoCheckIn(HabitModel habit, DateTime day) =>
      checkInDao.softDelete(habit.id, Dates.fmt(day));

  /// 计算全部习惯的统计快照
  Future<List<HabitStats>> statsSnapshot({
    DateTime? now,
    DateTime? windowFrom,
  }) async {
    final n = now ?? DateTime.now();
    final habits = await habitDao.getActive();
    final sets = await checkInDao.loadDateSets();
    // 累计次数聚合下推到 SQL（GROUP BY habit_id），不在应用层计数
    final totals = await checkInDao.allTotals();
    final from = windowFrom ?? DateTime(n.year, n.month, 1);

    return habits.map((h) {
      final done = sets[h.id] ?? const <String>{};
      return HabitStats(
        habit: h,
        totalCheckIns: totals[h.id] ?? 0,
        currentStreak: StreakCalculator.current(h, done, now: n),
        longestStreak: StreakCalculator.longest(h, done, now: n),
        scheduledDays: StreakCalculator.scheduledDays(h, from, n),
        completionRate: StreakCalculator.completionRate(h, done, from, n),
      );
    }).toList();
  }

  Future<HabitStats> statsOf(HabitModel habit, {DateTime? now, DateTime? windowFrom}) async {
    final n = now ?? DateTime.now();
    final sets = await checkInDao.loadDateSets(habitId: habit.id);
    final done = sets[habit.id] ?? const <String>{};
    final from = windowFrom ?? DateTime(n.year, n.month, 1);
    return HabitStats(
      habit: habit,
      totalCheckIns: done.length,
      currentStreak: StreakCalculator.current(habit, done, now: n),
      longestStreak: StreakCalculator.longest(habit, done, now: n),
      scheduledDays: StreakCalculator.scheduledDays(habit, from, n),
      completionRate: StreakCalculator.completionRate(habit, done, from, n),
    );
  }

  /// 里程碑检测，返回新达成的 kind（用于庆祝动效），不会重复返回
  Future<List<String>> detectMilestones(HabitModel habit, HabitStats stats) async {
    final achieved = await milestoneDao.achievedKinds(habit.id);
    final hits = <String>[];
    void check(String kind, bool cond) {
      if (cond && !achieved.contains(kind)) hits.add(kind);
    }

    check('streak_3', stats.currentStreak >= 3);
    check('streak_7', stats.currentStreak >= 7);
    check('streak_30', stats.currentStreak >= 30);
    check('streak_100', stats.currentStreak >= 100);
    check('total_10', stats.totalCheckIns >= 10);
    check('total_100', stats.totalCheckIns >= 100);

    for (final k in hits) {
      await milestoneDao.mark(habit.id, k);
    }
    return hits;
  }

  int _seq = 0;

  /// 本地唯一 id：时间戳 + 自增序号，避免同一毫秒内碰撞
  String _newId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'c$ts-${_seq++}';
  }

  Future<List<CheckInModel>> exportRows() => checkInDao.allForExport();
}

