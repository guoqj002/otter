import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/invest.dart';
import '../../model/repositories/invest_repository.dart';
import 'expense_providers.dart'; // 复用 ExpensePeriodMode / periodRange / periodTitle
import 'data_providers.dart';

final investRepoProvider = Provider<InvestRepository>(
    (ref) => InvestRepository(ref.watch(databaseProvider)));

/// 理财页当前查看的周期锚点 / 模式（独立于记账页，互不干扰）
final investAnchorProvider = StateProvider<DateTime>((ref) => DateTime.now());
final investPeriodModeProvider =
    StateProvider<ExpensePeriodMode>((ref) => ExpensePeriodMode.month);

/// 周期内理财记录列表
final investListOfPeriodProvider =
    FutureProvider.autoDispose<List<InvestModel>>((ref) async {
  final mode = ref.watch(investPeriodModeProvider);
  final anchor = ref.watch(investAnchorProvider);
  final range = periodRange(mode, anchor);
  return ref.watch(investRepoProvider).rangeList(range.from, range.to);
});

/// 指定月份理财记录（统计页用，key = YYYY-MM）
final investOfMonthProvider = FutureProvider.autoDispose
    .family<List<InvestModel>, String>((ref, ym) async {
  final y = int.parse(ym.substring(0, 4));
  final m = int.parse(ym.substring(5, 7));
  final range = periodRange(ExpensePeriodMode.month, DateTime(y, m));
  return ref.watch(investRepoProvider).rangeList(range.from, range.to);
});

/// 统计页所选周期的理财记录（与财务概览共用同一周期）
final statsInvestProvider =
    FutureProvider.autoDispose<List<InvestModel>>((ref) async {
  final mode = ref.watch(statsFinanceModeProvider);
  final anchor = ref.watch(statsFinanceAnchorProvider);
  final range = periodRange(mode, anchor);
  return ref.watch(investRepoProvider).rangeList(range.from, range.to);
});

/// 周期汇总
class InvestStats {
  const InvestStats({
    required this.profitCents,
    required this.lossCents,
    required this.count,
    required this.profitByKind,
    required this.lossByKind,
  });

  final int profitCents; // 盈利总额（正数）
  final int lossCents; // 亏损总额（正数）
  final int count;
  final Map<String, int> profitByKind; // kind -> cents
  final Map<String, int> lossByKind;

  int get netCents => profitCents - lossCents;

  factory InvestStats.from(List<InvestModel> list) {
    var profit = 0;
    var loss = 0;
    final byProfit = <String, int>{};
    final byLoss = <String, int>{};
    for (final e in list) {
      if (e.amountCents >= 0) {
        profit += e.amountCents;
        byProfit[e.kind] = (byProfit[e.kind] ?? 0) + e.amountCents;
      } else {
        loss += -e.amountCents;
        byLoss[e.kind] = (byLoss[e.kind] ?? 0) - e.amountCents;
      }
    }
    return InvestStats(
      profitCents: profit,
      lossCents: loss,
      count: list.length,
      profitByKind: byProfit,
      lossByKind: byLoss,
    );
  }
}

final investStatsProvider =
    Provider.autoDispose.family<InvestStats, List<InvestModel>>(
        (ref, list) => InvestStats.from(list));

/// 按日净盈亏序列：key = YYYY-MM-DD，value = 有符号分
Map<String, int> investDailySeries(List<InvestModel> list) {
  final map = <String, int>{};
  for (final e in list) {
    map[e.localDate] = (map[e.localDate] ?? 0) + e.amountCents;
  }
  return map;
}

/// 按月净盈亏序列：key = YYYY-MM，value = 有符号分
Map<String, int> investMonthlySeries(List<InvestModel> list) {
  final map = <String, int>{};
  for (final e in list) {
    final key = e.localDate.substring(0, 7);
    map[key] = (map[key] ?? 0) + e.amountCents;
  }
  return map;
}
