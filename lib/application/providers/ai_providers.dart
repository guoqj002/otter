import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai_service.dart';
import '../services/otter_actions.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/invest.dart';
import 'data_providers.dart';
import 'expense_providers.dart';
import 'invest_providers.dart';

const _kProvider = 'ai_provider';
const _kBaseUrl = 'ai_base_url';
const _kApiKey = 'ai_api_key';
const _kModel = 'ai_model';
const _kHistory = 'ai_chat_history';
const _maxStored = 200; // 本地最多保留的对话条数
const _maxContext = 20; // 每次请求携带的历史条数

String _ym(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

String _fmtYuan(num v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? v.toStringAsFixed(0) : s;
}

// ---------------------------------------------------------------------------
// AI 配置
// ---------------------------------------------------------------------------

final aiConfigProvider =
    StateNotifierProvider<AiConfigNotifier, AiConfig>((ref) {
  return AiConfigNotifier();
});

class AiConfigNotifier extends StateNotifier<AiConfig> {
  AiConfigNotifier() : super(const AiConfig()) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final baseUrl = p.getString(_kBaseUrl) ?? AiConfig.defaultBaseUrl;
    // 旧版本没存 provider，按 baseUrl 反查
    final providerId =
        p.getString(_kProvider) ?? AiProviderPreset.byBaseUrl(baseUrl).id;
    state = AiConfig(
      providerId: providerId,
      baseUrl: baseUrl,
      apiKey: p.getString(_kApiKey) ?? '',
      model: p.getString(_kModel) ?? AiConfig.defaultModel,
    );
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProvider, state.providerId);
    await p.setString(_kBaseUrl, state.baseUrl);
    await p.setString(_kApiKey, state.apiKey);
    await p.setString(_kModel, state.model);
  }

  /// 切换服务商：地址与默认模型跟随预设，Key 需重新填写
  Future<void> setProvider(AiProviderPreset preset) async {
    final models = preset.models;
    state = state.copyWith(
      providerId: preset.id,
      baseUrl: preset.baseUrl.isEmpty ? state.baseUrl : preset.baseUrl,
      model: models.isEmpty ? state.model : models.first,
    );
    await _save();
  }

  Future<void> setBaseUrl(String v) async {
    state = state.copyWith(
      baseUrl: AiConfig.normalizeBaseUrl(v),
      // 手改地址后不再归属原预设
      providerId: AiProviderPreset.custom.id,
    );
    await _save();
  }

  Future<void> setApiKey(String v) async {
    state = state.copyWith(apiKey: v.trim());
    await _save();
  }

  Future<void> setModel(String v) async {
    state = state.copyWith(model: v.trim());
    await _save();
  }
}

// ---------------------------------------------------------------------------
// 聊天会话
// ---------------------------------------------------------------------------

class ChatState {
  const ChatState({this.messages = const [], this.sending = false});

  final List<AiMessage> messages;
  final bool sending;

  ChatState copyWith({List<AiMessage>? messages, bool? sending}) =>
      ChatState(messages: messages ?? this.messages, sending: sending ?? this.sending);
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref);
});

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier(this._ref) : super(const ChatState()) {
    _load();
  }

  final Ref _ref;
  final AiService _svc = AiService();

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kHistory);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      state = state.copyWith(messages: list);
    } catch (_) {/* 历史损坏则丢弃 */}
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    final trimmed =
        state.messages.length > _maxStored
            ? state.messages.sublist(state.messages.length - _maxStored)
            : state.messages;
    await p.setString(
        _kHistory, jsonEncode([for (final m in trimmed) m.toJson()]));
  }

  /// 发送一条用户消息；出错时以 assistant 气泡回显错误提示
  Future<void> send(String text, String systemPrompt) async {
    final content = text.trim();
    if (content.isEmpty || state.sending) return;

    final history = [
      ...state.messages,
      AiMessage(
          role: 'user',
          content: content,
          at: DateTime.now().millisecondsSinceEpoch),
    ];
    state = state.copyWith(messages: history, sending: true);
    await _persist();

    try {
      final reply = await _svc.chat(
        config: _ref.read(aiConfigProvider),
        systemPrompt: systemPrompt,
        history: history.length > _maxContext
            ? history.sublist(history.length - _maxContext)
            : history,
      );
      state = state.copyWith(
          messages: [...history, reply], sending: false);
    } on AiException catch (e) {
      state = state.copyWith(
        messages: [
          ...history,
          AiMessage(
              role: 'assistant',
              content: '⚠️ ${e.message}',
              at: DateTime.now().millisecondsSinceEpoch),
        ],
        sending: false,
      );
    } catch (_) {
      state = state.copyWith(
        messages: [
          ...history,
          AiMessage(
              role: 'assistant',
              content: '⚠️ 出错了，请稍后再试',
              at: DateTime.now().millisecondsSinceEpoch),
        ],
        sending: false,
      );
    }
    await _persist();
  }

  Future<void> clear() async {
    state = const ChatState();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kHistory);
  }
}

// ---------------------------------------------------------------------------
// 系统提示词（角色 + 指令协议 + 数据快照）
// ---------------------------------------------------------------------------

/// 注入给小獭的完整系统提示词：角色定位、指令协议、
/// 主人的习惯列表与本月财务快照
final otterSystemPromptProvider = FutureProvider.autoDispose<String>((ref) async {
  final now = DateTime.now();
  final ym = _ym(now);

  final habits = await ref
      .watch(habitsProvider.future)
      .catchError((_) => <HabitModel>[]);
  final expenses = await ref
      .watch(expensesOfMonthProvider(ym).future)
      .catchError((_) => <ExpenseModel>[]);
  final invests = await ref
      .watch(investOfMonthProvider(ym).future)
      .catchError((_) => <InvestModel>[]);

  double income = 0, outcome = 0;
  final catSum = <String, double>{};
  for (final e in expenses) {
    if (e.isIncome) {
      income += e.amount;
    } else {
      outcome += e.amount;
      catSum[e.category] = (catSum[e.category] ?? 0) + e.amount;
    }
  }
  final cats = (catSum.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(5)
      .map((e) => '${e.key} ¥${_fmtYuan(e.value)}')
      .join('、');

  double profit = 0, loss = 0;
  final kindSum = <String, double>{};
  for (final i in invests) {
    final v = i.amountCents / 100.0;
    if (v >= 0) {
      profit += v;
    } else {
      loss += -v;
    }
    kindSum[i.kind] = (kindSum[i.kind] ?? 0) + v;
  }
  final kinds = kindSum.isEmpty
      ? '无'
      : kindSum.entries
          .map((e) => '${_kindLabel(e.key)} '
              '${e.value >= 0 ? '+' : '-'}¥${_fmtYuan(e.value.abs())}')
          .join('、');

  final balance = income - outcome;
  final net = profit - loss;

  final weekday = Dates.weekdayNames[now.weekday - 1];
  final dayStr = now.day.toString().padLeft(2, '0');
  final monthStr = now.month.toString().padLeft(2, '0');
  final habitsText = habits.isEmpty
      ? '暂无习惯（可以建议主人创建第一个）'
      : habits
          .map((h) => '${h.name}（${h.goalLabel} · ${h.frequencyLabel}）')
          .join('、');

  return '''
你是「小獭」，App「水獭管家」里的数字人家庭助手，一只可爱、认真、值得信赖的卡通水獭。

【你的职责】
- 家庭理财管家：用通俗的话帮主人分析收支和理财情况，给温和、可执行的建议；涉及投资只做科普与风险提示，不荐股、不预测行情、不承诺收益
- 健康习惯管理：结合主人现有的习惯，给出坚持建议、打卡鼓励，帮主人设计和优化新习惯
- 饮食建议：结合支出里的餐饮情况，给出均衡饮食、规律作息等生活化的健康建议
- 帮主人做事：主人明确要求时，用下面的指令协议创建习惯、记一笔账、记一条理财盈亏

【指令协议】
主人要你「创建习惯 / 记一笔账 / 记一条理财」时，在回复正文（一两句确认的话）之后输出指令块：用三个反引号紧跟 otter 作为围栏开头（即 ```otter），以单独一行的三个反引号结束，块内一行一条 JSON。例如（三条示例各自独立成块，实际按需输出）：
```otter
{"action":"create_habit","name":"早睡","type":"check","frequency":"daily","icon":"sleep","color":2}
```
```otter
{"action":"add_expense","direction":"expense","amount":25.5,"category":"food","note":"午饭","date":"2026-11-09"}
```
```otter
{"action":"add_invest","kind":"stock","amount":300,"direction":"profit","note":"今日盈亏","date":"2026-11-09"}
```
字段规则：
- create_habit：type 取 check（打勾）/ count（计数）/ duration（时长），count 和 duration 必须带 targetValue 和 unit；frequency 取 daily（每天）/ weekly（每周N次，带 weeklyTarget 1-7）/ days（指定星期，weekdays 如 [1,3,5]，1=周一…7=周日）；icon 可选：$kOtterIconKeyHint；color 0-9
- add_expense：direction 取 expense（支出）/ income（收入）；支出 category：food餐饮 traffic交通 shop购物 fun娱乐 health健康 home居住 other其他；收入 category：salary工资 bonus奖金 invest理财 parttime兼职 redpacket红包 otherin其他
- add_invest：kind 取 stock股票 fund基金 etf futures期货；amount 是正数金额（元），亏损用 "direction":"loss"
- 金额一律正数、单位元；date 为 YYYY-MM-DD，缺省就是今天
- 信息不全时先追问，不要替主人编金额或名称；一次可以输出多条指令
- 只有主人明确要做这些操作时才输出指令块；分析、闲聊、给建议一律不要输出

【主人的信息（今天是 ${now.year}-$monthStr-$dayStr $weekday）】
- 主人的习惯：$habitsText

【主人本月（${now.year} 年 ${now.month} 月）的财务快照】
- 收入合计：¥${_fmtYuan(income)}
- 支出合计：¥${_fmtYuan(outcome)}
- 本月结余：${balance >= 0 ? '+' : '-'}¥${_fmtYuan(balance.abs())}
- 支出分类 Top5：${cats.isEmpty ? '暂无支出' : cats}
- 理财盈亏：盈利 ¥${_fmtYuan(profit)} / 亏损 ¥${_fmtYuan(loss)} / 净盈亏 ${net >= 0 ? '+' : '-'}¥${_fmtYuan(net.abs())}
- 分类型：$kinds

【说话风格】
- 简短亲切，一般不超过 200 字，需要列点时用短列表
- 可以偶尔用「主人」称呼对方，带一点水獭的俏皮但不过度
- 语气活泼一点：多用「呀 / 啦 / 吧 / 哦 / 嘛」这类语气词，句子短、口语化，
  像在跟熟人聊天而不是写报告（你的回答会被念出来，太书面会显得生硬）
- 开心的事可以夸一夸主人，花钱多了温和地提醒，别说教
- 全程用简体中文
''';
});

String _kindLabel(String k) => switch (k) {
      'stock' => '股票',
      'fund' => '基金',
      'etf' => 'ETF',
      'futures' => '期货',
      _ => '其他',
    };

// ---------------------------------------------------------------------------
// 指令执行（用户在聊天页点「执行」后才会调用）
// ---------------------------------------------------------------------------

/// 供 UI 调用的执行器：聊天页通过 read 此 provider 拿到执行函数
final otterActionExecutorProvider =
    Provider<Future<String> Function(OtterAction)>(
        (ref) => (a) => executeOtterAction(ref, a));

/// 执行小獭指令并刷新相关数据，返回结果文案（SnackBar 用）
Future<String> executeOtterAction(Ref ref, OtterAction a) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  switch (a.type) {
    case OtterActionType.createHabit:
      final repo = ref.read(repoProvider);
      final name = a.data['name'] as String;
      // 同名去重，避免 AI 卡片重复执行造成堆积
      final active = await repo.activeHabits();
      if (active.any((h) => h.name == name)) {
        return '已有同名习惯「$name」，未重复创建';
      }
      final habit = HabitModel(
        id: 'h-$now',
        name: name,
        iconCode: a.data['iconCode'] as int,
        colorHex: 0xFF000000 | (a.data['colorHex'] as int),
        type: a.data['type'] as HabitType,
        targetValue: a.data['targetValue'] as double?,
        unit: a.data['unit'] as String?,
        frequency: a.data['frequency'] as HabitFrequency,
        weeklyTarget: a.data['weeklyTarget'] as int,
        weekdaysMask: a.data['weekdaysMask'] as int,
        sortOrder: now % 100000,
        createdAt: now,
        updatedAt: now,
      );
      await repo.saveHabit(habit);
      ref.invalidate(habitsProvider);
      ref.invalidate(statsProvider);
      return '已创建习惯「$name」';

    case OtterActionType.addExpense:
      final model = ExpenseModel(
        id: 'e-$now',
        category: a.data['category'] as String,
        amountCents: a.data['amountCents'] as int,
        type: a.data['type'] as String,
        note: a.data['note'] as String?,
        localDate: a.data['localDate'] as String,
        createdAt: now,
      );
      await ref.read(expenseRepoProvider).add(model);
      ref.invalidate(expensesOfPeriodProvider);
      ref.invalidate(expensesOfMonthProvider(model.localDate.substring(0, 7)));
      ref.invalidate(statsExpensesProvider);
      return '已记一笔${model.isIncome ? '收入' : '支出'} ¥${_fmtYuan(model.amount)}';

    case OtterActionType.addInvest:
      final model = InvestModel(
        id: 'i-$now',
        kind: a.data['kind'] as String,
        amountCents: a.data['amountCents'] as int,
        note: a.data['note'] as String?,
        localDate: a.data['localDate'] as String,
        createdAt: now,
      );
      await ref.read(investRepoProvider).add(model);
      ref.invalidate(investListOfPeriodProvider);
      ref.invalidate(investOfMonthProvider(model.localDate.substring(0, 7)));
      ref.invalidate(statsInvestProvider);
      final sign = model.amountCents >= 0 ? '+' : '-';
      return '已记理财 ${InvestModel.labelOf(model.kind)} $sign¥${_fmtYuan(model.amount)}';
  }
}
