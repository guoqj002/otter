import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/expense_providers.dart';
import '../../application/providers/invest_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/invest.dart';
import '../expense/expense_categories.dart' show fmtCents;

/// 理财页：股票 / 基金每日盈亏，日 / 月 / 年统计
/// 柱状图 / 折线图 / 日历三种视图；盈利红色，亏损绿色（A股习惯）
class InvestPage extends ConsumerWidget {
  const InvestPage({super.key});

  static const profitColor = Color(0xFFE5484D); // 盈利红
  static const lossColor = Color(0xFF23A55A); // 亏损绿

  /// 各类型的主题色（列表头像 / 图例）
  static Color kindColor(String kind) => switch (kind) {
        InvestModel.kindStock => const Color(0xFF7C5CE0),
        InvestModel.kindFund => const Color(0xFF0EA5E9),
        InvestModel.kindEtf => const Color(0xFF14B8A6),
        InvestModel.kindFutures => const Color(0xFFF59E0B),
        _ => const Color(0xFF94A3B8),
      };

  /// 各类型的图标
  static IconData kindIcon(String kind) => switch (kind) {
        InvestModel.kindStock => Icons.candlestick_chart_rounded,
        InvestModel.kindFund => Icons.pie_chart_rounded,
        InvestModel.kindEtf => Icons.show_chart_rounded,
        InvestModel.kindFutures => Icons.waterfall_chart_rounded,
        _ => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(investPeriodModeProvider);
    final anchor = ref.watch(investAnchorProvider);
    final listAsync = ref.watch(investListOfPeriodProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('理财')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('记一笔'),
      ),
      body: Column(
        children: [
          _ModeSwitcher(mode: mode),
          _PeriodSwitcher(mode: mode, anchor: anchor),
          listAsync.when(
            loading: () => const Expanded(
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Expanded(
                child: Center(child: Text('加载失败：$e',
                    style: TextStyle(color: scheme.onSurfaceVariant)))),
            data: (list) {
              final stats = ref.watch(investStatsProvider(list));
              return Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    _SummaryCard(stats: stats),
                    const SizedBox(height: 12),
                    if (mode != ExpensePeriodMode.day) ...[
                      const _ChartSection(),
                      const SizedBox(height: 12),
                    ],
                    if (list.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                            top: mode == ExpensePeriodMode.day ? 60 : 20),
                        child: Column(
                          children: [
                            Image.asset(
                                'assets/habit_icons/otter_stock.png',
                                width: 96,
                                height: 96,
                                filterQuality: FilterQuality.high),
                            const SizedBox(height: 12),
                            Text('这段时间还没有理财记录',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      )
                    else
                      ..._groupedByDay(context, ref, list),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _groupedByDay(
      BuildContext context, WidgetRef ref, List<InvestModel> list) {
    final widgets = <Widget>[];
    final groups = <String, List<InvestModel>>{};
    for (final e in list) {
      groups.putIfAbsent(e.localDate, () => []).add(e);
    }
    for (final entry in groups.entries) {
      var dayNet = 0;
      for (final e in entry.value) {
        dayNet += e.amountCents;
      }
      widgets.add(_DayHeader(date: entry.key, netCents: dayNet));
      for (final e in entry.value) {
        widgets.add(_InvestTile(record: e));
      }
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }
}

// --------------------------------------------------------------- 盈亏配色

Color profitColorOf(int cents) =>
    cents >= 0 ? InvestPage.profitColor : InvestPage.lossColor;

// --------------------------------------------------------------- 日/月/年切换

class _ModeSwitcher extends ConsumerWidget {
  const _ModeSwitcher({required this.mode});

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
                value: ExpensePeriodMode.day,
                label: Text('日'),
                icon: Icon(Icons.today_rounded, size: 17)),
            ButtonSegment(
                value: ExpensePeriodMode.month,
                label: Text('月'),
                icon: Icon(Icons.calendar_month_rounded, size: 17)),
            ButtonSegment(
                value: ExpensePeriodMode.year,
                label: Text('年'),
                icon: Icon(Icons.event_note_rounded, size: 17)),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              ref.read(investPeriodModeProvider.notifier).state = s.first,
        ),
      ),
    );
  }
}

class _PeriodSwitcher extends ConsumerWidget {
  const _PeriodSwitcher({required this.mode, required this.anchor});

  final ExpensePeriodMode mode;
  final DateTime anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => ref.read(investAnchorProvider.notifier).state =
                _shift(anchor, -1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text(periodTitle(mode, anchor),
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w700)),
          IconButton(
            onPressed: () => ref.read(investAnchorProvider.notifier).state =
                _shift(anchor, 1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const Spacer(),
          TextButton(
            onPressed: () =>
                ref.read(investAnchorProvider.notifier).state = DateTime.now(),
            child: const Text('回到今天'),
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

// --------------------------------------------------------------- 汇总卡片

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.stats});

  final InvestStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('盈利 +${fmtCents(stats.profitCents)}',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: InvestPage.profitColor)),
              const SizedBox(width: 16),
              Text('亏损 -${fmtCents(stats.lossCents)}',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: InvestPage.lossColor)),
              const Spacer(),
              Text('${stats.count} 笔',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '净盈亏 ${stats.netCents < 0 ? '-' : '+'}${fmtCents(stats.netCents.abs())}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: profitColorOf(stats.netCents),
                ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- 图表区

enum _ChartView { bar, line, calendar }

final investChartViewProvider =
    StateProvider<_ChartView>((ref) => _ChartView.bar);

class _ChartSection extends ConsumerWidget {
  const _ChartSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(investPeriodModeProvider);
    final listAsync = ref.watch(investListOfPeriodProvider);
    final view = ref.watch(investChartViewProvider);
    final anchor = ref.watch(investAnchorProvider);

    // 年模式下不提供日历视图
    final allowCalendar = mode == ExpensePeriodMode.month;
    final effectiveView =
        (view == _ChartView.calendar && !allowCalendar) ? _ChartView.bar : view;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
        children: [
          Row(
            children: [
              Text('盈亏走势',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              SegmentedButton<_ChartView>(
                segments: [
                  const ButtonSegment(
                      value: _ChartView.bar,
                      icon: Icon(Icons.bar_chart_rounded, size: 16),
                      label: Text('柱状')),
                  const ButtonSegment(
                      value: _ChartView.line,
                      icon: Icon(Icons.show_chart_rounded, size: 16),
                      label: Text('折线')),
                  if (allowCalendar)
                    const ButtonSegment(
                        value: _ChartView.calendar,
                        icon: Icon(Icons.calendar_view_month_rounded, size: 16),
                        label: Text('日历')),
                ],
                selected: {effectiveView},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelectionChanged: (s) =>
                    ref.read(investChartViewProvider.notifier).state = s.first,
              ),
            ],
          ),
          const SizedBox(height: 10),
          listAsync.maybeWhen(
            data: (list) {
              final isMonth = mode == ExpensePeriodMode.month;
              final series = isMonth
                  ? _fillDays(anchor, investDailySeries(list))
                  : _fillMonths(anchor.year, investMonthlySeries(list));
              switch (effectiveView) {
                case _ChartView.bar:
                  return _NetBarChart(series: series, monthMode: isMonth);
                case _ChartView.line:
                  return _NetLineChart(series: series, monthMode: isMonth);
                case _ChartView.calendar:
                  return _CalendarChart(
                      month: anchor, dayNet: investDailySeries(list));
              }
            },
            orElse: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator())),
          ),
          if (effectiveView != _ChartView.calendar)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(InvestPage.profitColor, '盈利'),
                  const SizedBox(width: 14),
                  _legendDot(InvestPage.lossColor, '亏损'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  /// 月模式：补齐当月每一天（无记录为 0）
  List<(String, int)> _fillDays(DateTime anchor, Map<String, int> raw) {
    final days = DateTime(anchor.year, anchor.month + 1, 0).day;
    return [
      for (var d = 1; d <= days; d++)
        (
          '$d',
          raw['${anchor.year}-${anchor.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}'] ?? 0
        )
    ];
  }

  /// 年模式：补齐 12 个月（无记录为 0）
  List<(String, int)> _fillMonths(int year, Map<String, int> raw) {
    return [
      for (var m = 1; m <= 12; m++)
        ('$m月', raw['$year-${m.toString().padLeft(2, '0')}'] ?? 0)
    ];
  }
}

// --------------------------------------------------------------- 柱状图

class _NetBarChart extends StatelessWidget {
  const _NetBarChart({required this.series, required this.monthMode});

  final List<(String, int)> series; // (label, netCents)
  final bool monthMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: CustomPaint(
        painter: _NetBarPainter(series: series, monthMode: monthMode),
      ),
    );
  }
}

class _NetBarPainter extends CustomPainter {
  _NetBarPainter({required this.series, required this.monthMode});

  final List<(String, int)> series;
  final bool monthMode;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 6.0;
    const padR = 6.0;
    const padB = 20.0;
    const padT = 14.0;
    final chartH = size.height - padT - padB;
    final chartW = size.width - padL - padR;
    final zeroY = padT + chartH / 2;

    var maxAbs = 0;
    for (final (_, v) in series) {
      if (v.abs() > maxAbs) maxAbs = v.abs();
    }
    if (maxAbs == 0) maxAbs = 1;

    // 零轴
    final zeroPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(padL, zeroY), Offset(size.width - padR, zeroY), zeroPaint);

    final slot = chartW / series.length;
    final barW = slot * 0.62;
    final barPaint = Paint();

    for (var i = 0; i < series.length; i++) {
      final (label, v) = series[i];
      if (v == 0) continue;
      final h = (v.abs() / maxAbs) * (chartH / 2 - 4);
      final cx = padL + slot * i + slot / 2;
      barPaint.color = v > 0 ? InvestPage.profitColor : InvestPage.lossColor;
      final rect = v > 0
          ? Rect.fromLTRB(cx - barW / 2, zeroY - h, cx + barW / 2, zeroY - 1)
          : Rect.fromLTRB(cx - barW / 2, zeroY + 1, cx + barW / 2, zeroY + h);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)), barPaint);
    }

    // X 轴标签（隔行抽稀）
    final tp = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );
    final step = monthMode
        ? (series.length > 20 ? 5 : (series.length > 10 ? 2 : 1))
        : 1;
    for (var i = 0; i < series.length; i += step) {
      tp.text = TextSpan(
        text: series[i].$1,
        style: TextStyle(
            fontSize: monthMode ? 8.5 : 9.5, color: Colors.grey),
      );
      tp.layout();
      final cx = padL + slot * i + slot / 2;
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - padB + 4));
    }

    // 最大刻度提示
    tp.text = TextSpan(
      text: _kFormat(maxAbs),
      style: TextStyle(fontSize: 9, color: Colors.grey),
    );
    tp.layout();
    tp.paint(canvas, Offset(padL, padT - 11));
  }

  static String _kFormat(int cents) {
    final v = cents / 100.0;
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}万';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(_NetBarPainter old) =>
      old.series != series || old.monthMode != monthMode;
}

// --------------------------------------------------------------- 折线图（累计净盈亏）

class _NetLineChart extends StatelessWidget {
  const _NetLineChart({required this.series, required this.monthMode});

  final List<(String, int)> series;
  final bool monthMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: CustomPaint(
        painter: _NetLinePainter(series: series, monthMode: monthMode),
      ),
    );
  }
}

class _NetLinePainter extends CustomPainter {
  _NetLinePainter({required this.series, required this.monthMode});

  final List<(String, int)> series;
  final bool monthMode;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 6.0;
    const padR = 6.0;
    const padB = 20.0;
    const padT = 14.0;
    final chartH = size.height - padT - padB;
    final chartW = size.width - padL - padR;

    // 累计净盈亏
    final cum = <double>[];
    var acc = 0;
    for (final (_, v) in series) {
      acc += v;
      cum.add(acc / 100.0);
    }
    var lo = 0.0;
    var hi = 0.0;
    for (final v in cum) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (hi - lo < 1) hi = lo + 1;

    double yOf(double v) =>
        padT + chartH * (1 - (v - lo) / (hi - lo));

    // 零轴（在范围内时）
    if (lo < 0 && hi > 0) {
      final zy = yOf(0);
      canvas.drawLine(
        Offset(padL, zy),
        Offset(size.width - padR, zy),
        Paint()
          ..color = Colors.grey.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }

    final net = cum.last;
    final lineColor = net >= 0 ? InvestPage.profitColor : InvestPage.lossColor;

    // 折线
    final path = Path();
    for (var i = 0; i < cum.length; i++) {
      final x = padL + chartW * i / (cum.length - 1).clamp(1, 1 << 30);
      final y = yOf(cum[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    // 面积填充（到底边）
    final area = Path.from(path)
      ..lineTo(size.width - padR, padT + chartH)
      ..lineTo(padL, padT + chartH)
      ..close();
    canvas.drawAreaIfValid(area, lineColor);

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);

    // 端点
    if (cum.isNotEmpty) {
      final lx = padL + chartW;
      final ly = yOf(net);
      canvas.drawCircle(Offset(lx, ly), 3.5, Paint()..color = lineColor);
      final tp = TextPainter(textDirection: ui.TextDirection.ltr)
        ..text = TextSpan(
          text:
              '${net < 0 ? '-' : '+'}${net.abs() >= 10000 ? '${(net.abs() / 10000).toStringAsFixed(1)}万' : net.abs().toStringAsFixed(0)}',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: lineColor),
        )
        ..layout();
      final dy = ly - tp.height - 6 < 0 ? ly + 8 : ly - tp.height - 6;
      var dx = lx - tp.width;
      if (dx < 0) dx = 0;
      tp.paint(canvas, Offset(dx, dy));
    }

    // X 轴标签
    final tp2 = TextPainter(textDirection: ui.TextDirection.ltr);
    final step = monthMode
        ? (series.length > 20 ? 5 : (series.length > 10 ? 2 : 1))
        : 1;
    for (var i = 0; i < series.length; i += step) {
      tp2.text = TextSpan(
        text: series[i].$1,
        style: TextStyle(fontSize: monthMode ? 8.5 : 9.5, color: Colors.grey),
      );
      tp2.layout();
      final x = padL + chartW * i / (series.length - 1).clamp(1, 1 << 30);
      tp2.paint(canvas, Offset(x - tp2.width / 2, size.height - padB + 4));
    }
  }

  @override
  bool shouldRepaint(_NetLinePainter old) =>
      old.series != series || old.monthMode != monthMode;
}

extension _DrawArea on Canvas {
  void drawAreaIfValid(Path area, Color color) {
    final bounds = area.getBounds();
    if (!bounds.isFinite) return;
    if (bounds.width <= 0 || bounds.height <= 0) return;
    drawPath(
      area,
      Paint()..color = color.withValues(alpha: 0.12),
    );
  }
}

// --------------------------------------------------------------- 日历视图

class _CalendarChart extends StatelessWidget {
  const _CalendarChart({required this.month, required this.dayNet});

  final DateTime month; // 锚点（年月有效）
  final Map<String, int> dayNet; // 'YYYY-MM-DD' -> net cents

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1; // 周一为第一列
    final cells = <int?>[for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++) d];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      children: [
        Row(
          children: [
            for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text('周$w',
                      style: TextStyle(
                          fontSize: 10.5, color: scheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < cells.length / 7; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(cells[r * 7 + c], scheme, context)),
            ],
          ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                    color: InvestPage.profitColor.withValues(alpha: 0.25),
                    shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('盈利日', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 14),
            Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                    color: InvestPage.lossColor.withValues(alpha: 0.25),
                    shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('亏损日', style: TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _cell(int? day, ColorScheme scheme, BuildContext context) {
    if (day == null) return const SizedBox(height: 52);
    final key =
        '${month.year}-${month.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final net = dayNet[key] ?? 0;
    final has = dayNet.containsKey(key);
    final bg = !has
        ? Colors.transparent
        : (net >= 0
            ? InvestPage.profitColor.withValues(alpha: 0.16)
            : InvestPage.lossColor.withValues(alpha: 0.16));
    final valColor = has ? profitColorOf(net) : scheme.onSurfaceVariant;
    return Container(
      height: 52,
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$day',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: has ? FontWeight.w700 : FontWeight.w400,
                  color: has ? scheme.onSurface : scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            has
                ? '${net < 0 ? '-' : '+'}${_compact(net.abs())}'
                : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: valColor),
          ),
        ],
      ),
    );
  }

  static String _compact(int cents) {
    final v = cents / 100.0;
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}万';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }
}

// --------------------------------------------------------------- 流水列表

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.netCents});

  final String date;
  final int netCents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = Dates.parse(date);
    final label = '${d.month} 月 ${d.day} 日 · ${_weekday(d)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
          const Spacer(),
          Text(
            '净 ${netCents < 0 ? '-' : '+'}${fmtCents(netCents.abs())}',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: netCents == 0
                    ? scheme.onSurfaceVariant
                    : profitColorOf(netCents)),
          ),
        ],
      ),
    );
  }

  static String _weekday(DateTime d) =>
      ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][d.weekday - 1];
}

class _InvestTile extends ConsumerWidget {
  const _InvestTile({required this.record});

  final InvestModel record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final catColor = InvestPage.kindColor(record.kind);
    final kindIcon = InvestPage.kindIcon(record.kind);
    final kindLabel = InvestModel.labelOf(record.kind);
    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除这笔记录？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('删除')),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        await ref.read(investRepoProvider).delete(record.id);
        ref.invalidate(investListOfPeriodProvider);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1F2937)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF374151)
                : const Color(0xFFE7E5E4),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(kindIcon, size: 19, color: catColor),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.note?.trim().isNotEmpty == true
                      ? record.note!.trim()
                      : kindLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text(
                      '${record.isProfit ? '盈利' : '亏损'} · $kindLabel',
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Text(
              '${record.isProfit ? '+' : '-'}${fmtCents(record.amountCents.abs())}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: record.isProfit
                    ? InvestPage.profitColor
                    : InvestPage.lossColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- 记一笔

Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _AddInvestSheet(),
  );
}

class _AddInvestSheet extends ConsumerStatefulWidget {
  const _AddInvestSheet();

  @override
  ConsumerState<_AddInvestSheet> createState() => _AddInvestSheetState();
}

class _AddInvestSheetState extends ConsumerState<_AddInvestSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _kind = InvestModel.kindStock;
  bool _profit = true;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _amountOk {
    final v = double.tryParse(_amountCtrl.text.trim());
    return v != null && v > 0 && v < 10000000;
  }

  Future<void> _save() async {
    if (!_amountOk || _saving) return;
    setState(() => _saving = true);
    final abs = ((double.parse(_amountCtrl.text.trim())) * 100).round();
    final cents = _profit ? abs : -abs;
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(investRepoProvider).add(InvestModel(
          id: 'iv-$now',
          kind: _kind,
          amountCents: cents,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          localDate: Dates.fmt(_date),
          createdAt: now,
        ));
    ref.invalidate(investListOfPeriodProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _profit ? InvestPage.profitColor : InvestPage.lossColor;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('记一笔理财',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          // 类型：股票 / 基金 / ETF / 期货
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: [
                for (final k in InvestModel.kinds)
                  ButtonSegment(
                      value: k,
                      label: Text(InvestModel.labelOf(k)),
                      icon: Icon(InvestPage.kindIcon(k), size: 17)),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ),
          const SizedBox(height: 14),
          // 盈利 / 亏损（盈利红 / 亏损绿）
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: true,
                    label: Text('盈利',
                        style: TextStyle(
                            color: _profit
                                ? InvestPage.profitColor
                                : null,
                            fontWeight: _profit
                                ? FontWeight.w700
                                : FontWeight.w400)),
                    icon: Icon(Icons.north_east_rounded,
                        size: 17, color: _profit ? InvestPage.profitColor : null)),
                ButtonSegment(
                    value: false,
                    label: Text('亏损',
                        style: TextStyle(
                            color: !_profit
                                ? InvestPage.lossColor
                                : null,
                            fontWeight: !_profit
                                ? FontWeight.w700
                                : FontWeight.w400)),
                    icon: Icon(Icons.south_east_rounded,
                        size: 17, color: !_profit ? InvestPage.lossColor : null)),
              ],
              selected: {_profit},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _profit = s.first),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,6}\.?\d{0,2}')),
                  ],
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    prefixText: '¥ ',
                    prefixStyle: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: accent),
                    labelText: '金额',
                    helperText: _profit ? '记录盈利金额' : '记录亏损金额',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) setState(() => _date = d);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_rounded,
                          size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(DateFormat('M月d日').format(_date)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLength: 30,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '备注（可选）',
              hintText: '例如：贵州茅台、沪深300ETF',
              counterText: '',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _amountOk ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}
