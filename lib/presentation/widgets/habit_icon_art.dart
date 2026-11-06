import 'package:flutter/material.dart';

import '../../domain/entities/habit.dart';

/// 旧版 Material 图标，仅作为 [HabitModel.iconCode] 的存储键，
/// 保证老数据的码点仍能映射到水獭图标（不再直接渲染）。
const kHabitIcons = <IconData>[
  Icons.fitness_center_rounded,
  Icons.directions_run_rounded,
  Icons.pool_rounded,
  Icons.self_improvement_rounded,
  Icons.pedal_bike_rounded,
  Icons.hiking_rounded,
  Icons.sports_gymnastics_rounded,
  Icons.water_drop_rounded,
  Icons.bedtime_rounded,
  Icons.restaurant_rounded,
  Icons.monitor_weight_rounded,
  Icons.spa_rounded,
  Icons.wb_sunny_rounded,
  Icons.alarm_rounded,
  Icons.sports_martial_arts_rounded,
  Icons.sports_basketball_rounded,
];

/// 读书 / 俯卧撑水獭图标的存储键（emoji 码点，不与 Material 图标冲突）
const kOtterReadCode = 0x1F4DA; // 📚
const kOtterPushupCode = 0x1F4AA; // 💪

/// 卡通水獭习惯图标资源（assets/habit_icons/）
const kHabitIconAssets = <String>[
  'assets/habit_icons/otter_dumbbell.png', // 力量/俯卧撑
  'assets/habit_icons/otter_run.png', // 跑步
  'assets/habit_icons/otter_swim.png', // 游泳
  'assets/habit_icons/otter_yoga.png', // 瑜伽/冥想
  'assets/habit_icons/otter_bike.png', // 骑行
  'assets/habit_icons/otter_hike.png', // 徒步/爬楼
  'assets/habit_icons/otter_jumprope.png', // 跳绳/有氧
  'assets/habit_icons/otter_water.png', // 喝水
  'assets/habit_icons/otter_sleep.png', // 早睡
  'assets/habit_icons/otter_eat.png', // 饮食
  'assets/habit_icons/otter_stretch.png', // 拉伸
  'assets/habit_icons/otter_ball.png', // 球类
  'assets/habit_icons/otter_read.png', // 读书
  'assets/habit_icons/otter_pushup.png', // 俯卧撑
];

/// 旧码点索引 → 水獭图标索引（按语义就近映射）
const _legacyToArt = <int>[0, 1, 2, 3, 4, 5, 10, 7, 8, 9, 6, 3, 10, 8, 0, 11];

int _artIndexOf(int code) {
  if (code == kOtterReadCode) return 12;
  if (code == kOtterPushupCode) return 13;
  final i = kHabitIcons.indexWhere((e) => e.codePoint == code);
  if (i < 0) return 0;
  return _legacyToArt[i];
}

/// 图标选择器可选项的码点（按资源顺序）
final kHabitIconCodes = <int>[
  kHabitIcons[0].codePoint, // 力量
  kHabitIcons[1].codePoint, // 跑步
  kHabitIcons[2].codePoint, // 游泳
  kHabitIcons[3].codePoint, // 瑜伽
  kHabitIcons[4].codePoint, // 骑行
  kHabitIcons[5].codePoint, // 徒步
  kHabitIcons[10].codePoint, // 跳绳
  kHabitIcons[7].codePoint, // 喝水
  kHabitIcons[8].codePoint, // 早睡
  kHabitIcons[9].codePoint, // 饮食
  kHabitIcons[6].codePoint, // 拉伸
  kHabitIcons[15].codePoint, // 球类
  kOtterReadCode, // 读书
  kOtterPushupCode, // 俯卧撑
];

/// 码点 → 水獭图标资源路径
String habitIconAssetOf(int code) => kHabitIconAssets[_artIndexOf(code)];

/// 习惯 → 水獭图标资源路径
String habitIconAsset(HabitModel habit) => habitIconAssetOf(habit.iconCode);

/// 卡通水獭习惯图标（透明底 PNG，自适应任意底色）
class HabitIconArtImage extends StatelessWidget {
  const HabitIconArtImage({super.key, required this.code, this.size = 24});

  final int code;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      habitIconAssetOf(code),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
