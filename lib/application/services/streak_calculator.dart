import '../../core/utils/date_utils.dart';
import '../../domain/entities/habit.dart';

/// 连续打卡计算器 —— 纯函数、无 Flutter 依赖，规则见设计方案 2.3
///
/// 规则：
/// 1. 以 localDate（YYYY-MM-DD）集合为准，时区在记录落库时已确定。
/// 2. daily 频率：从今天（今天未打卡则从昨天）向前连续的天数。
/// 3. days 频率：只在「应打卡日」推进，非应打卡日不中断也不计数。
/// 4. weekly 频率：按周聚合，连续 N 周达标 → streak = N 周。
class StreakCalculator {
  const StreakCalculator._();

  /// 当前连续（单位：天 / 周）
  static int current(HabitModel habit, Set<String> doneDates, {DateTime? now}) {
    final today = Dates.dateOnly(now ?? DateTime.now());
    if (habit.frequency == HabitFrequency.weekly) {
      return _weeklyStreak(habit, doneDates, today, includeCurrent: true);
    }
    return _dailyStreak(habit, doneDates, today);
  }

  /// 历史最长连续（单位：天 / 周）
  static int longest(HabitModel habit, Set<String> doneDates, {DateTime? now}) {
    if (doneDates.isEmpty) return 0;
    final today = Dates.dateOnly(now ?? DateTime.now());
    final start = habit.createdAt > 0
        ? Dates.dateOnly(DateTime.fromMillisecondsSinceEpoch(habit.createdAt))
        : doneDates.map(Dates.parse).reduce((a, b) => a.isBefore(b) ? a : b);

    if (habit.frequency == HabitFrequency.weekly) {
      return _longestWeekly(habit, doneDates, start, today);
    }

    var best = 0;
    var run = 0;
    var cursor = DateOnly(start);
    final end = DateOnly(today);
    while (cursor.value.isBefore(end.value) || cursor.value == end.value) {
      final day = cursor.value;
      final done = doneDates.contains(Dates.fmt(day));
      final scheduled = habit.isScheduledOn(day);

      if (done) {
        run++;
        if (run > best) best = run;
      } else if (scheduled) {
        run = 0;
      }
      // 非应打卡日：既不累加也不清零
      cursor = DateOnly(day.add(const Duration(days: 1)));
    }
    return best;
  }

  // ---------------------------------------------------------------- daily

  static int _dailyStreak(HabitModel habit, Set<String> doneDates, DateTime today) {
    var streak = 0;

    for (var i = 0; i < 4000; i++) {
      final day = today.subtract(Duration(days: i));
      final done = doneDates.contains(Dates.fmt(day));
      final scheduled =
          habit.frequency != HabitFrequency.days || habit.isScheduledOn(day);

      if (done) {
        streak++;
      } else if (scheduled) {
        // 只有「今天」这一个是尚未完成的应打卡日，允许跳过；
        // 更早的应打卡日未打卡 = 真实断点，立即结束，不再向前累计
        if (i == 0) continue;
        break;
      }
    }
    return streak;
  }

  // --------------------------------------------------------------- weekly

  /// 周达标：该周打卡数 >= weeklyTarget
  static bool _weekHit(HabitModel habit, Set<String> doneDates, DateTime weekStart) {
    var c = 0;
    for (var i = 0; i < 7; i++) {
      if (doneDates.contains(Dates.fmt(weekStart.add(Duration(days: i))))) c++;
    }
    return c >= habit.weeklyTarget;
  }

  static int _weeklyStreak(
    HabitModel habit,
    Set<String> doneDates,
    DateTime today, {
    bool includeCurrent = true,
  }) {
    var week = Dates.weekStart(today);
    var streak = 0;

    // 本周尚未达标不算断：先在达标时计入，不达标则从上周起算
    if (includeCurrent && _weekHit(habit, doneDates, week)) {
      streak++;
    }
    week = week.subtract(const Duration(days: 7));

    var guard = 0;
    while (guard++ < 600) {
      if (_weekHit(habit, doneDates, week)) {
        streak++;
        week = week.subtract(const Duration(days: 7));
      } else {
        break;
      }
    }
    return streak;
  }

  static int _longestWeekly(
    HabitModel habit,
    Set<String> doneDates,
    DateTime start,
    DateTime today,
  ) {
    var week = Dates.weekStart(start);
    final lastWeek = Dates.weekStart(today);
    var best = 0;
    var run = 0;
    while (!week.isAfter(lastWeek)) {
      if (_weekHit(habit, doneDates, week)) {
        run++;
        if (run > best) best = run;
      } else {
        // 本周尚未结束不打断历史记录
        if (!week.isAtSameMomentAs(lastWeek)) run = 0;
      }
      week = week.add(const Duration(days: 7));
    }
    return best;
  }

  /// 时间窗口内应打卡天数，用于完成率
  static int scheduledDays(HabitModel habit, DateTime from, DateTime to) {
    final start = Dates.dateOnly(from);
    final end = Dates.dateOnly(to);
    if (end.isBefore(start)) return 0;
    final totalDays = end.difference(start).inDays + 1;

    switch (habit.frequency) {
      case HabitFrequency.daily:
        return totalDays;
      case HabitFrequency.weekly:
        final weeks = totalDays / 7.0;
        return (weeks * habit.weeklyTarget).round().clamp(0, totalDays);
      case HabitFrequency.days:
        var c = 0;
        for (var i = 0; i < totalDays; i++) {
          if (habit.isScheduledOn(start.add(Duration(days: i)))) c++;
        }
        return c;
    }
  }

  /// 窗口内完成率（0.0 - 1.0）
  static double completionRate(
    HabitModel habit,
    Set<String> doneDates,
    DateTime from,
    DateTime to,
  ) {
    final scheduled = scheduledDays(habit, from, to);
    if (scheduled == 0) return 0;
    final start = Dates.dateOnly(from);
    final totalDays = Dates.dateOnly(to).difference(start).inDays + 1;
    var done = 0;
    for (var i = 0; i < totalDays; i++) {
      if (doneDates.contains(Dates.fmt(start.add(Duration(days: i))))) done++;
    }
    return (done / scheduled).clamp(0.0, 1.0);
  }
}

/// 轻量日期包装，避免反复构造 DateTime 时带入时间分量
class DateOnly {
  DateOnly(DateTime d) : value = Dates.dateOnly(d);
  final DateTime value;
}
