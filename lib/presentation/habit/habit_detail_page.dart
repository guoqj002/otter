import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers/data_providers.dart';
import '../../application/providers/settings_provider.dart';
import '../../application/services/streak_calculator.dart';
import '../../core/notification/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/habit.dart';
import '../home/habit_check_in_tile.dart' show habitColor;
import '../widgets/habit_icon_art.dart';
import '../widgets/common.dart';
import '../widgets/heatmap.dart';

class HabitDetailPage extends ConsumerStatefulWidget {
  const HabitDetailPage({super.key, required this.habitId});

  final String habitId;

  @override
  ConsumerState<HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends ConsumerState<HabitDetailPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// 详情页直接删除：确认后连同打卡记录一并删除
  Future<void> _confirmDelete(
      BuildContext context, String habitId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个习惯？'),
        content: Text('「$name」的所有历史打卡记录会一并删除，且无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(repoProvider).deleteHabit(habitId);
    await ref
        .read(notificationServiceProvider)
        .cancelHabitReminder(habitId);
    ref.invalidate(habitsProvider);
    ref.invalidate(statsProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final habitAsync = ref.watch(habitByIdProvider(widget.habitId));
    final historyAsync = ref.watch(habitHistoryProvider(widget.habitId));
    final setsAsync = ref.watch(dateSetsProvider);
    final monthStatsAsync = ref.watch(habitMonthStatsProvider(widget.habitId));
    final scheme = Theme.of(context).colorScheme;

    return habitAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (habit) {
        if (habit == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.search_off_rounded,
              title: '习惯不存在',
              subtitle: '它可能已经被删除了',
            ),
          );
        }
        final color = habitColor(habit);
        final done = setsAsync.valueOrNull?[habit.id] ?? const <String>{};
        final history = historyAsync.valueOrNull ?? const <CheckInModel>[];
        final streak = StreakCalculator.current(habit, done);
        final longest = StreakCalculator.longest(habit, done);
        final monthFrom = DateTime(_month.year, _month.month, 1);
        final monthStats = monthStatsAsync.valueOrNull;
        final rate = monthStats?.completionRate ??
            StreakCalculator.completionRate(habit, done, monthFrom, DateTime.now());

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                HabitIconArtImage(code: habit.iconCode, size: 26),
                const SizedBox(width: 8),
                Flexible(child: Text(habit.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _confirmDelete(context, habit.id, habit.name),
              ),
              IconButton(
                tooltip: '编辑',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.push('/habit/${habit.id}/edit'),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dateSetsProvider);
              ref.invalidate(habitHistoryProvider(widget.habitId));
              await ref.read(dateSetsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      _stat('$streak', habit.frequency == HabitFrequency.weekly ? '当前周数' : '当前连续', color,
                          emphasize: true),
                      _divider(),
                      _stat('$longest', '历史最长', color),
                      _divider(),
                      _stat('${history.length}', '累计次数', color),
                      _divider(),
                      _stat('${(rate * 100).round()}%', '本月完成', color),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text(
                    '${habit.frequencyLabel} · ${habit.goalLabel}'
                    '${habit.reminderTime != null ? ' · 每天 ${habit.reminderTime} 提醒' : ''}',
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() =>
                          _month = DateTime(_month.year, _month.month - 1)),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(Dates.monthLabel(_month),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    IconButton(
                      onPressed: _month.month == DateTime.now().month &&
                              _month.year == DateTime.now().year
                          ? null
                          : () => setState(() =>
                              _month = DateTime(_month.year, _month.month + 1)),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                    child: MonthCalendar(
                      month: _month,
                      doneDates: done,
                      color: color,
                      scheduledCheck: habit.isScheduledOn,
                      onTapDay: (day) => _onTapDay(context, habit, day, done),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionTitle('近半年'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Heatmap(doneDates: done, color: color, weeks: 26),
                  ),
                ),
                const SizedBox(height: 20),
                SectionTitle('打卡记录 · ${history.length}',
                    trailing: Text('补卡：${ref.watch(settingsProvider).allowBackfill ? '已开启' : '未开启'}',
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant))),
                if (history.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text('还没有记录，去首页打第一个卡吧',
                            style: TextStyle(
                                fontSize: 13, color: scheme.onSurfaceVariant)),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < history.length && i < 60; i++) ...[
                          _historyTile(context, habit, history[i], color, i == 0),
                          if (i != history.length - 1 && i != 59)
                            Divider(
                                height: 1,
                                indent: 52,
                                color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 28),
                TextButton.icon(
                  onPressed: () => _confirmArchive(context, habit),
                  icon: Icon(Icons.archive_outlined, size: 18, color: scheme.onSurfaceVariant),
                  label: Text('归档这个习惯',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
      );

  Widget _stat(String value, String label, Color color, {bool emphasize = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 24 : 20,
              fontWeight: FontWeight.w800,
              color: emphasize ? color : Theme.of(context).colorScheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _historyTile(
      BuildContext context, HabitModel habit, CheckInModel c, Color color, bool isFirst) {
    final scheme = Theme.of(context).colorScheme;
    final value = c.value;
    String? detail;
    if (value != null && habit.type != HabitType.check) {
      final s = value == value.roundToDouble() ? value.toInt().toString() : value.toString();
      detail = '$s${habit.unit ?? ''}';
    }
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(Icons.check_rounded, size: 15, color: color),
      ),
      title: Text(
        Dates.friendlyDate(c.date),
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
      subtitle: detail == null
          ? null
          : Text(detail, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      trailing: Text(
        '${c.doneDateTime.hour.toString().padLeft(2, '0')}:${c.doneDateTime.minute.toString().padLeft(2, '0')}',
        style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }

  Future<void> _onTapDay(
    BuildContext context,
    HabitModel habit,
    DateTime day,
    Set<String> done,
  ) async {
    final key = Dates.fmt(day);
    if (done.contains(key)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('撤销 ${Dates.friendlyDate(day)} 的打卡？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('撤销'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await ref.read(repoProvider).undoCheckIn(habit, day);
        ref.invalidate(dateSetsProvider);
        ref.invalidate(habitHistoryProvider(habit.id));
      }
      return;
    }

    // 补卡
    final allow = ref.read(settingsProvider).allowBackfill;
    if (!allow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('补卡功能未开启，可在「我的 → 设置」中打开')),
      );
      return;
    }
    final days = Dates.daysBetween(day, DateTime.now());
    if (days > 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只能补打最近 7 天内的卡')),
      );
      return;
    }
    await ref.read(repoProvider).checkIn(habit, when: day, allowBackfill: true);
    ref.invalidate(dateSetsProvider);
    ref.invalidate(habitHistoryProvider(habit.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已补打 ${Dates.friendlyDate(day)}')),
      );
    }
  }

  Future<void> _confirmArchive(BuildContext context, HabitModel habit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档习惯？'),
        content: const Text('归档后不再出现在首页，历史记录会保留，可随时恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('归档')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repoProvider).archiveHabit(habit.id);
    ref.invalidate(habitsProvider);
    ref.invalidate(statsProvider);
    if (context.mounted) context.go('/');
  }
}
