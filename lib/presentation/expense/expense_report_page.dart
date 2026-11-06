import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/expense_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import 'expense_categories.dart';

/// 报表统计：日 / 月 / 年的收支汇总、趋势图与分类排行
class ExpenseReportPage extends ConsumerWidget {
  const ExpenseReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(expensePeriodModeProvider);
    final anchor = ref.watch(expenseAnchorProvider);
    final listAsync = ref.watch(expensesOfPeriodProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('报表统计')),
      body: Column(
        children: [
          _ReportModeSwitcher(mode: mode),
          _ReportPeriodSwitcher(mode: mode, anchor: anchor),
          listAsync.when(
            loading: () => const Expanded(
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Expanded(
                child: Center(child: Text('加载失败：$e',
                    style: TextStyle(color: scheme.onSurfaceVariant)))),
            data: (list) {
              final stats = ref.watch(expenseStatsProvider(list));
              return Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    _ReportSummaryCard(stats: stats),
                    const SizedBox(height: 14),
                    // 趋势图：日模式无趋势，仅分类排行
                    if (list.isNotEmpty) ...[
                      if (mode == ExpensePeriodMode.month) ...[
                        _SectionCard(
                            title: '每日收支趋势',
                            child: _TrendBars.fromDaily(
                              series: dailySeries(list),
                              month: Dates.fmt(anchor).substring(0, 7),
                            )),
                        const SizedBox(height: 14),
                      ] else if (mode == ExpensePeriodMode.year) ...[
                        _SectionCard(
                            title: '每月收支趋势',
                            child: _TrendBars.fromMonthly(
                              series: monthlySeries(list),
                              year: anchor.year,
                            )),
                        const SizedBox(height: 14),
                      ],
                      _CategoryRankCard(
                          title: '支出分类',
                          byCategory: stats.expenseByCategory,
                          totalCents: stats.expenseCents,
                          isIncome: false),
                      const SizedBox(height: 12),
                      _CategoryRankCard(
                          title: '收入分类',
                          byCategory: stats.incomeByCategory,
                          totalCents: stats.incomeCents,
                          isIncome: true),
                    ],
                    if (list.isEmpty) ...[
                      const SizedBox(height: 48),
                      Column(
                        children: [
                          Image.asset('assets/habit_icons/otter_read.png',
                              width: 96,
                              height: 96,
                              filterQuality: FilterQuality.high),
                          const SizedBox(height: 12),
                          Text('该周期暂无收支数据',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- 模式 / 周期切换

class _ReportModeSwitcher extends ConsumerWidget {
  const _ReportModeSwitcher({required this.mode});

  final ExpensePeriodMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ExpensePeriodMode>(
          segments: const [
            ButtonSegment(
                value: ExpensePeriodMode.day, label: Text('按日')),
            ButtonSegment(
                value: ExpensePeriodMode.month, label: Text('按月')),
            ButtonSegment(
                value: ExpensePeriodMode.year, label: Text('按年')),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              ref.read(expensePeriodModeProvider.notifier).state = s.first,
        ),
      ),
    );
  }
}

class _ReportPeriodSwitcher extends ConsumerWidget {
  const _ReportPeriodSwitcher({required this.mode, required this.anchor});

  final ExpensePeriodMode mode;
  final DateTime anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => ref.read(expenseAnchorProvider.notifier).state =
                _shift(anchor, -1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text(periodTitle(mode, anchor),
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w700)),
          IconButton(
            onPressed: () => ref.read(expenseAnchorProvider.notifier).state =
                _shift(anchor, 1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const Spacer(),
          TextButton(
            onPressed: () =>
                ref.read(expenseAnchorProvider.notifier).state = DateTime.now(),
            child: Text('回到今天',
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  DateTime _shift(DateTime d, int delta) {
    switch (mode) {
      case ExpensePeriodMode.day:
        return Dates.dateOnly(d).add(Duration(days: delta));
      case ExpensePeriodMode.month:
        var y = d.year;
        var m = d.month + delta;
        if (m < 1) { m = 12; y--; }
        if (m > 12) { m = 1; y++; }
        return DateTime(y, m);
      case ExpensePeriodMode.year:
        return DateTime(d.year + delta);
    }
  }
}

// --------------------------------------------------------------- 汇总

class _ReportSummaryCard extends StatelessWidget {
  const _ReportSummaryCard({required this.stats});

  final ExpenseStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.seed.withValues(alpha: 0.14),
            AppColors.seed.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.seed.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AmountBlock(
                label: '收入',
                cents: stats.incomeCents,
                color: AppColors.success),
          ),
          Container(
              width: 1,
              height: 34,
              color: AppColors.seed.withValues(alpha: 0.25)),
          Expanded(
            child: _AmountBlock(
                label: '支出',
                cents: stats.expenseCents,
                color: AppColors.seed),
          ),
          Container(
              width: 1,
              height: 34,
              color: AppColors.seed.withValues(alpha: 0.25)),
          Expanded(
            child: _AmountBlock(
                label: '结余',
                cents: stats.balanceCents,
                color: stats.balanceCents < 0
                    ? AppColors.danger
                    : AppColors.success,
                signed: true),
          ),
        ],
      ),
    );
  }
}

class _AmountBlock extends StatelessWidget {
  const _AmountBlock({
    required this.label,
    required this.cents,
    required this.color,
    this.signed = false,
  });

  final String label;
  final int cents;
  final Color color;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(
            '${signed && cents > 0 ? '+' : signed && cents < 0 ? '-' : ''}${fmtCents(cents.abs())}',
            style: TextStyle(
                fontSize: 18.5, fontWeight: FontWeight.w800, color: color),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- 区块卡片

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1F2937)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF374151)
              : const Color(0xFFE7E5E4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                    color: AppColors.seed,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendDot(color: AppColors.success),
                  const SizedBox(width: 4),
                  Text('收入',
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 10),
                  _LegendDot(color: AppColors.seed),
                  const SizedBox(width: 4),
                  Text('支出',
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// --------------------------------------------------------------- 趋势柱状图

/// 一组趋势数据：label + (收入, 支出)
class _TrendEntry {
  const _TrendEntry(this.label, this.incomeCents, this.expenseCents);
  final String label;
  final int incomeCents;
  final int expenseCents;
}

class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.entries});

  final List<_TrendEntry> entries;

  factory _TrendBars.fromDaily({
    required Map<String, (int, int)> series,
    required String month, // YYYY-MM
  }) {
    final y = int.parse(month.substring(0, 4));
    final m = int.parse(month.substring(5, 7));
    final days = DateTime(y, m + 1, 0).day;
    final entries = <_TrendEntry>[];
    for (var d = 1; d <= days; d++) {
      final key =
          '$month-${d.toString().padLeft(2, '0')}';
      final v = series[key] ?? (0, 0);
      entries.add(_TrendEntry('$d', v.$1, v.$2));
    }
    return _TrendBars(entries: entries);
  }

  factory _TrendBars.fromMonthly({
    required Map<String, (int, int)> series,
    required int year,
  }) {
    final entries = <_TrendEntry>[];
    for (var m = 1; m <= 12; m++) {
      final key = '$year-${m.toString().padLeft(2, '0')}';
      final v = series[key] ?? (0, 0);
      entries.add(_TrendEntry('$m月', v.$1, v.$2));
    }
    return _TrendBars(entries: entries);
  }

  @override
  Widget build(BuildContext context) {
    final maxCents = entries.fold<int>(
        0, (s, e) => [s, e.incomeCents, e.expenseCents].reduce((a, b) => a > b ? a : b));
    return Column(
      children: [
        SizedBox(
          height: 180,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(entries: entries, maxCents: maxCents),
          ),
        ),
        // 周期内没有数据时给一行提示
        if (maxCents == 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('周期内暂无数据',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.entries, required this.maxCents});

  final List<_TrendEntry> entries;
  final int maxCents;

  static const _axisColor = Color(0x3394A3B8);
  static const _labelColor = Color(0xFF94A3B8);

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 6.0;
    const bottomPad = 18.0;
    final chartW = size.width - leftPad * 2;
    final chartH = size.height - bottomPad - 8;

    // 网格线 + 左侧刻度
    final gridPaint = Paint()
      ..color = _axisColor
      ..strokeWidth = 1;
    final scale = _scaleLabel(maxCents);
    for (var i = 0; i <= 2; i++) {
      final y = 8.0 + chartH * i / 2;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - leftPad, y), gridPaint);
      if (i > 0) {
        _drawText(
            canvas,
            i == 1 ? scale.$2 : scale.$1,
            Offset(0, y - 5),
            const TextStyle(fontSize: 9, color: _labelColor));
      }
    }

    final n = entries.length;
    if (n == 0 || maxCents == 0) return;
    final groupW = chartW / n;
    final barW = (groupW * 0.56).clamp(2.0, 14.0);
    final radius = Radius.circular(barW / 3);

    for (var i = 0; i < n; i++) {
      final e = entries[i];
      final cx = leftPad + groupW * i + groupW / 2;
      final incomeH =
          maxCents == 0 ? 0.0 : chartH * e.incomeCents / maxCents;
      final expenseH =
          maxCents == 0 ? 0.0 : chartH * e.expenseCents / maxCents;
      final baseY = 8.0 + chartH;

      // 收入柱（左）
      if (incomeH > 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(cx - barW - 1.5, baseY - incomeH, barW, incomeH),
            topLeft: radius,
            topRight: radius,
          ),
          Paint()..color = AppColors.success,
        );
      }
      // 支出柱（右）
      if (expenseH > 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(cx + 1.5, baseY - expenseH, barW, expenseH),
            topLeft: radius,
            topRight: radius,
          ),
          Paint()..color = AppColors.seed,
        );
      }

      // X 轴标签：日模式太密时隔行显示
      final showEvery = n > 20 ? (n / 8).ceil() : 1;
      if (i % showEvery == 0 || i == n - 1) {
        _drawText(
            canvas,
            e.label,
            Offset(cx - 12, baseY + 4),
            const TextStyle(fontSize: 9, color: _labelColor),
            width: 24);
      }
    }
  }

  (String, String) _scaleLabel(int maxCents) {
    String fmt(int c) {
      final v = c / 100.0;
      if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}w';
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
      return v == v.roundToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(1);
    }
    final top = fmt(maxCents);
    final half = fmt(maxCents ~/ 2);
    return (top, half);
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style,
      {double width = 60}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.maxCents != maxCents ||
      old.entries.length != entries.length ||
      _listDiffers(old.entries, entries);

  static bool _listDiffers(List<_TrendEntry> a, List<_TrendEntry> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i].incomeCents != b[i].incomeCents ||
          a[i].expenseCents != b[i].expenseCents) {
        return true;
      }
    }
    return false;
  }
}

// --------------------------------------------------------------- 分类排行

class _CategoryRankCard extends StatelessWidget {
  const _CategoryRankCard({
    required this.title,
    required this.byCategory,
    required this.totalCents,
    required this.isIncome,
  });

  final String title;
  final Map<String, int> byCategory;
  final int totalCents;
  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal =
        entries.isEmpty ? 1 : entries.first.value;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1F2937)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF374151)
              : const Color(0xFFE7E5E4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                    color: isIncome ? AppColors.success : AppColors.seed,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('共 ${fmtCents(totalCents)}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isIncome ? AppColors.success : AppColors.seed)),
            ],
          ),
          const SizedBox(height: 12),
          for (final e in entries) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: isIncome
                              ? incomeCategoryOf(e.key).color.withValues(alpha: 0.14)
                              : categoryOf(e.key).color.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isIncome
                              ? incomeCategoryOf(e.key).icon
                              : categoryOf(e.key).icon,
                          size: 14,
                          color: isIncome
                              ? incomeCategoryOf(e.key).color
                              : categoryOf(e.key).color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(isIncome
                          ? incomeCategoryOf(e.key).label
                          : categoryOf(e.key).label,
                          style: const TextStyle(fontSize: 13)),
                      const Spacer(),
                      Text(
                        totalCents > 0
                            ? '${(e.value / totalCents * 100).toStringAsFixed(1)}%'
                            : '',
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 10),
                      Text(fmtCents(e.value),
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 5,
                      child: Row(
                        children: [
                          Expanded(
                            flex: e.value,
                            child: Container(
                                color: isIncome
                                    ? AppColors.success
                                    : AppColors.seed),
                          ),
                          if (maxVal > e.value)
                            Expanded(
                              flex: maxVal - e.value,
                              child: const SizedBox.shrink(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
