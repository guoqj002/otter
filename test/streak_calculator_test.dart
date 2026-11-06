import 'package:flutter_test/flutter_test.dart';

import 'package:fitstreak/application/services/streak_calculator.dart';
import 'package:fitstreak/core/utils/date_utils.dart';
import 'package:fitstreak/domain/entities/habit.dart';

HabitModel mkHabitModel({
  HabitFrequency frequency = HabitFrequency.daily,
  int weeklyTarget = 3,
  int weekdaysMask = 127,
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime(2026, 1, 1);
  return HabitModel(
    id: 'h1',
    name: '俯卧撑',
    iconCode: 0xe3f2,
    colorHex: 0xFF22C55E,
    type: HabitType.check,
    frequency: frequency,
    weeklyTarget: weeklyTarget,
    weekdaysMask: weekdaysMask,
    createdAt: created.millisecondsSinceEpoch,
    updatedAt: created.millisecondsSinceEpoch,
  );
}

Set<String> dates(List<DateTime> ds) => ds.map(Dates.fmt).toSet();

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  group('daily streak', () {
    test('连续 3 天，今天已打卡 → 3', () {
      final now = d(2026, 10, 22);
      final done = dates([d(2026, 10, 20), d(2026, 10, 21), d(2026, 10, 22)]);
      expect(StreakCalculator.current(mkHabitModel(), done, now: now), 3);
    });

    test('今天未打卡不归零，沿用昨天 → 2', () {
      final now = d(2026, 10, 22);
      final done = dates([d(2026, 10, 20), d(2026, 10, 21)]);
      expect(StreakCalculator.current(mkHabitModel(), done, now: now), 2);
    });

    test('昨天未打卡 → 归零', () {
      final now = d(2026, 10, 22);
      final done = dates([d(2026, 10, 18), d(2026, 10, 19)]);
      expect(StreakCalculator.current(mkHabitModel(), done, now: now), 0);
    });

    test('跨月边界 10-31 → 11-01 连续', () {
      final now = d(2026, 11, 1);
      final done = dates([d(2026, 10, 30), d(2026, 10, 31), d(2026, 11, 1)]);
      expect(StreakCalculator.current(mkHabitModel(), done, now: now), 3);
    });

    test('最长连续取历史峰值', () {
      final now = d(2026, 10, 22);
      final done = dates([
        d(2026, 10, 1), d(2026, 10, 2), d(2026, 10, 3), d(2026, 10, 4),
        d(2026, 10, 20), d(2026, 10, 21), d(2026, 10, 22),
      ]);
      expect(StreakCalculator.longest(mkHabitModel(), done, now: now), 4);
      expect(StreakCalculator.current(mkHabitModel(), done, now: now), 3);
    });
  });

  group('days frequency (周一/三/五)', () {
    // 2026-10-19 是周一
    final mwf = 0x15; // bit0 周一 | bit2 周三 | bit4 周五

    test('非应打卡日不中断 streak', () {
      final now = d(2026, 10, 21); // 周三
      final done = dates([d(2026, 10, 19), d(2026, 10, 21)]);
      expect(
        StreakCalculator.current(mkHabitModel(frequency: HabitFrequency.days, weekdaysMask: mwf), done, now: now),
        2,
      );
    });

    test('今天应打卡但未打，只跳过今天，不误判为断 → 1', () {
      final now = d(2026, 10, 21); // 周三，应打卡且未打
      final done = dates([d(2026, 10, 19)]);
      expect(
        StreakCalculator.current(mkHabitModel(frequency: HabitFrequency.days, weekdaysMask: mwf), done, now: now),
        1,
      );
    });

    test('跨过断点后不能继续向前累计 → 归零', () {
      // 今天是周二（非应打卡日），上周五打了，但本周一（10-19）漏打
      final now = d(2026, 10, 20); // 周二
      final done = dates([d(2026, 10, 16)]); // 上周五
      expect(
        StreakCalculator.current(mkHabitModel(frequency: HabitFrequency.days, weekdaysMask: mwf), done, now: now),
        0,
      );
    });

    test('非应打卡日 today 打开 App 不误判', () {
      final now = d(2026, 10, 20); // 周二，非应打卡日
      final done = dates([d(2026, 10, 19)]);
      expect(
        StreakCalculator.current(mkHabitModel(frequency: HabitFrequency.days, weekdaysMask: mwf), done, now: now),
        1,
      );
    });
  });

  group('weekly frequency (每周 3 次)', () {
    test('本周达标 + 上周达标 → 2 周', () {
      final now = d(2026, 10, 22); // 周四，本周起始 10-19
      final done = dates([
        d(2026, 10, 12), d(2026, 10, 14), d(2026, 10, 16),
        d(2026, 10, 19), d(2026, 10, 20), d(2026, 10, 21),
      ]);
      expect(
        StreakCalculator.current(mkHabitModel(frequency: HabitFrequency.weekly), done, now: now),
        2,
      );
    });

    test('本周未达标不算断，取上周连续', () {
      final now = d(2026, 10, 22);
      final done = dates([
        d(2026, 10, 5), d(2026, 10, 7), d(2026, 10, 9),
        d(2026, 10, 12), d(2026, 10, 14), d(2026, 10, 16),
        d(2026, 10, 19), // 本周仅 1 次
      ]);
      expect(
        StreakCalculator.current(mkHabitModel(frequency: HabitFrequency.weekly), done, now: now),
        2,
      );
    });

    test('断一周后连续中断', () {
      final now = d(2026, 10, 22);
      final done = dates([
        d(2026, 9, 28), d(2026, 9, 30), d(2026, 10, 2),
        // 10-05 那周空
        d(2026, 10, 12), d(2026, 10, 14), d(2026, 10, 16),
        d(2026, 10, 19), d(2026, 10, 20), d(2026, 10, 21),
      ]);
      expect(
        StreakCalculator.current(mkHabitModel(frequency: HabitFrequency.weekly), done, now: now),
        2,
      );
    });
  });

  group('completion rate', () {
    test('daily：14 天窗口完成 7 天 → 50%', () {
      var done = <String>{};
      for (var i = 0; i < 7; i++) {
        done.add(Dates.fmt(d(2026, 10, 16).add(Duration(days: i))));
      }
      final rate = StreakCalculator.completionRate(
        mkHabitModel(),
        done,
        d(2026, 10, 16),
        d(2026, 10, 29),
      );
      expect(rate, closeTo(0.5, 0.001));
    });

    test('days：仅周一三五，两周应打卡 6 天', () {
      final habit = mkHabitModel(frequency: HabitFrequency.days, weekdaysMask: 0x15);
      final n = StreakCalculator.scheduledDays(habit, d(2026, 10, 19), d(2026, 11, 1));
      expect(n, 6);
    });

    test('weekly：两周目标 3 次/周 → 6', () {
      final habit = mkHabitModel(frequency: HabitFrequency.weekly, weeklyTarget: 3);
      final n = StreakCalculator.scheduledDays(habit, d(2026, 10, 19), d(2026, 11, 1));
      expect(n, 6);
    });
  });

  group('weekStart', () {
    test('周四的周起点是本周一', () {
      expect(Dates.weekStart(d(2026, 10, 22)), d(2026, 10, 19));
    });

    test('周日的周起点仍是本周一', () {
      expect(Dates.weekStart(d(2026, 10, 25)), d(2026, 10, 19));
    });
  });
}
