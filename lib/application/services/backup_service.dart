import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/db/app_database.dart';

/// 数据备份 / 恢复服务
///
/// 导出为 JSON（含习惯、打卡、里程碑、记账、昵称等偏好），
/// 导入时整库替换。兼容 v1 导出格式（无记账 / 无偏好 / 打卡无 id）。
class BackupService {
  BackupService(this.db);

  final AppDatabase db;

  static const appTag = '水獭管家';
  static const currentVersion = 2;

  // ------------------------------------------------------------- 导出

  /// 构建导出 payload
  Future<Map<String, dynamic>> buildPayload() async {
    final habits = await db.select(db.habits).get();
    final checkIns = await db.select(db.checkIns).get();
    final milestones = await db.select(db.milestones).get();
    final expenses = await db.select(db.expenses).get();
    final investRecords = await db.select(db.investRecords).get();
    final prefs = await SharedPreferences.getInstance();

    return {
      'app': appTag,
      'version': currentVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': {
        'nickname': prefs.getString('nickname') ?? '',
        'themeMode': prefs.getString('theme_mode') ?? 'system',
        'allowBackfill': prefs.getBool('allow_backfill') ?? false,
      },
      'habits': [for (final r in habits) r.toJson()],
      'checkIns': [for (final r in checkIns) r.toJson()],
      'milestones': [for (final r in milestones) r.toJson()],
      'expenses': [for (final r in expenses) r.toJson()],
      'investRecords': [for (final r in investRecords) r.toJson()],
    };
  }

  /// 导出 JSON 到临时目录，返回文件（供分享面板发送）
  Future<File> writeExportFile() async {
    final payload = await buildPayload();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(RegExp(r'[-:T]'), '');
    final file = File('${dir.path}/水獭管家-backup-$stamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file;
  }

  // ------------------------------------------------------------- 导入

  /// 校验并统计文件内容（不写库），用于导入前确认
  Future<BackupSummary> inspect(String path) async {
    final map = await _readPayload(path);
    final version = (map['version'] as num?)?.toInt() ?? 1;
    return BackupSummary(
      version: version,
      exportedAt: (map['exportedAt'] as String?) ?? '',
      habits: (map['habits'] as List?)?.length ?? 0,
      checkIns: (map['checkIns'] as List?)?.length ?? 0,
      expenses: (map['expenses'] as List?)?.length ?? 0,
      investRecords: (map['investRecords'] as List?)?.length ?? 0,
      nickname: ((map['settings'] as Map?)?['nickname'] as String?) ?? '',
    );
  }

  /// 整库替换导入。返回导入统计。
  Future<BackupSummary> importFrom(String path) async {
    final map = await _readPayload(path);

    final habitRows = [
      for (final m in _list(map['habits'])) Habit.fromJson(_normHabit(m))
    ];
    final checkInRows = [
      for (final m in _list(map['checkIns'])) CheckIn.fromJson(_normCheckIn(m))
    ];
    final milestoneRows = [
      for (final m in _list(map['milestones'])) Milestone.fromJson(m)
    ];
    final expenseRows = [
      for (final m in _list(map['expenses'])) Expense.fromJson(_normExpense(m))
    ];
    final investRows = [
      for (final m in _list(map['investRecords']))
        InvestRecord.fromJson(_normInvest(m))
    ];

    final settingsMap = (map['settings'] as Map?) ?? const {};
    final nickname = (settingsMap['nickname'] as String?)?.trim() ?? '';

    await db.transaction(() async {
      // 先删子表再删父表（外键约束）
      await db.delete(db.checkIns).go();
      await db.delete(db.milestones).go();
      await db.delete(db.expenses).go();
      await db.delete(db.investRecords).go();
      await db.delete(db.habits).go();

      await db.batch((b) {
        b.insertAll(db.habits, habitRows, mode: InsertMode.insertOrReplace);
        b.insertAll(db.checkIns, checkInRows, mode: InsertMode.insertOrReplace);
        if (milestoneRows.isNotEmpty) {
          b.insertAll(db.milestones, milestoneRows,
              mode: InsertMode.insertOrReplace);
        }
        if (expenseRows.isNotEmpty) {
          b.insertAll(db.expenses, expenseRows,
              mode: InsertMode.insertOrReplace);
        }
        if (investRows.isNotEmpty) {
          b.insertAll(db.investRecords, investRows,
              mode: InsertMode.insertOrReplace);
        }
      });
    });

    // 恢复偏好（不覆盖 onboarded，避免导入后被踢回引导页）
    if (nickname.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nickname', nickname);
    }

    return BackupSummary(
      version: (map['version'] as num?)?.toInt() ?? 1,
      exportedAt: (map['exportedAt'] as String?) ?? '',
      habits: habitRows.length,
      checkIns: checkInRows.length,
      expenses: expenseRows.length,
      investRecords: investRows.length,
      nickname: nickname,
    );
  }

  // ------------------------------------------------------------- 内部

  Future<Map<String, dynamic>> _readPayload(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const FormatException('文件不存在');
    }
    final raw = await file.readAsString();
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('不是有效的 JSON 文件');
    }
    final map = decoded;
    if (map is! Map<String, dynamic>) {
      throw const FormatException('文件格式不正确');
    }
    final app = (map['app'] as String?) ?? '';
    if (app != appTag && app != 'FitStreak' && app != 'fitstreak') {
      throw const FormatException('不是水獭管家的备份文件');
    }
    final version = (map['version'] as num?)?.toInt() ?? 1;
    if (version > currentVersion) {
      throw const FormatException('备份文件来自更新版本的 App，请先升级后再导入');
    }
    return map;
  }

  List<Map<String, dynamic>> _list(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw) if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  /// 习惯行标准化：兼容 v1（缺 iconCode/colorHex 等）
  Map<String, dynamic> _normHabit(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m);
    // v1 用 archived: bool，v2 用 archivedAt
    if (!out.containsKey('archivedAt') && out['archived'] is bool) {
      out['archivedAt'] =
          out['archived'] == true ? DateTime.now().millisecondsSinceEpoch : null;
    }
    out['iconCode'] = out['iconCode'] ?? 0x1F525;
    out['colorHex'] = out['colorHex'] ?? 0xFFDD8A4E;
    out['type'] = out['type'] ?? 'check';
    out['frequency'] = out['frequency'] ?? 'daily';
    out['weeklyTarget'] = out['weeklyTarget'] ?? 7;
    out['weekdaysMask'] = out['weekdaysMask'] ?? 127;
    out['sortOrder'] = out['sortOrder'] ?? 0;
    out['createdAt'] = out['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;
    out['updatedAt'] = out['updatedAt'] ?? out['createdAt'];
    return out;
  }

  /// 打卡行标准化：v1 无 id，需生成
  Map<String, dynamic> _normCheckIn(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m);
    if (out['id'] == null || (out['id'] as String).isEmpty) {
      out['id'] = 'ci-${out['habitId']}-${out['localDate']}-${m.hashCode.abs()}';
    }
    out['deletedAt'] = out['deletedAt'];
    return out;
  }

  /// 记账行标准化：v1 无 type 字段
  Map<String, dynamic> _normExpense(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m);
    out['type'] = out['type'] ?? 'expense';
    return out;
  }

  /// 理财行标准化：老备份无理财数据（调用方直接跳过）
  Map<String, dynamic> _normInvest(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m);
    out['kind'] = out['kind'] ?? 'stock';
    return out;
  }
}

/// 备份内容摘要（确认弹窗 / 完成提示用）
class BackupSummary {
  const BackupSummary({
    required this.version,
    required this.exportedAt,
    required this.habits,
    required this.checkIns,
    required this.expenses,
    this.investRecords = 0,
    required this.nickname,
  });

  final int version;
  final String exportedAt;
  final int habits;
  final int checkIns;
  final int expenses;
  final int investRecords;
  final String nickname;
}
