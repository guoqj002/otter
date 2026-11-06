import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

part 'app_database.g.dart';

/// 习惯表
class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get iconCode => integer()();
  IntColumn get colorHex => integer()();
  TextColumn get type => text()(); // check | count | duration
  RealColumn get targetValue => real().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get frequency => text()(); // daily | weekly | days
  IntColumn get weeklyTarget => integer().withDefault(const Constant(7))();
  IntColumn get weekdaysMask => integer().withDefault(const Constant(127))();
  TextColumn get reminderTime => text().nullable()(); // HH:mm
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get archivedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 打卡记录表：同习惯同一天唯一
class CheckIns extends Table {
  TextColumn get id => text()();
  TextColumn get habitId =>
      text().references(Habits, #id, onDelete: KeyAction.cascade)();
  TextColumn get localDate => text()(); // YYYY-MM-DD
  IntColumn get doneAt => integer()(); // epoch ms UTC
  RealColumn get value => real().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {habitId, localDate},
      ];
}

/// 里程碑：用于庆祝动效去重
class Milestones extends Table {
  TextColumn get habitId => text()();
  TextColumn get kind => text()();
  IntColumn get achievedAt => integer()();

  @override
  Set<Column> get primaryKey => {habitId, kind};
}

/// 记账流水表：金额以"分"存储避免浮点误差
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get category => text()(); // food traffic shop fun health home other | salary bonus invest redpacket parttime otherin
  IntColumn get amountCents => integer()();
  TextColumn get type => text().withDefault(const Constant('expense'))(); // expense | income
  TextColumn get note => text().nullable()();
  TextColumn get localDate => text()(); // YYYY-MM-DD
  IntColumn get createdAt => integer()(); // epoch ms UTC

  @override
  Set<Column> get primaryKey => {id};
}

/// 理财记录表：股票 / 基金每日盈亏，amountCents 有符号（正=盈利，负=亏损）
class InvestRecords extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // stock | fund
  IntColumn get amountCents => integer()(); // 有符号
  TextColumn get note => text().nullable()();
  TextColumn get localDate => text()(); // YYYY-MM-DD
  IntColumn get createdAt => integer()(); // epoch ms UTC

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Habits, CheckIns, Milestones, Expenses, InvestRecords])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(expenses);
          }
          if (from < 3) {
            // 存量流水默认为支出
            await m.addColumn(expenses, expenses.type);
          }
          if (from < 4) {
            await m.createTable(investRecords);
          }
        },
        onCreate: (m) async {
          await m.createAll();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'fitstreak.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
