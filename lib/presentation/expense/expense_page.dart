import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/expense_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/expense.dart';
import 'expense_categories.dart';
import 'expense_report_page.dart';

/// 记账页：周期（日/月/年）收支汇总 + 流水列表
class ExpensePage extends ConsumerWidget {
  const ExpensePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(expensePeriodModeProvider);
    final anchor = ref.watch(expenseAnchorProvider);
    final listAsync = ref.watch(expensesOfPeriodProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('记账'),
        actions: [
          IconButton(
            tooltip: '报表统计',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ExpenseReportPage())),
            icon: const Icon(Icons.bar_chart_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
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
              final stats = ref.watch(expenseStatsProvider(list));
              return Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    _SummaryCard(stats: stats),
                    const SizedBox(height: 12),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: Column(
                          children: [
                            Image.asset('assets/habit_icons/otter_read.png',
                                width: 96, height: 96, filterQuality: FilterQuality.high),
                            const SizedBox(height: 12),
                            Text('这段时间还没有记账',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      )
                    else
                      ..._groupedByDay(context, list),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _groupedByDay(BuildContext context, List<ExpenseModel> list) {
    final widgets = <Widget>[];
    final groups = <String, List<ExpenseModel>>{};
    for (final e in list) {
      groups.putIfAbsent(e.localDate, () => []).add(e);
    }
    for (final entry in groups.entries) {
      var dayIn = 0;
      var dayOut = 0;
      for (final e in entry.value) {
        if (e.isIncome) {
          dayIn += e.amountCents;
        } else {
          dayOut += e.amountCents;
        }
      }
      widgets.add(_DayHeader(
          date: entry.key, incomeCents: dayIn, expenseCents: dayOut));
      for (final e in entry.value) {
        widgets.add(_ExpenseTile(expense: e));
      }
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }
}

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
              ref.read(expensePeriodModeProvider.notifier).state = s.first,
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
            child: const Text('回到今天'),
          ),
        ],
      ),
    );
  }

  DateTime _shift(DateTime d, int delta) => shiftPeriod(mode, d, delta);
}

// --------------------------------------------------------------- 汇总卡片

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.stats});

  final ExpenseStats stats;

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
              Text('收入 ${fmtCents(stats.incomeCents)}',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success)),
              const SizedBox(width: 16),
              Text('支出 ${fmtCents(stats.expenseCents)}',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.seed)),
              const Spacer(),
              Text('${stats.count} 笔',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '结余 ${stats.balanceCents < 0 ? '-' : ''}${fmtCents(stats.balanceCents.abs())}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: stats.balanceCents < 0
                      ? AppColors.danger
                      : AppColors.seed,
                ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- 流水列表

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.incomeCents,
    required this.expenseCents,
  });

  final String date; // YYYY-MM-DD
  final int incomeCents;
  final int expenseCents;

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
          if (incomeCents > 0) ...[
            Text('收 ${fmtCents(incomeCents)}',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.success)),
            const SizedBox(width: 8),
          ],
          Text('支 ${fmtCents(expenseCents)}',
              style: TextStyle(
                  fontSize: 12.5,
                  color: expenseCents > 0
                      ? scheme.onSurfaceVariant
                      : scheme.onSurfaceVariant.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  static String _weekday(DateTime d) =>
      ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][d.weekday - 1];
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense});

  final ExpenseModel expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = categoryOfType(expense.type, expense.category);
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(expense.id),
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
        await ref.read(expenseRepoProvider).delete(expense.id);
        ref.invalidate(expensesOfPeriodProvider);
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
                color: cat.color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(cat.icon, size: 19, color: cat.color),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expense.note?.trim().isNotEmpty == true
                      ? expense.note!.trim()
                      : cat.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text(cat.label,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Text(
              expense.isIncome
                  ? '+${fmtCents(expense.amountCents)}'
                  : '-${fmtCents(expense.amountCents)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: expense.isIncome ? AppColors.success : null,
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
    builder: (ctx) => const _AddRecordSheet(),
  );
}

class _AddRecordSheet extends ConsumerStatefulWidget {
  const _AddRecordSheet();

  @override
  ConsumerState<_AddRecordSheet> createState() => _AddRecordSheetState();
}

class _AddRecordSheetState extends ConsumerState<_AddRecordSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _type = ExpenseModel.typeExpense;
  String _category = kExpenseCategories.first.code;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  List<ExpenseCategory> get _cats =>
      _type == ExpenseModel.typeIncome ? kIncomeCategories : kExpenseCategories;

  bool get _amountOk {
    final v = double.tryParse(_amountCtrl.text.trim());
    return v != null && v > 0 && v < 10000000;
  }

  void _switchType(String t) {
    setState(() {
      _type = t;
      // 切换收支时若当前分类不属于新类型则重置
      final codes = _cats.map((c) => c.code).toSet();
      if (!codes.contains(_category)) {
        _category = _cats.first.code;
      }
    });
  }

  Future<void> _save() async {
    if (!_amountOk || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final cents = ((double.parse(_amountCtrl.text.trim())) * 100).round();
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(expenseRepoProvider).add(ExpenseModel(
          id: 'e-$now',
          category: _category,
          amountCents: cents,
          type: _type,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          localDate: Dates.fmt(_date),
          createdAt: now,
        ));
    ref.invalidate(expensesOfPeriodProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = _type == ExpenseModel.typeIncome;
    final accent = isIncome ? incomeColor : expenseColor;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('记一笔',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          // 支出 / 收入 切换
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: ExpenseModel.typeExpense,
                    label: Text('支出'),
                    icon: Icon(Icons.north_east_rounded, size: 17)),
                ButtonSegment(
                    value: ExpenseModel.typeIncome,
                    label: Text('收入'),
                    icon: Icon(Icons.south_west_rounded, size: 17)),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _switchType(s.first),
            ),
          ),
          const SizedBox(height: 14),
          // 分类
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _cats)
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(c.icon, size: 15, color: c.color),
                      const SizedBox(width: 4),
                      Text(c.label),
                    ],
                  ),
                  selected: _category == c.code,
                  selectedColor: c.color.withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                      color: _category == c.code ? c.color : null,
                      fontWeight:
                          _category == c.code ? FontWeight.w700 : FontWeight.w400),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _category = c.code),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 金额
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    // 只允许数字和最多两位小数
                    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}\.?\d{0,2}')),
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
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              // 日期
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
              hintText: isIncome ? '例如：工资、红包' : '例如：午餐、打车',
              counterText: '',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.danger)),
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
