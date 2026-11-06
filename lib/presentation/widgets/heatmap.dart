import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';

/// GitHub 风格年度热力图（自绘，性能更好）
class Heatmap extends StatelessWidget {
  const Heatmap({
    super.key,
    required this.doneDates,
    required this.color,
    this.weeks = 26,
    this.end,
    this.cell = 12,
    this.gap = 3,
  });

  final Set<String> doneDates;
  final Color color;
  final int weeks;
  final DateTime? end;
  final double cell;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final today = Dates.dateOnly(end ?? DateTime.now());
    final lastWeekStart = Dates.weekStart(today);
    final firstWeekStart =
        lastWeekStart.subtract(Duration(days: (weeks - 1) * 7));

    final totalDays = Dates.daysBetween(firstWeekStart, today) + 1;
    final rows = 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final computedCell =
            ((available - (weeks - 1) * gap) / weeks).clamp(6.0, cell);
        final width = weeks * computedCell + (weeks - 1) * gap;
        final height = rows * computedCell + (rows - 1) * gap;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: height,
              child: CustomPaint(
                painter: _HeatPainter(
                  doneDates: doneDates,
                  firstDay: firstWeekStart,
                  weeks: weeks,
                  totalDays: totalDays,
                  cell: computedCell,
                  gap: gap,
                  base: color,
                  empty: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF374151)
                      : AppColors.heatScale[0],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('少',
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                for (var i = 0; i < 5; i++)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? (Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF374151)
                              : AppColors.heatScale[0])
                          : color.withValues(alpha: 0.25 + i * 0.1875),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                const SizedBox(width: 4),
                Text('多',
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter({
    required this.doneDates,
    required this.firstDay,
    required this.weeks,
    required this.totalDays,
    required this.cell,
    required this.gap,
    required this.base,
    required this.empty,
  });

  final Set<String> doneDates;
  final DateTime firstDay;
  final int weeks;
  final int totalDays;
  final double cell;
  final double gap;
  final Color base;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < totalDays; i++) {
      final day = firstDay.add(Duration(days: i));
      final week = i ~/ 7;
      final row = i % 7;
      final x = week * (cell + gap);
      final y = row * (cell + gap);
      final key = Dates.fmt(day);
      final done = doneDates.contains(key);

      paint.color = done ? base.withValues(alpha: 0.85) : empty;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cell, cell),
          Radius.circular(cell * 0.22),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) =>
      old.doneDates.length != doneDates.length ||
      old.firstDay != firstDay ||
      old.cell != cell ||
      old.base != base;
}

/// 月历视图：显示某月每天是否打卡
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.doneDates,
    required this.color,
    this.scheduledCheck,
    this.onTapDay,
  });

  final DateTime month;
  final Set<String> doneDates;
  final Color color;

  /// 判断某天是否「应打卡」（用于标记灰色未完成）
  final bool Function(DateTime day)? scheduledCheck;
  final void Function(DateTime day)? onTapDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1; // 周一为起点
    final today = Dates.dateOnly(DateTime.now());

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final key = Dates.fmt(date);
      final done = doneDates.contains(key);
      final isToday = date.isAtSameMomentAs(today);
      final isFuture = date.isAfter(today);
      final scheduled = scheduledCheck?.call(date) ?? true;

      cells.add(
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTapDay == null || isFuture ? null : () => onTapDay!(date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: done
                  ? color.withValues(alpha: 0.9)
                  : (scheduled && !isFuture
                      ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: isToday ? Border.all(color: color, width: 1.6) : null,
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text(
                    '$d',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                      color: isFuture
                          ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            for (final w in Dates.weekdayNames)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1,
          children: cells,
        ),
      ],
    );
  }
}
