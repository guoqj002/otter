import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/expense_providers.dart';
import '../../application/providers/invest_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/invest.dart';
import '../expense/expense_categories.dart';
import '../widgets/common.dart';

/// 统计页 · 财务概览：收支环形图 + 理财盈亏柱状图
/// 周期（日 / 月 / 年）可切换，两张图共用同一周期
class FinanceStatsSection extends ConsumerWidget {
  const FinanceStatsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(statsFinanceModeProvider);
    final anchor = ref.watch(statsFinanceAnchorProvider);
    final expensesAsync = ref.watch(statsExpensesProvider);
    final investAsync = ref.watch(statsInvestProvider);

    final scope = switch (mode) {
      ExpensePeriodMode.day => '当日',
      ExpensePeriodMode.month => '本月',
      ExpensePeriodMode.year => '本年',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          '财务概览',
          trailing: SegmentedButton<ExpensePeriodMode>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(value: ExpensePeriodMode.day, label: Text('日')),
              ButtonSegment(value: ExpensePeriodMode.month, label: Text('月')),
              ButtonSegment(value: ExpensePeriodMode.year, label: Text('年')),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              ref.read(statsFinanceModeProvider.notifier).state = s.first;
              // 切模式时把锚点收回今天，避免停留在很久以前的周期里
              ref.read(statsFinanceAnchorProvider.notifier).state =
                  DateTime.now();
            },
          ),
        ),
        _PeriodNav(mode: mode, anchor: anchor),
        const SizedBox(height: 6),
        const SectionTitle('收支'),
        _FinanceCard(
          child: expensesAsync.when(
            loading: () => const _ChartLoading(),
            error: (e, _) => _ChartError(e),
            data: (list) => _IncomeExpensePie(
              stats: ExpenseStats.from(list),
              scopeLabel: scope,
            ),
          ),
        ),
        const SizedBox(height: 22),
        const SectionTitle('理财盈亏'),
        _FinanceCard(
          child: investAsync.when(
            loading: () => const _ChartLoading(),
            error: (e, _) => _ChartError(e),
            data: (list) => _InvestBars(
              list: list,
              mode: mode,
              anchor: anchor,
              scopeLabel: scope,
            ),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- 周期导航

class _PeriodNav extends ConsumerWidget {
  const _PeriodNav({required this.mode, required this.anchor});

  final ExpensePeriodMode mode;
  final DateTime anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isToday =
        periodTitle(mode, anchor) == periodTitle(mode, DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2),
      child: Row(
        children: [
          _NavArrow(
            icon: Icons.chevron_left_rounded,
            onTap: () => ref.read(statsFinanceAnchorProvider.notifier).state =
                shiftPeriod(mode, anchor, -1),
          ),
          Expanded(
            child: Text(
              periodTitle(mode, anchor),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
          ),
          _NavArrow(
            icon: Icons.chevron_right_rounded,
            onTap: () => ref.read(statsFinanceAnchorProvider.notifier).state =
                shiftPeriod(mode, anchor, 1),
          ),
          SizedBox(
            width: 62,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: isToday
                  ? null
                  : () => ref.read(statsFinanceAnchorProvider.notifier).state =
                      DateTime.now(),
              child: Text(isToday ? '今天' : '回到今天',
                  style: const TextStyle(fontSize: 11.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
    );
  }
}

// --------------------------------------------------------------- 卡片骨架

class _FinanceCard extends StatelessWidget {
  const _FinanceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? const Color(0xFF374151) : const Color(0xFFE7E5E4),
        ),
      ),
      child: child,
    );
  }
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 150,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _ChartError extends StatelessWidget {
  const _ChartError(this.error);

  final Object error;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Text('$error',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
    );
  }
}

// --------------------------------------------------------------- 收支环形饼图

class _IncomeExpensePie extends StatelessWidget {
  const _IncomeExpensePie({required this.stats, required this.scopeLabel});

  final ExpenseStats stats;
  final String scopeLabel; // 当日 / 本月 / 本年

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = stats.incomeCents == 0 && stats.expenseCents == 0;

    return Column(
      children: [
        SizedBox(
          width: 168,
          height: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(168, 168),
                painter: _DonutPainter(
                  incomeCents: stats.incomeCents,
                  expenseCents: stats.expenseCents,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(empty ? '暂无收支' : '$scopeLabel结余',
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 3),
                  Text(
                    empty
                        ? '--'
                        : (stats.balanceCents >= 0 ? '+' : '-') +
                            fmtCents(stats.balanceCents.abs()),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: empty
                          ? scheme.onSurfaceVariant
                          : (stats.balanceCents < 0
                              ? AppColors.danger
                              : AppColors.success),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendItem(
              color: AppColors.success,
              label: '收入',
              value: fmtCents(stats.incomeCents),
            ),
            const SizedBox(width: 22),
            _LegendItem(
              color: AppColors.seed,
              label: '支出',
              value: fmtCents(stats.expenseCents),
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label ',
            style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.incomeCents, required this.expenseCents});

  final int incomeCents;
  final int expenseCents;

  static const _stroke = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _stroke) / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final total = incomeCents + expenseCents;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;

    if (total == 0) {
      paint.color = Colors.grey.withValues(alpha: 0.25);
      canvas.drawCircle(center, radius, paint);
      return;
    }

    const gap = 0.045; // 扇区间的小缝隙（弧度）
    final incomeSweep = math.pi * 2 * incomeCents / total;
    final expenseSweep = math.pi * 2 - incomeSweep;
    const start = -math.pi / 2;

    // 从 12 点方向顺时针：先收入（绿），再支出（橙）
    if (incomeSweep > gap * 2) {
      paint.color = AppColors.success;
      canvas.drawArc(rect, start + gap / 2, incomeSweep - gap, false, paint);
    }
    if (expenseSweep > gap * 2) {
      paint.color = AppColors.seed;
      canvas.drawArc(rect, start + incomeSweep + gap / 2, expenseSweep - gap,
          false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.incomeCents != incomeCents || old.expenseCents != expenseCents;
}

// --------------------------------------------------------------- 理财盈亏柱状图

class _InvestBars extends StatelessWidget {
  const _InvestBars({
    required this.list,
    required this.mode,
    required this.anchor,
    required this.scopeLabel,
  });

  final List<InvestModel> list;
  final ExpensePeriodMode mode;
  final DateTime anchor;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = InvestStats.from(list);
    final buckets = _buckets();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 170,
          width: double.infinity,
          child: CustomPaint(
            painter: _PLBarsPainter(
              values: buckets.values,
              labels: buckets.labels,
              marks: buckets.marks,
            ),
          ),
        ),
        if (stats.count == 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: Text('$scopeLabel暂无理财记录',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendItem(
                  color: InvestPageColors.profit,
                  label: '盈利',
                  value: fmtCents(stats.profitCents),
                ),
                const SizedBox(width: 18),
                _LegendItem(
                  color: InvestPageColors.loss,
                  label: '亏损',
                  value: fmtCents(stats.lossCents),
                ),
                const SizedBox(width: 18),
                _LegendItem(
                  color: stats.netCents >= 0
                      ? InvestPageColors.profit
                      : InvestPageColors.loss,
                  label: '净盈亏',
                  value:
                      '${stats.netCents >= 0 ? '+' : '-'}${fmtCents(stats.netCents.abs())}',
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 按周期把记录聚合成柱：日 → 逐笔；月 → 逐日；年 → 逐月
  _Buckets _buckets() {
    switch (mode) {
      case ExpensePeriodMode.day:
        if (list.isEmpty) {
          return const _Buckets(values: [], labels: [], marks: {});
        }
        final values = <int>[];
        final labels = <String>[];
        for (var i = 0; i < list.length; i++) {
          values.add(list[i].amountCents);
          labels.add('${i + 1}');
        }
        final marks = <int>{};
        final step = values.length > 12 ? (values.length / 6).ceil() : 1;
        for (var i = 0; i < values.length; i += step) {
          marks.add(i);
        }
        return _Buckets(values: values, labels: labels, marks: marks);

      case ExpensePeriodMode.month:
        final days = DateTime(anchor.year, anchor.month + 1, 0).day;
        final values = List<int>.filled(days, 0);
        for (final e in list) {
          final d = DateTime.tryParse(e.localDate);
          if (d == null) continue;
          final idx = d.day - 1;
          if (idx >= 0 && idx < days) values[idx] += e.amountCents;
        }
        return _Buckets(
          values: values,
          labels: [for (var i = 1; i <= days; i++) '$i'],
          marks: {
            0,
            4,
            9,
            14,
            19,
            24,
            if (days > 28) days - 1,
          },
        );

      case ExpensePeriodMode.year:
        final values = List<int>.filled(12, 0);
        for (final e in list) {
          final d = DateTime.tryParse(e.localDate);
          if (d == null) continue;
          values[d.month - 1] += e.amountCents;
        }
        return _Buckets(
          values: values,
          labels: [for (var i = 1; i <= 12; i++) '$i月'],
          marks: const {0, 2, 4, 6, 8, 10},
        );
    }
  }
}

class _Buckets {
  const _Buckets({
    required this.values,
    required this.labels,
    required this.marks,
  });

  final List<int> values;
  final List<String> labels;
  final Set<int> marks;
}

/// 理财红绿配色（与理财页保持一致）
class InvestPageColors {
  static const profit = Color(0xFFE5484D); // 盈利红
  static const loss = Color(0xFF23A55A); // 亏损绿
}

class _PLBarsPainter extends CustomPainter {
  _PLBarsPainter({
    required this.values,
    required this.labels,
    required this.marks,
  });

  /// 每根柱的净盈亏（有符号分）
  final List<int> values;
  final List<String> labels;

  /// 需要绘制 X 轴文字的下标
  final Set<int> marks;

  static const _labelColor = Color(0xFF94A3B8);
  static const _axisColor = Color(0x3394A3B8);

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 6.0;
    const bottomPad = 16.0;
    final chartW = size.width - leftPad * 2;
    final chartH = size.height - bottomPad - 10;
    final midY = 10.0 + chartH / 2;

    // 中轴（零线）
    final axis = Paint()
      ..color = _axisColor
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(leftPad, midY), Offset(size.width - leftPad, midY), axis);

    if (values.isEmpty) return; // 空状态由卡片下方的提示文字说明

    var maxAbs = 0;
    for (final v in values) {
      if (v.abs() > maxAbs) maxAbs = v.abs();
    }

    final n = values.length;
    final slot = chartW / n;
    final barW = (slot * 0.62).clamp(2.0, 18.0);
    final half = chartH / 2;

    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == 0 || maxAbs == 0) continue;
      final cx = leftPad + slot * i + slot / 2;
      final h = (half * v.abs() / maxAbs).clamp(2.0, half);
      final color = v > 0 ? InvestPageColors.profit : InvestPageColors.loss;
      final rect = v > 0
          ? Rect.fromLTWH(cx - barW / 2, midY - h, barW, h)
          : Rect.fromLTWH(cx - barW / 2, midY, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(barW / 2.4),
          topRight: Radius.circular(barW / 2.4),
          bottomLeft: Radius.circular(barW / 2.4),
          bottomRight: Radius.circular(barW / 2.4),
        ),
        Paint()..color = color.withValues(alpha: 0.9),
      );
    }

    // X 轴标签
    for (final i in marks) {
      if (i < 0 || i >= n || i >= labels.length) continue;
      _drawCentered(
        canvas,
        labels[i],
        Offset(leftPad + slot * i + slot / 2, size.height - bottomPad + 4),
        const TextStyle(fontSize: 9, color: _labelColor),
      );
    }
  }

  void _drawCentered(
      Canvas canvas, String text, Offset anchor, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(anchor.dx - tp.width / 2, anchor.dy));
  }

  @override
  bool shouldRepaint(covariant _PLBarsPainter old) =>
      !_listEquals(old.values, values) ||
      !_listEqualsStr(old.labels, labels) ||
      old.marks.length != marks.length;

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  static bool _listEqualsStr(List<String> a, List<String> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }
}
