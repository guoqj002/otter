import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/services/streak_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/habit.dart';
import '../../application/providers/data_providers.dart';
import '../widgets/common.dart';
import 'check_in_sheet.dart';
import 'habit_check_in_tile.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);
    final todayMapAsync = ref.watch(todayCheckInsProvider);
    final dateSetsAsync = ref.watch(dateSetsProvider);
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: habitsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (habits) {
            if (habits.isEmpty) {
              return _HomeHeader(
                done: 0,
                total: 0,
                child: EmptyState(
                  icon: Icons.add_task_rounded,
                  title: '还没有习惯',
                  subtitle: '创建第一个习惯，从今天开始。\n30 秒就能搞定。',
                  action: FilledButton.icon(
                    onPressed: () => context.push('/habit/new'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('创建习惯'),
                  ),
                ),
              );
            }

            final doneMap = todayMapAsync.valueOrNull ?? const <String, CheckInModel>{};
            final sets = dateSetsAsync.valueOrNull ?? const <String, Set<String>>{};

            // 今日需打卡（按频率过滤），已打卡的也保留展示
            final scheduled = habits.where((h) => h.isScheduledOn(now)).toList();
            final todayHabits = habits
                .where((h) => h.isScheduledOn(now) || doneMap.containsKey(h.id))
                .toList();
            final others = habits.where((h) => !todayHabits.contains(h)).toList();

            final doneCount = scheduled.where((h) => doneMap.containsKey(h.id)).length;
            final totalCount = scheduled.length;
            final allDone = totalCount > 0 && doneCount >= totalCount;

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(dateSetsProvider);
                ref.invalidate(todayCheckInsProvider);
                await ref.read(dateSetsProvider.future);
              },
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _HomeHeader(
                      done: doneCount,
                      total: totalCount,
                      allDone: allDone,
                      child: const SizedBox.shrink(),
                    ),
                  ),
                  if (allDone)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: _AllDoneBanner(),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    sliver: SliverToBoxAdapter(
                      child: SectionTitle('今日待办 · $doneCount/$totalCount'),
                    ),
                  ),
                  if (todayHabits.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Icon(Icons.self_improvement_rounded,
                                    size: 32,
                                    color: scheme.onSurfaceVariant),
                                const SizedBox(height: 10),
                                const Text('今天没有安排',
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text('休息也是训练的一部分',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.separated(
                      itemCount: todayHabits.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final h = todayHabits[i];
                        final checkIn = doneMap[h.id];
                        final set = sets[h.id] ?? const <String>{};
                        final streak = StreakCalculator.current(h, set);
                        return HabitCheckInTile(
                          habit: h,
                          checkIn: checkIn,
                          streak: streak,
                          highlight: i == 0 && checkIn == null && doneCount == 0,
                          onTap: () => _onTapHabit(context, ref, h, checkIn),
                          onUndo: checkIn == null
                              ? null
                              : () => _undo(context, ref, h),
                          onOpenDetail: () => context.push('/habit/${h.id}'),
                        );
                      },
                    ),
                  ),
                  if (others.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                      sliver: SliverToBoxAdapter(
                        child: SectionTitle('今天不需要 · ${others.length}'),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.separated(
                        itemCount: others.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final h = others[i];
                          return Opacity(
                            opacity: 0.55,
                            child: HabitCheckInTile(
                              habit: h,
                              checkIn: null,
                              streak: StreakCalculator.current(
                                  h, sets[h.id] ?? const <String>{}),
                              highlight: false,
                              onTap: () => context.push('/habit/${h.id}'),
                              onUndo: null,
                              onOpenDetail: () => context.push('/habit/${h.id}'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/habit/new'),
        backgroundColor: AppColors.seed,
        foregroundColor: Colors.white,
        tooltip: '新建习惯',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Future<void> _onTapHabit(
    BuildContext context,
    WidgetRef ref,
    HabitModel habit,
    CheckInModel? existing,
  ) async {
    if (existing != null) {
      // 已打卡 → 展示撤销选项
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.event_repeat_rounded,
                    color: habitColor(habit)),
                title: Text(habit.name),
                subtitle: Text('今天已完成 · ${existing.doneDateTime.hour.toString().padLeft(2, '0')}:${existing.doneDateTime.minute.toString().padLeft(2, '0')}'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.undo_rounded),
                title: const Text('撤销今日打卡'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _undo(context, ref, habit);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart_rounded),
                title: const Text('查看详情'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/habit/${habit.id}');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      return;
    }

    if (habit.type == HabitType.check) {
      await _doCheckIn(context, ref, habit, null);
      return;
    }

    // 数值/时长型：底部弹层输入
    final value = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CheckInSheet(habit: habit),
    );
    if (value == null || !context.mounted) return;
    await _doCheckIn(context, ref, habit, value);
  }

  Future<void> _doCheckIn(
    BuildContext context,
    WidgetRef ref,
    HabitModel habit,
    double? value,
  ) async {
    final repo = ref.read(repoProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await repo.checkIn(habit, value: value);
      if (!created) {
        messenger.showSnackBar(
          const SnackBar(content: Text('今天已经打过卡啦')),
        );
        return;
      }
      // 刷新依赖数据
      ref.invalidate(todayCheckInsProvider);
      ref.invalidate(dateSetsProvider);

      final stats = await repo.statsOf(habit);
      final milestones = await repo.detectMilestones(habit, stats);
      if (milestones.isNotEmpty && context.mounted) {
        await showMilestoneDialog(context, milestones.first, habit);
      } else if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('已完成 · 连续 ${stats.currentStreak} 天'),
            duration: const Duration(milliseconds: 1400),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('打卡失败：$e')));
    }
  }

  Future<void> _undo(BuildContext context, WidgetRef ref, HabitModel habit) async {
    final messenger = ScaffoldMessenger.of(context);
    var undone = false;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('已撤销「${habit.name}」'),
        action: SnackBarAction(
          label: '恢复',
          onPressed: () async {
            if (undone) return;
            undone = true;
            await ref.read(repoProvider).checkIn(habit);
            ref.invalidate(todayCheckInsProvider);
            ref.invalidate(dateSetsProvider);
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
    await ref.read(repoProvider).undoCheckIn(habit, DateTime.now());
    ref.invalidate(todayCheckInsProvider);
    ref.invalidate(dateSetsProvider);
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.done,
    required this.total,
    required this.child,
    this.allDone = false,
  });

  final int done;
  final int total;
  final Widget child;
  final bool allDone;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${now.month}月${now.day}日 · 周${Dates.weekdayNames[now.weekday - 1]}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      allDone
                          ? '今天全部完成 🎉'
                          : (total == 0 ? '今天轻松一下' : '还有 ${total - done} 项待完成'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              ProgressRing(done: done, total: total),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _AllDoneBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withValues(alpha: 0.14),
            AppColors.seed.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: AppColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '今天的习惯已全部完成，继续保持！',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
