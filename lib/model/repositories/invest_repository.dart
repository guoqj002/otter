import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../../domain/entities/invest.dart';

/// 理财仓储
class InvestRepository {
  InvestRepository(this.db);

  final AppDatabase db;

  InvestModel _map(InvestRecord r) => InvestModel(
        id: r.id,
        kind: r.kind,
        amountCents: r.amountCents,
        note: r.note,
        localDate: r.localDate,
        createdAt: r.createdAt,
      );

  Future<void> add(InvestModel e) =>
      db.into(db.investRecords).insert(InvestRecordsCompanion.insert(
            id: e.id,
            kind: e.kind,
            amountCents: e.amountCents,
            note: Value(e.note),
            localDate: e.localDate,
            createdAt: e.createdAt,
          ));

  Future<void> delete(String id) =>
      (db.delete(db.investRecords)..where((t) => t.id.equals(id))).go();

  /// 任意日期区间 [fromDate, toDate) 的记录，按日期倒序
  Future<List<InvestModel>> rangeList(String fromDate, String toDate) {
    return (db.select(db.investRecords)
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
}
