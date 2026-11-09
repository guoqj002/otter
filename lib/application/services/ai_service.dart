import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// AI 服务商预设（均为 OpenAI 兼容接口）
class AiProviderPreset {
  const AiProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.models = const [],
    this.hint = '',
  });

  final String id;
  final String name;
  final String baseUrl;
  final List<String> models;
  final String hint;

  /// 自定义服务商（手填地址与模型）
  static const custom = AiProviderPreset(
    id: 'custom',
    name: '自定义',
    baseUrl: '',
    hint: '手动填写任意 OpenAI 兼容接口',
  );

  static const all = <AiProviderPreset>[
    AiProviderPreset(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      models: ['deepseek-chat', 'deepseek-reasoner'],
    ),
    AiProviderPreset(
      id: 'qwen',
      name: '通义千问',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      models: ['qwen-plus', 'qwen-max', 'qwen-turbo', 'qwen-long'],
    ),
    AiProviderPreset(
      id: 'zhipu',
      name: '智谱 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      models: ['glm-4-plus', 'glm-4-flash', 'glm-4-air', 'glm-4-long'],
    ),
    AiProviderPreset(
      id: 'moonshot',
      name: 'Kimi（月之暗面）',
      baseUrl: 'https://api.moonshot.cn/v1',
      models: ['moonshot-v1-8k', 'moonshot-v1-32k', 'moonshot-v1-128k'],
    ),
    AiProviderPreset(
      id: 'openai',
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      models: ['gpt-4o-mini', 'gpt-4o', 'gpt-4.1-mini'],
    ),
    custom,
  ];

  static AiProviderPreset byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => custom);

  /// 根据 baseUrl 反查服务商（兼容未存 providerId 的旧配置）
  static AiProviderPreset byBaseUrl(String baseUrl) {
    final u = baseUrl.trim().toLowerCase();
    if (u.isEmpty) return custom;
    for (final p in all) {
      if (p.baseUrl.isNotEmpty && u.startsWith(p.baseUrl.toLowerCase())) {
        return p;
      }
    }
    return custom;
  }
}

/// AI 配置（OpenAI 兼容接口）
class AiConfig {
  const AiConfig({
    this.providerId = 'openai',
    this.baseUrl = defaultBaseUrl,
    this.apiKey = '',
    this.model = defaultModel,
  });

  static const defaultBaseUrl = 'https://api.openai.com/v1';
  static const defaultModel = 'gpt-4o-mini';

  final String providerId;
  final String baseUrl;
  final String apiKey;
  final String model;

  AiProviderPreset get provider => AiProviderPreset.byId(providerId);

  bool get isConfigured => apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 归一化 base url：去尾部斜杠，空则回退默认
  static String normalizeBaseUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return defaultBaseUrl;
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  AiConfig copyWith({
    String? providerId,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) =>
      AiConfig(
        providerId: providerId ?? this.providerId,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );
}

/// 对话消息（role: user | assistant）
class AiMessage {
  const AiMessage({
    required this.role,
    required this.content,
    required this.at,
  });

  final String role;
  final String content;
  final int at; // epoch ms

  Map<String, dynamic> toJson() => {'role': role, 'content': content, 'at': at};

  static AiMessage fromJson(Map<String, dynamic> j) => AiMessage(
        role: j['role'] as String? ?? 'user',
        content: j['content'] as String? ?? '',
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

/// AI 调用异常（message 为可直接展示的中文提示）
class AiException implements Exception {
  AiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// OpenAI 兼容 chat/completions 客户端（非流式）
class AiService {
  AiService({http.Client? client, this.timeout = const Duration(seconds: 60)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  Future<AiMessage> chat({
    required AiConfig config,
    required String systemPrompt,
    required List<AiMessage> history,
    int? maxTokens,
  }) async {
    final base = AiConfig.normalizeBaseUrl(config.baseUrl);
    final uri = Uri.parse('$base/chat/completions');

    final body = jsonEncode(<String, dynamic>{
      'model': config.model.trim(),
      'messages': <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
        for (final m in history)
          {'role': m.role, 'content': m.content},
      ],
      'temperature': 0.7,
      if (maxTokens != null) 'max_tokens': maxTokens,
    });

    final http.Response resp;
    try {
      resp = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey.trim()}',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiException('请求超时了，检查网络或换个接口地址再试试');
    } catch (_) {
      throw AiException('网络请求失败，请检查网络连接和接口地址');
    }

    if (resp.statusCode != 200) {
      throw AiException(_friendlyError(resp));
    }

    try {
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      final content =
          (choices?.firstOrNull as Map<String, dynamic>?)?['message']
              ?['content'] as String?;
      if (content == null || content.isEmpty) {
        throw AiException('模型返回了空回复');
      }
      return AiMessage(
        role: 'assistant',
        content: content.trim(),
        at: DateTime.now().millisecondsSinceEpoch,
      );
    } on AiException {
      rethrow;
    } catch (_) {
      throw AiException('返回数据解析失败，请确认接口为 OpenAI 兼容格式');
    }
  }

  /// 连通性测试：发一条极短请求，成功返回模型回复片段
  Future<String> testConnection({required AiConfig config}) async {
    final reply = await chat(
      config: config,
      systemPrompt: '你是连通性测试助手，只需极简回复。',
      history: [
        AiMessage(
          role: 'user',
          content: '只回复两个字：收到',
          at: DateTime.now().millisecondsSinceEpoch,
        ),
      ],
      maxTokens: 16,
    );
    return reply.content;
  }

  String _friendlyError(http.Response resp) {    String detail = '';
    try {
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final err = data['error'];
      if (err is Map) detail = (err['message'] ?? '').toString();
    } catch (_) {/* 忽略解析失败，用状态码兜底 */}

    return switch (resp.statusCode) {
      401 => 'API Key 无效或已过期（401）',
      403 => '没有权限访问该模型（403），检查 Key 权限或余额',
      404 => '接口地址或模型名不存在（404），检查配置',
      429 => '请求太频繁或额度不足（429）',
      >= 500 => '服务端繁忙（${resp.statusCode}），稍后再试',
      _ => '请求失败（${resp.statusCode}）${detail.isEmpty ? '' : '：$detail'}',
    };
  }
}
