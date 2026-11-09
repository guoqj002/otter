import 'dart:convert';

import '../../core/utils/date_utils.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/invest.dart';
import '../../presentation/widgets/habit_icon_art.dart';

/// 「小獭」指令协议
///
/// AI 在回复里用 ```otter 围栏输出一行或多行 JSON 指令，
/// App 解析成待确认的 [OtterAction] 卡片，用户点「执行」才真正写库。
/// 三类指令：创建习惯 / 记一笔账 / 记一条理财盈亏。
class OtterAction {
  const OtterAction._(this.type, this.data, this.summary);

  final OtterActionType type;

  /// 规范化后的字段（执行时使用）
  final Map<String, dynamic> data;

  /// 确认卡片上的一行描述
  final String summary;

  // ------------------------------------------------------------ 解析

  /// 从 AI 回复中提取全部指令（忽略无法解析的块）
  static List<OtterAction> parse(String reply) {
    final actions = <OtterAction>[];
    final blockRe = RegExp(r'```otter\s*([\s\S]*?)```', multiLine: false);
    for (final m in blockRe.allMatches(reply)) {
      final body = m.group(1)?.trim() ?? '';
      if (body.isEmpty) continue;
      for (final obj in _jsonObjects(body)) {
        final a = _fromJson(obj);
        if (a != null) actions.add(a);
      }
    }
    return actions;
  }

  /// 去掉回复中的指令块，只留正文
  static String stripBlocks(String reply) =>
      reply.replaceAll(blockReSrc, '').trim();

  static final RegExp blockReSrc =
      RegExp(r'```otter\s*[\s\S]*?```', multiLine: false);

  /// 提取块内的 JSON 对象：整块是一个 → 直接用；
  /// 否则逐行尝试（一行一条 JSON）
  static Iterable<Map<String, dynamic>> _jsonObjects(String body) sync* {
    final decoded = _tryDecode(body);
    if (decoded is Map<String, dynamic>) {
      yield decoded;
      return;
    }
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (!t.startsWith('{')) continue;
      final d = _tryDecode(t);
      if (d is Map<String, dynamic>) yield d;
    }
  }

  static Object? _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  // ------------------------------------------------------------ 规范化

  static OtterAction? _fromJson(Map<String, dynamic> m) {
    switch (m['action']) {
      case 'create_habit':
        return _habit(m);
      case 'add_expense':
        return _expense(m);
      case 'add_invest':
        return _invest(m);
    }
    return null;
  }

  static OtterAction? _habit(Map<String, dynamic> m) {
    final name = (m['name'] as String?)?.trim() ?? '';
    if (name.isEmpty || name.length > 20) return null;

    final typeStr = (m['type'] as String?) ?? 'check';
    final type = switch (typeStr) {
      'count' => HabitType.count,
      'duration' => HabitType.duration,
      _ => HabitType.check,
    };

    double? target;
    String? unit;
    if (type != HabitType.check) {
      final t0 = _num(m['targetValue']);
      target = t0?.toDouble();
      unit = ((m['unit'] as String?) ?? '').trim();
      // 缺省兜底：计数 30 个 / 时长 20 分钟
      if (target == null || target <= 0) {
        target = type == HabitType.count ? 30 : 20;
      }
      if (unit.isEmpty || unit.length > 4) {
        unit = type == HabitType.count ? '个' : '分钟';
      }
    }

    final freqStr = (m['frequency'] as String?) ?? 'daily';
    final frequency = switch (freqStr) {
      'weekly' => HabitFrequency.weekly,
      'days' => HabitFrequency.days,
      _ => HabitFrequency.daily,
    };

    var weeklyTarget = (_num(m['weeklyTarget']) ?? 3).round();
    if (weeklyTarget < 1 || weeklyTarget > 7) weeklyTarget = 3;

    var mask = 0;
    final days = m['weekdays'];
    if (days is List) {
      for (final d in days) {
        final n = _num(d)?.round() ?? 0;
        if (n >= 1 && n <= 7) mask |= 1 << (n - 1);
      }
    }
    if (mask == 0) mask = 127;

    final iconKey = (m['icon'] as String?)?.trim() ?? '';
    final iconCode = kOtterIconKeys[iconKey] ?? guessIconCode(name);

    var color = (_num(m['color']) ?? 0).round();
    if (color < 0 || color > 9) color = 0;

    final goal = switch (type) {
      HabitType.check => '完成即可',
      _ => '目标 ${_fmtNum(target!)}$unit',
    };
    final freqLabel = switch (frequency) {
      HabitFrequency.daily => '每天',
      HabitFrequency.weekly => '每周 $weeklyTarget 次',
      HabitFrequency.days => '周 ${[
        for (var i = 0; i < 7; i++)
          if ((mask >> i) & 1 == 1) Dates.weekdayNames[i]
      ].join(' ')}',
    };

    return OtterAction._(
      OtterActionType.createHabit,
      {
        'name': name,
        'type': type,
        'targetValue': target,
        'unit': unit,
        'frequency': frequency,
        'weeklyTarget': weeklyTarget,
        'weekdaysMask': mask,
        'iconCode': iconCode,
        'colorHex': color,
      },
      '创建习惯「$name」· $goal · $freqLabel',
    );
  }

  static OtterAction? _expense(Map<String, dynamic> m) {
    final amount = _num(m['amount']);
    if (amount == null || amount <= 0 || amount >= 10000000) return null;

    final income = (m['direction'] as String?) == 'income';
    final type = income ? ExpenseModel.typeIncome : ExpenseModel.typeExpense;
    final validCodes = _expenseCodes(income);
    var category = ((m['category'] as String?) ?? '').trim();
    if (!validCodes.contains(category)) {
      category = income ? 'otherin' : 'other';
    }
    final note = ((m['note'] as String?) ?? '').trim();
    final date = _dateOf(m['date']);
    final catLabel = income ? _incomeLabel(category) : _expenseLabel(category);

    return OtterAction._(
      OtterActionType.addExpense,
      {
        'type': type,
        'category': category,
        'amountCents': (amount * 100).round(),
        'note': note.isEmpty ? null : note,
        'localDate': date,
      },
      '${income ? '收入' : '支出'} ¥${_fmtNum(amount)} · $catLabel'
      '${note.isEmpty ? '' : ' · $note'} · $date',
    );
  }

  static OtterAction? _invest(Map<String, dynamic> m) {
    final amount = _num(m['amount']);
    if (amount == null || amount <= 0 || amount >= 10000000) return null;

    final loss = (m['direction'] as String?) == 'loss';
    var kind = ((m['kind'] as String?) ?? '').trim();
    if (!InvestModel.kinds.contains(kind)) kind = InvestModel.kindStock;
    final note = ((m['note'] as String?) ?? '').trim();
    final date = _dateOf(m['date']);

    return OtterAction._(
      OtterActionType.addInvest,
      {
        'kind': kind,
        'amountCents': loss ? -(amount * 100).round() : (amount * 100).round(),
        'note': note.isEmpty ? null : note,
        'localDate': date,
      },
      '理财：${InvestModel.labelOf(kind)} ${loss ? '-' : '+'}¥${_fmtNum(amount)} · $date',
    );
  }

  // ------------------------------------------------------------ 工具

  static num? _num(Object? v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim());
    return null;
  }

  static String _fmtNum(num v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? v.toStringAsFixed(0) : s;
  }

  /// 日期字段：YYYY-MM-DD 或 今天 → 合法日期串，非法回退今天
  static String _dateOf(Object? v) {
    final today = Dates.todayStr();
    final s = (v as String?)?.trim() ?? '';
    if (s.isEmpty || s == 'today' || s == '今天') return today;
    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!re.hasMatch(s)) return today;
    final p = Dates.parse(s);
    // 排除 2026-13-99 这类溢出日期（DateTime 会静默进位）
    return Dates.fmt(p) == s ? s : today;
  }

  static const _expenseIn = [
    'food', 'traffic', 'shop', 'fun', 'health', 'home', 'other',
  ];
  static const _incomeIn = [
    'salary', 'bonus', 'invest', 'parttime', 'redpacket', 'otherin',
  ];

  static List<String> _expenseCodes(bool income) =>
      income ? _incomeIn : _expenseIn;

  static String _expenseLabel(String code) => switch (code) {
        'food' => '餐饮',
        'traffic' => '交通',
        'shop' => '购物',
        'fun' => '娱乐',
        'health' => '健康',
        'home' => '居住',
        _ => '其他',
      };

  static String _incomeLabel(String code) => switch (code) {
        'salary' => '工资',
        'bonus' => '奖金',
        'invest' => '理财',
        'parttime' => '兼职',
        'redpacket' => '红包',
        _ => '其他',
      };
}

enum OtterActionType { createHabit, addExpense, addInvest }

/// icon key → 习惯图标码点（供系统提示词与解析共用）
final Map<String, int> kOtterIconKeys = {
  'strength': kHabitIconCodes[0],
  'run': kHabitIconCodes[1],
  'swim': kHabitIconCodes[2],
  'yoga': kHabitIconCodes[3],
  'bike': kHabitIconCodes[4],
  'hike': kHabitIconCodes[5],
  'jumprope': kHabitIconCodes[6],
  'water': kHabitIconCodes[7],
  'sleep': kHabitIconCodes[8],
  'eat': kHabitIconCodes[9],
  'stretch': kHabitIconCodes[10],
  'ball': kHabitIconCodes[11],
  'read': kHabitIconCodes[12],
  'pushup': kHabitIconCodes[13],
};

/// 按习惯名称猜一个合适的图标（AI 没给 icon 时兜底）
int guessIconCode(String name) {
  final rules = <String, List<String>>{
    'water': ['喝水', '饮水', '八杯'],
    'run': ['跑步', '慢跑', '晨跑'],
    'sleep': ['早睡', '睡眠', '作息'],
    'read': ['读书', '阅读', '看书'],
    'eat': ['饮食', '吃', '三餐', '轻食'],
    'swim': ['游泳'],
    'yoga': ['瑜伽', '冥想', '呼吸'],
    'bike': ['骑行', '骑车', '单车'],
    'hike': ['徒步', '爬山', '爬楼', '散步', '走路', '步数'],
    'jumprope': ['跳绳', '有氧', '操'],
    'stretch': ['拉伸', '伸展'],
    'ball': ['篮球', '足球', '羽毛球', '网球', '球'],
    'pushup': ['俯卧撑', '平板支撑'],
    'strength': ['力量', '哑铃', '撸铁', '健身', '锻炼'],
  };
  for (final e in rules.entries) {
    for (final kw in e.value) {
      if (name.contains(kw)) return kOtterIconKeys[e.key]!;
    }
  }
  return kHabitIconCodes.first;
}

/// 系统提示词里的 icon / color 取值说明（与解析保持一致）
const kOtterIconKeyHint = 'strength run swim yoga bike hike jumprope '
    'water sleep eat stretch ball read pushup';
