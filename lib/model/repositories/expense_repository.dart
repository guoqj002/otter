import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../../domain/entities/expense.dart';

/// 记账仓储
class ExpenseRepository {
  ExpenseRepository(this.db);

  final AppDatabase db;

  ExpenseModel _map(Expense r) => ExpenseModel(
        id: r.id,
        category: r.category,
        amountCents: r.amountCents,
        type: r.type,
        note: r.note,
        localDate: r.localDate,
        createdAt: r.createdAt,
      );

  Future<void> add(ExpenseModel e) =>
      db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: e.id,
            category: e.category,
            amountCents: e.amountCents,
            type: Value(e.type),
            note: Value(e.note),
            localDate: e.localDate,
            createdAt: e.createdAt,
          ));

  Future<void> delete(String id) =>
      (db.delete(db.expenses)..where((t) => t.id.equals(id))).go();

  /// 任意日期区间 [fromDate, toDate) 的流水，按日期倒序
  /// 例：rangeList('2026-11-01', '2026-12-01')
  Future<List<ExpenseModel>> rangeList(String fromDate, String toDate) {
    return (db.select(db.expenses)
          ..where((t) =>
              t.localDate.isBiggerOrEqualValue(fromDate) &
              t.localDate.isSmallerThanValue(toDate))
          ..orderBy([
            (u) => OrderingTerm.desc(u.localDate),
            (u) => OrderingTerm.desc(u.createdAt),
          ]))
        .get()
        .then((rows) => rows.map(_map).toList());
  }

  /// 某月流水，按日期倒序
  Future<List<ExpenseModel>> monthList(String yearMonth) {
    final from = '$yearMonth-01';
    final to = _nextMonthStart(yearMonth);
    return rangeList(from, to);
  }

  static String _nextMonthStart(String yearMonth) {
    final y = int.parse(yearMonth.substring(0, 4));
    final m = int.parse(yearMonth.substring(5, 7));
    return m == 12 ? '${y + 1}-01-01' : '$y-${(m + 1).toString().padLeft(2, '0')}-01';
  }
}
