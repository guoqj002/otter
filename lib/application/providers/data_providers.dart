import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../../model/db/app_database.dart';
import '../../model/repositories/habit_repository.dart';
import '../../application/services/backup_service.dart';
import '../../domain/entities/habit.dart';

/// 单例数据库（App 生命周期内只开一次）
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 数据导入导出服务
final backupServiceProvider =
    Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider)));

final repoProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(ref.watch(databaseProvider));
});

/// 当前「今天」的 key，跨天时由 root 主动刷新，驱动所有依赖它的 UI
final todayProvider = StateProvider<String>((ref) => Dates.todayStr());

/// 首页习惯列表（活跃）
final habitsProvider = StreamProvider<List<HabitModel>>((ref) {
  return ref.watch(repoProvider).watchActive();
});

/// 今日打卡映射 habitId -> CheckInModel
final todayCheckInsProvider = FutureProvider<Map<String, CheckInModel>>((ref) {
  ref.watch(todayProvider); // 跨天刷新
  return ref.watch(repoProvider).todayMap();
});

/// 全部打卡日期集合（habitId -> `Set<localDate>`），用于 streak / 热力图
final dateSetsProvider = FutureProvider<Map<String, Set<String>>>((ref) {
  ref.watch(todayProvider);
  return ref.watch(repoProvider).dateSets();
});

/// 单个习惯的历史记录
final habitHistoryProvider = FutureProvider.family<List<CheckInModel>, String>((ref, habitId) {
  ref.watch(todayProvider);
  return ref.watch(repoProvider).history(habitId);
});

/// 单个习惯实体
final habitByIdProvider = FutureProvider.family<HabitModel?, String>((ref, id) {
  return ref.watch(repoProvider).habitDao.getById(id);
});

/// 全量统计快照（本月窗口）
final statsProvider = FutureProvider<List<HabitStats>>((ref) {
  ref.watch(todayProvider);
  ref.watch(habitsProvider);
  return ref.watch(repoProvider).statsSnapshot();
});

/// 近 N 天每日打卡总数（统计页柱状图）
final dailyTotalsProvider = FutureProvider.family<Map<String, int>, int>((ref, days) {
  ref.watch(todayProvider);
  final now = DateTime.now();
  return ref
      .watch(repoProvider)
      .dailyTotals(now.subtract(Duration(days: days - 1)), now);
});

/// 单习惯本月统计（完成率等）
final habitMonthStatsProvider = FutureProvider.family<HabitStats?, String>((ref, habitId) async {
  ref.watch(todayProvider);
  final repo = ref.watch(repoProvider);
  final habit = await repo.habitDao.getById(habitId);
  if (habit == null) return null;
  return repo.statsOf(habit);
});

/// 活跃习惯计数
final habitCountProvider = FutureProvider<int>((ref) async {
  ref.watch(habitsProvider);
  return (await ref.watch(repoProvider).activeHabits()).length;
});
