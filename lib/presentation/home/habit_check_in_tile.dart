import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/habit.dart';
import '../widgets/common.dart';
import '../widgets/habit_icon_art.dart';

Color habitColor(HabitModel habit) => Color(habit.colorHex);

/// 首页打卡卡片：一键打卡、撤销、进详情
class HabitCheckInTile extends StatefulWidget {
  const HabitCheckInTile({
    super.key,
    required this.habit,
    required this.checkIn,
    required this.streak,
    required this.onTap,
    required this.onOpenDetail,
    this.onUndo,
    this.highlight = false,
  });

  final HabitModel habit;
  final CheckInModel? checkIn;
  final int streak;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;
  final VoidCallback? onUndo;
  final bool highlight;

  @override
  State<HabitCheckInTile> createState() => _HabitCheckInTileState();
}

class _HabitCheckInTileState extends State<HabitCheckInTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    lowerBound: 0.94,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void didUpdateWidget(covariant HabitCheckInTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checkIn == null && widget.checkIn != null) {
      _scale.reverse().then((_) => _scale.forward());
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final color = habitColor(habit);
    final done = widget.checkIn != null;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScaleTransition(
      scale: _scale,
      child: Material(
        color: done
            ? color.withValues(alpha: isDark ? 0.13 : 0.07)
            : (isDark ? const Color(0xFF1F2937) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          onLongPress: widget.onOpenDetail,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.highlight && !done
                    ? color.withValues(alpha: 0.55)
                    : (isDark ? const Color(0xFF374151) : const Color(0xFFE7E5E4)),
                width: widget.highlight && !done ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: done ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: HabitIconArtImage(code: habit.iconCode, size: 38),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              habit.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: done ? scheme.onSurface.withValues(alpha: 0.7) : scheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StreakBadge(
                            streak: widget.streak,
                            unit: habit.frequency == HabitFrequency.weekly ? '周' : '天',
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        done
                            ? '已完成 · ${_valueLabel(habit, widget.checkIn?.value)}'
                            : '${habit.goalLabel} · ${habit.frequencyLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: done ? AppColors.success : scheme.onSurfaceVariant,
                          fontWeight: done ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (done)
                  IconButton(
                    tooltip: '撤销打卡',
                    onPressed: widget.onUndo,
                    icon: Icon(Icons.check_circle_rounded, color: color, size: 28),
                  )
                else
                  Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withValues(alpha: 0.45), width: 2),
                    ),
                    child: Icon(Icons.add_rounded, size: 20, color: color),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _valueLabel(HabitModel habit, double? v) {
    switch (habit.type) {
      case HabitType.check:
        return Dates.friendlyDate(DateTime.now());
      case HabitType.count:
      case HabitType.duration:
        final value = v ?? habit.targetValue ?? 0;
        final s = value == value.roundToDouble() ? value.toInt().toString() : value.toString();
        return '$s${habit.unit ?? ''}';
    }
  }
}
