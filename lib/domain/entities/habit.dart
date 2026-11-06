import '../../core/utils/date_utils.dart';

enum HabitType {
  check('打勾'),
  count('计数'),
  duration('时长');

  const HabitType(this.label);
  final String label;

  static HabitType fromDb(String v) =>
      HabitType.values.firstWhere((e) => e.name == v, orElse: () => HabitType.check);
}

enum HabitFrequency {
  daily('每天'),
  weekly('每周N次'),
  days('指定星期');

  const HabitFrequency(this.label);
  final String label;

  static HabitFrequency fromDb(String v) =>
      HabitFrequency.values.firstWhere((e) => e.name == v, orElse: () => HabitFrequency.daily);
}

class HabitModel {
  const HabitModel({
    required this.id,
    required this.name,
    required this.iconCode,
    required this.colorHex,
    required this.type,
    this.targetValue,
    this.unit,
    required this.frequency,
    this.weeklyTarget = 7,
    this.weekdaysMask = 127,
    this.reminderTime,
    this.sortOrder = 0,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int iconCode;
  final int colorHex;
  final HabitType type;
  final double? targetValue;
  final String? unit;
  final HabitFrequency frequency;
  final int weeklyTarget;
  final int weekdaysMask; // bit0 = 周一
  final String? reminderTime; // HH:mm
  final int sortOrder;
  final int? archivedAt;
  final int createdAt;
  final int updatedAt;

  bool get isArchived => archivedAt != null;

  /// 指定星期模式下，该星期几是否需要打卡
  bool isScheduledOn(DateTime day) {
    switch (frequency) {
      case HabitFrequency.daily:
      case HabitFrequency.weekly:
        return true;
      case HabitFrequency.days:
        return (weekdaysMask >> (day.weekday - 1)) & 1 == 1;
    }
  }

  List<int> get activeWeekdays => [
        for (var i = 0; i < 7; i++)
          if ((weekdaysMask >> i) & 1 == 1) i + 1,
      ];

  String get frequencyLabel {
    switch (frequency) {
      case HabitFrequency.daily:
        return '每天';
      case HabitFrequency.weekly:
        return '每周 $weeklyTarget 次';
      case HabitFrequency.days:
        final names = activeWeekdays.map((w) => Dates.weekdayNames[w - 1]).join(' ');
        return '周 $names';
    }
  }

  String get goalLabel {
    switch (type) {
      case HabitType.check:
        return '完成即可';
      case HabitType.count:
      case HabitType.duration:
        final t = targetValue ?? 0;
        final tStr = t == t.roundToDouble() ? t.toInt().toString() : t.toString();
        return '目标 $tStr${unit ?? ''}';
    }
  }

  HabitModel copyWith({
    String? name,
    int? iconCode,
    int? colorHex,
    HabitType? type,
    double? targetValue,
    String? unit,
    HabitFrequency? frequency,
    int? weeklyTarget,
    int? weekdaysMask,
    String? reminderTime,
    int? sortOrder,
    int? archivedAt,
    int? updatedAt,
    bool clearTarget = false,
    bool clearReminder = false,
  }) {
    return HabitModel(
      id: id,
      name: name ?? this.name,
      iconCode: iconCode ?? this.iconCode,
      colorHex: colorHex ?? this.colorHex,
      type: type ?? this.type,
      targetValue: clearTarget ? null : (targetValue ?? this.targetValue),
      unit: clearTarget ? null : (unit ?? this.unit),
      frequency: frequency ?? this.frequency,
      weeklyTarget: weeklyTarget ?? this.weeklyTarget,
      weekdaysMask: weekdaysMask ?? this.weekdaysMask,
      reminderTime: clearReminder ? null : (reminderTime ?? this.reminderTime),
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CheckInModel {
  const CheckInModel({
    required this.id,
    required this.habitId,
    required this.localDate,
    required this.doneAt,
    this.value,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String habitId;
  final String localDate;
  final int doneAt;
  final double? value;
  final String? note;
  final int? deletedAt;

  DateTime get date => Dates.parse(localDate);
  DateTime get doneDateTime => DateTime.fromMillisecondsSinceEpoch(doneAt);

  bool get isDeleted => deletedAt != null;
}

/// 单个习惯在某个时间窗口内的聚合统计
class HabitStats {
  const HabitStats({
    required this.habit,
    required this.totalCheckIns,
    required this.currentStreak,
    required this.longestStreak,
    required this.scheduledDays,
    required this.completionRate,
  });

  final HabitModel habit;
  final int totalCheckIns;
  final int currentStreak;
  final int longestStreak;
  final int scheduledDays;
  final double completionRate;

  int get completionPercent => (completionRate * 100).round();
}
