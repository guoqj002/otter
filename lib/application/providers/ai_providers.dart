import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai_service.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/invest.dart';
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
// 财务上下文（系统提示词）
// ---------------------------------------------------------------------------

/// 读取本月记账 + 理财数据，生成注入给小獭的财务快照
final otterSystemPromptProvider = FutureProvider.autoDispose<String>((ref) async {
  final now = DateTime.now();
  final ym = _ym(now);

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

  return '''
你是「小獭」，App「水獭管家」里的数字人家庭理财管家，一只可爱、认真、值得信赖的卡通水獭。

【你的职责】
- 用通俗的话帮主人分析收支和理财情况，给出温和、可执行的建议
- 涉及投资时只做科普与风险提示，不荐股、不预测行情、不承诺收益
- 你只能看到下面的数据快照，不能修改任何数据；如果主人问的问题超出数据范围，如实说明
- 金额一律用 ¥，口径与 App 一致：结余为正说明收大于支

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
