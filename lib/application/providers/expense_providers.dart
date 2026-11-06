import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../../domain/entities/expense.dart';
import '../../model/repositories/expense_repository.dart';
import 'data_providers.dart';

final expenseRepoProvider = Provider<ExpenseRepository>(
    (ref) => ExpenseRepository(ref.watch(databaseProvider)));

/// 统计周期模式
enum ExpensePeriodMode { day, month, year }

/// 当前查看的周期锚点日期
final expenseAnchorProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// 当前周期模式（日 / 月 / 年）
final expensePeriodModeProvider =
    StateProvider<ExpensePeriodMode>((ref) => ExpensePeriodMode.month);

/// 周期对应的日期区间 [from, to)，均为 YYYY-MM-DD
class ExpenseRange {
  const ExpenseRange(this.from, this.to);
  final String from;
  final String to;
}

ExpenseRange periodRange(ExpensePeriodMode mode, DateTime anchor) {
  switch (mode) {
    case ExpensePeriodMode.day:
      final d = Dates.fmt(anchor);
      final next = anchor.add(const Duration(days: 1));
      return ExpenseRange(d, Dates.fmt(next));
    case ExpensePeriodMode.month:
      final ym = Dates.fmt(anchor).substring(0, 7);
      final y = int.parse(ym.substring(0, 4));
      final m = int.parse(ym.substring(5, 7));
      final to = m == 12
          ? '${y + 1}-01-01'
          : '$y-${(m + 1).toString().padLeft(2, '0')}-01';
      return ExpenseRange('$ym-01', to);
    case ExpensePeriodMode.year:
      final y = anchor.year;
      return ExpenseRange('$y-01-01', '${y + 1}-01-01');
  }
}

/// 周期标题：2026 年 11 月 5 日 / 2026 年 11 月 / 2026 年
String periodTitle(ExpensePeriodMode mode, DateTime anchor) {
  switch (mode) {
    case ExpensePeriodMode.day:
      return '${anchor.year} 年 ${anchor.month} 月 ${anchor.day} 日';
    case ExpensePeriodMode.month:
      return '${anchor.year} 年 ${anchor.month} 月';
    case ExpensePeriodMode.year:
      return '${anchor.year} 年';
  }
}

/// 周期内流水列表
final expensesOfPeriodProvider =
    FutureProvider.autoDispose<List<ExpenseModel>>((ref) async {
  final mode = ref.watch(expensePeriodModeProvider);
  final anchor = ref.watch(expenseAnchorProvider);
  final range = periodRange(mode, anchor);
  return ref.watch(expenseRepoProvider).rangeList(range.from, range.to);
});

/// 指定月份流水（统计页用，key = YYYY-MM）
final expensesOfMonthProvider = FutureProvider.autoDispose
    .family<List<ExpenseModel>, String>((ref, ym) async {
  final y = int.parse(ym.substring(0, 4));
  final m = int.parse(ym.substring(5, 7));
  final range = periodRange(ExpensePeriodMode.month, DateTime(y, m));
  return ref.watch(expenseRepoProvider).rangeList(range.from, range.to);
});

/// 周期前后翻页：按日 / 月 / 年各自平移
DateTime shiftPeriod(ExpensePeriodMode mode, DateTime d, int delta) {
  switch (mode) {
    case ExpensePeriodMode.day:
      return Dates.dateOnly(d).add(Duration(days: delta));
    case ExpensePeriodMode.month:
      var y = d.year;
      var m = d.month + delta;
      if (m < 1) {
        m = 12;
        y--;
      }
      if (m > 12) {
        m = 1;
        y++;
      }
      return DateTime(y, m);
    case ExpensePeriodMode.year:
      return DateTime(d.year + delta);
  }
}

// ------------------------------------------------- 统计页财务区块（独立周期）

/// 统计页「财务概览」的周期模式与锚点，与记账页 / 理财页互不干扰
final statsFinanceModeProvider =
    StateProvider<ExpensePeriodMode>((ref) => ExpensePeriodMode.month);
final statsFinanceAnchorProvider =
    StateProvider<DateTime>((ref) => DateTime.now());

/// 统计页所选周期的收支流水
final statsExpensesProvider =
    FutureProvider.autoDispose<List<ExpenseModel>>((ref) async {
  final mode = ref.watch(statsFinanceModeProvider);
  final anchor = ref.watch(statsFinanceAnchorProvider);
  final range = periodRange(mode, anchor);
  return ref.watch(expenseRepoProvider).rangeList(range.from, range.to);
});

/// 周期汇总：收入/支出总额 + 分类小计
final expenseStatsProvider =
    Provider.autoDispose.family<ExpenseStats, List<ExpenseModel>>(
        (ref, list) => ExpenseStats.from(list));

class ExpenseStats {
  ExpenseStats({
    required this.incomeCents,
    required this.expenseCents,
    required this.count,
    required this.incomeByCategory,
    required this.expenseByCategory,
  });

  final int incomeCents;
  final int expenseCents;
  final int count;
  final Map<String, int> incomeByCategory; // code -> cents
  final Map<String, int> expenseByCategory; // code -> cents

  int get balanceCents => incomeCents - expenseCents;

  factory ExpenseStats.from(List<ExpenseModel> list) {
    var income = 0;
    var expense = 0;
    final byIncome = <String, int>{};
    final byExpense = <String, int>{};
    for (final e in list) {
      if (e.isIncome) {
        income += e.amountCents;
        byIncome[e.category] = (byIncome[e.category] ?? 0) + e.amountCents;
      } else {
        expense += e.amountCents;
        byExpense[e.category] = (byExpense[e.category] ?? 0) + e.amountCents;
      }
    }
    return ExpenseStats(
      incomeCents: income,
      expenseCents: expense,
      count: list.length,
      incomeByCategory: byIncome,
      expenseByCategory: byExpense,
    );
  }
}

/// 按天分组的日累计序列：key 为 YYYY-MM-DD，value 为 (收入, 支出)
Map<String, (int, int)> dailySeries(List<ExpenseModel> list) {
  final map = <String, (int, int)>{};
  for (final e in list) {
    final cur = map[e.localDate] ?? (0, 0);
    map[e.localDate] = e.isIncome
        ? (cur.$1 + e.amountCents, cur.$2)
        : (cur.$1, cur.$2 + e.amountCents);
  }
  return map;
}

/// 按月分组的月累计序列：key 为 YYYY-MM，value 为 (收入, 支出)
Map<String, (int, int)> monthlySeries(List<ExpenseModel> list) {
  final map = <String, (int, int)>{};
  for (final e in list) {
    final key = e.localDate.substring(0, 7);
    final cur = map[key] ?? (0, 0);
    map[key] = e.isIncome
        ? (cur.$1 + e.amountCents, cur.$2)
        : (cur.$1, cur.$2 + e.amountCents);
  }
  return map;
}
