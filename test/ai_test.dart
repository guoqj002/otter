import 'package:flutter_test/flutter_test.dart';

import 'package:fitstreak/application/services/ai_service.dart';

void main() {
  group('AiConfig', () {
    test('normalizeBaseUrl 去尾斜杠、空值回退默认', () {
      expect(
        AiConfig.normalizeBaseUrl('https://api.deepseek.com/v1/'),
        'https://api.deepseek.com/v1',
      );
      expect(AiConfig.normalizeBaseUrl('  https://a.b/v1  '), 'https://a.b/v1');
      expect(AiConfig.normalizeBaseUrl(''), AiConfig.defaultBaseUrl);
      expect(AiConfig.normalizeBaseUrl('   '), AiConfig.defaultBaseUrl);
    });

    test('isConfigured 需要同时有 key 与 model', () {
      expect(const AiConfig(apiKey: 'sk-x', model: 'm').isConfigured, isTrue);
      expect(const AiConfig(apiKey: '', model: 'm').isConfigured, isFalse);
      expect(const AiConfig(apiKey: 'sk-x', model: '  ').isConfigured, isFalse);
    });

    test('copyWith 保留未指定字段', () {
      final c = const AiConfig(baseUrl: 'u', apiKey: 'k', model: 'm')
          .copyWith(apiKey: 'k2');
      expect(c.baseUrl, 'u');
      expect(c.apiKey, 'k2');
      expect(c.model, 'm');
    });
  });

  group('AiMessage', () {
    test('toJson/fromJson 往返一致', () {
      const m = AiMessage(role: 'assistant', content: '你好', at: 12345);
      final back = AiMessage.fromJson(m.toJson());
      expect(back.role, 'assistant');
      expect(back.content, '你好');
      expect(back.at, 12345);
    });

    test('fromJson 对脏数据兜底', () {
      final m = AiMessage.fromJson({});
      expect(m.role, 'user');
      expect(m.content, '');
      expect(m.at, 0);
    });
  });
}
