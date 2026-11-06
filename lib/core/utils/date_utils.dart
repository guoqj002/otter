import 'package:flutter/material.dart';

/// 全局日期工具：所有「哪一天」的判断必须走这里，保证时区一致
class Dates {
  Dates._();

  static const List<String> weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parse(String s) {
    final parts = s.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  static String todayStr([DateTime? now]) => fmt(now ?? DateTime.now());

  /// 周一为一周起点（ISO-8601），与 weekdaysMask 的 bit0=周一 对齐
  static DateTime weekStart(DateTime d) {
    final x = dateOnly(d);
    return x.subtract(Duration(days: x.weekday - 1));
  }

  static int daysBetween(DateTime a, DateTime b) =>
      dateOnly(b).difference(dateOnly(a)).inDays;

  static String monthLabel(DateTime d) => '${d.year}年${d.month}月';

  static String friendlyDate(DateTime d, {DateTime? now}) {
    final n = dateOnly(now ?? DateTime.now());
    final t = dateOnly(d);
    final diff = n.difference(t).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff == 2) return '前天';
    return '${t.month}月${t.day}日 周${weekdayNames[t.weekday - 1]}';
  }

  static String timeOfDayLabel(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? parseTimeOfDay(String? s) {
    if (s == null || s.isEmpty) return null;
    final p = s.split(':');
    if (p.length != 2) return null;
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }
}
