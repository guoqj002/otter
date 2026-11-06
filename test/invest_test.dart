import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitstreak/model/db/app_database.dart';
import 'package:fitstreak/model/repositories/invest_repository.dart';
import 'package:fitstreak/domain/entities/invest.dart';
import 'package:fitstreak/application/providers/invest_providers.dart';

void main() {
  late AppDatabase db;
  late InvestRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = InvestRepository(db);
  });

  tearDown(() async => db.close());

  InvestModel _m(String id, String date, int cents, {String kind = 'stock'}) =>
      InvestModel(
        id: id,
        kind: kind,
        amountCents: cents,
        localDate: date,
        createdAt: 1700000000000,
      );

  test('InvestStats 统计盈利/亏损/净额', () {
    final s = InvestStats.from([
      _m('a', '2026-11-01', 50000),
      _m('b', '2026-11-02', -20000, kind: 'fund'),
      _m('c', '2026-11-02', 30000),
    ]);
    expect(s.profitCents, 80000);
    expect(s.lossCents, 20000);
    expect(s.netCents, 60000);
    expect(s.count, 3);
    expect(s.lossByKind['fund'], 20000);
  });

  test('日 / 月序列聚合（有符号）', () {
    final list = [
      _m('a', '2026-11-01', 10000),
      _m('b', '2026-11-01', -4000),
      _m('c', '2026-12-05', 70000, kind: 'fund'),
    ];
    final daily = investDailySeries(list);
    expect(daily['2026-11-01'], 6000);
    final monthly = investMonthlySeries(list);
    expect(monthly['2026-11'], 6000);
    expect(monthly['2026-12'], 70000);
  });

  test('仓储写入 / 区间查询 / 删除回环', () async {
    await repo.add(_m('a', '2026-11-01', 10000));
    await repo.add(_m('b', '2026-11-30', -5000, kind: 'fund'));
    await repo.add(_m('c', '2026-12-01', 20000));

    final nov = await repo.rangeList('2026-11-01', '2026-12-01');
    expect(nov.length, 2);

    await repo.delete('a');
    final after = await repo.rangeList('2026-11-01', '2026-12-01');
    expect(after.length, 1);
    expect(after.first.isProfit, isFalse);
    expect(after.first.kind, 'fund');
  });
}
