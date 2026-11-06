import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/entities/habit.dart';

/// 供其他页面引用
class HabitPreset {
  const HabitPreset({
    required this.name,
    required this.icon,
    required this.color,
    required this.subtitle,
    required this.type,
    this.targetValue,
    this.unit,
  });

  final String name;
  final IconData icon;
  final Color color;
  final String subtitle;
  final HabitType type;
  final double? targetValue;
  final String? unit;

  HabitModel toHabit({required String id, required int sortOrder, required int now}) {
    return HabitModel(
      id: id,
      name: name,
      iconCode: icon.codePoint,
      colorHex: color.toARGB32(),
      type: type,
      targetValue: targetValue,
      unit: unit,
      frequency: HabitFrequency.daily,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }
}

const habitPresets = <HabitPreset>[
  HabitPreset(
    name: '俯卧撑',
    icon: Icons.fitness_center_rounded,
    color: AppColors.seed,
    subtitle: '每天 30 个',
    type: HabitType.count,
    targetValue: 30,
    unit: '个',
  ),
  HabitPreset(
    name: '跑步',
    icon: Icons.directions_run_rounded,
    color: Color(0xFF0EA5E9),
    subtitle: '每次 20 分钟',
    type: HabitType.duration,
    targetValue: 20,
    unit: '分钟',
  ),
  HabitPreset(
    name: '拉伸',
    icon: Icons.self_improvement_rounded,
    color: Color(0xFF8B5CF6),
    subtitle: '10 分钟放松',
    type: HabitType.duration,
    targetValue: 10,
    unit: '分钟',
  ),
  HabitPreset(
    name: '深蹲',
    icon: Icons.sports_gymnastics_rounded,
    color: Color(0xFFF59E0B),
    subtitle: '每天 50 个',
    type: HabitType.count,
    targetValue: 50,
    unit: '个',
  ),
  HabitPreset(
    name: '喝水',
    icon: Icons.water_drop_rounded,
    color: Color(0xFF14B8A6),
    subtitle: '每天 8 杯',
    type: HabitType.count,
    targetValue: 8,
    unit: '杯',
  ),
  HabitPreset(
    name: '早睡',
    icon: Icons.bedtime_rounded,
    color: Color(0xFF6366F1),
    subtitle: '23:00 前躺下',
    type: HabitType.check,
  ),
];
