import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers/data_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/habit.dart';
import '../widgets/habit_icon_art.dart';
import '../widgets/common.dart';
import 'stats_finance_section.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  int _rangeDays = 14;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(statsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (stats) {
          if (stats.isEmpty) {
            return const EmptyState(
              icon: Icons.pie_chart_rounded,
              title: '还没有数据',
              subtitle: '创建习惯并打卡后，这里会显示你的坚持曲线',
            );
          }
          final totalDone = stats.fold<int>(0, (s, e) => s + e.totalCheckIns);
          final best = stats.reduce((a, b) => a.currentStreak >= b.currentStreak ? a : b);
          final avgRate = stats.fold<double>(0, (s, e) => s + e.completionRate) / stats.length;
          final sorted = [...stats]..sort((a, b) => b.completionRate.compareTo(a.completionRate));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  _kpi('累计打卡', '$totalDone', '次', AppColors.seed, scheme),
                  const SizedBox(width: 10),
                  _kpi('最长连续', '${best.longestStreak}', '天', AppColors.warning, scheme),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _kpi('本月完成率', '${(avgRate * 100).round()}', '%', AppColors.success, scheme),
                  const SizedBox(width: 10),
                  _kpi('在坚持的习惯', '${stats.length}', '个', scheme.primary, scheme),
                ],
              ),
              const SizedBox(height: 22),
              SectionTitle(
                '近 $_rangeDays 天打卡趋势',
                trailing: SegmentedButton<int>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7天')),
                    ButtonSegment(value: 14, label: Text('14天')),
                    ButtonSegment(value: 30, label: Text('30天')),
                  ],
                  selected: {_rangeDays},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _rangeDays = s.first),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
                  child: ref.watch(dailyTotalsProvider(_rangeDays)).when(
                        loading: () => const SizedBox(
                            height: 150,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                        error: (e, _) => SizedBox(
                            height: 150, child: Center(child: Text('$e'))),
                        data: (data) => _BarChart(
                          days: _rangeDays,
                          data: data,
                          color: AppColors.seed,
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 22),
              const FinanceStatsSection(),
              const SizedBox(height: 22),
              const SectionTitle('完成率排行'),
              for (final s in sorted) ...[
                _HabitRateRow(stats: s),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 14),
              Text(
                '完成率按本月「应打卡天数」计算；每周 N 次类型按周目标折算。',
                style: TextStyle(fontSize: 11.5, height: 1.6, color: scheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _kpi(String label, String value, String unit, Color color, ColorScheme scheme) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                  const SizedBox(width: 3),
                  Text(unit,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 简易柱状图（自绘，避免引入图表依赖的体积开销）
class _BarChart extends StatelessWidget {
  const _BarChart({required this.days, required this.data, required this.color});

  final int days;
  final Map<String, int> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = Dates.dateOnly(DateTime.now());
    final start = today.subtract(Duration(days: days - 1));
    final values = <int>[];
    final labels = <String>[];
    for (var i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      values.add(data[Dates.fmt(d)] ?? 0);
      labels.add('${d.day}');
    }
    final maxV = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: days > 20 ? 1.2 : 2.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          height: maxV == 0
                              ? 3
                              : (values[i] / maxV * 92).clamp(3.0, 92.0),
                          decoration: BoxDecoration(
                            color: values[i] == 0
                                ? scheme.surfaceContainerHighest
                                : color.withValues(
                                    alpha: 0.55 + 0.45 * (values[i] / (maxV == 0 ? 1 : maxV))),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: days > 20 && i % 3 != 0
                    ? const SizedBox.shrink()
                    : Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
                      ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HabitRateRow extends StatelessWidget {
  const _HabitRateRow({required this.stats});

  final HabitStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final habit = stats.habit;
    final color = Color(habit.colorHex);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/habit/${habit.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: HabitIconArtImage(code: habit.iconCode, size: 26),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(habit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                  StreakBadge(
                    streak: stats.currentStreak,
                    unit: habit.frequency == HabitFrequency.weekly ? '周' : '天',
                    compact: true,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${stats.completionPercent}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: stats.completionRate,
                  minHeight: 5,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('累计 ${stats.totalCheckIns} 次 · 最长 ${stats.longestStreak} 天',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  Text('本月 ${stats.scheduledDays} 个应打卡日',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
