import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// AI 配置（OpenAI 兼容接口）
class AiConfig {
  const AiConfig({
    this.baseUrl = defaultBaseUrl,
    this.apiKey = '',
    this.model = defaultModel,
  });

  static const defaultBaseUrl = 'https://api.openai.com/v1';
  static const defaultModel = 'gpt-4o-mini';

  final String baseUrl;
  final String apiKey;
  final String model;

  bool get isConfigured => apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 归一化 base url：去尾部斜杠，空则回退默认
  static String normalizeBaseUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return defaultBaseUrl;
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  AiConfig copyWith({String? baseUrl, String? apiKey, String? model}) =>
      AiConfig(
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

  String _friendlyError(http.Response resp) {
    String detail = '';
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
