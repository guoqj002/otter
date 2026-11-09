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

  group('AiProviderPreset', () {
    test('byBaseUrl 能识别各服务商', () {
      expect(AiProviderPreset.byBaseUrl('https://api.deepseek.com/v1').id, 'deepseek');
      expect(AiProviderPreset.byBaseUrl('https://dashscope.aliyuncs.com/compatible-mode/v1').id, 'qwen');
      expect(AiProviderPreset.byBaseUrl('https://open.bigmodel.cn/api/paas/v4').id, 'zhipu');
      expect(AiProviderPreset.byBaseUrl('https://api.moonshot.cn/v1').id, 'moonshot');
      expect(AiProviderPreset.byBaseUrl('https://api.openai.com/v1').id, 'openai');
    });

    test('未知地址与空值回退自定义', () {
      expect(AiProviderPreset.byBaseUrl('https://my-proxy.example.com/v1').id, 'custom');
      expect(AiProviderPreset.byBaseUrl('').id, 'custom');
    });

    test('byId 未知 id 回退自定义', () {
      expect(AiProviderPreset.byId('deepseek').name, 'DeepSeek');
      expect(AiProviderPreset.byId('nope').id, 'custom');
    });

    test('每个预设有地址与至少一个推荐模型（自定义除外）', () {
      for (final p in AiProviderPreset.all) {
        if (p.id == 'custom') continue;
        expect(p.baseUrl, isNotEmpty, reason: p.id);
        expect(p.models, isNotEmpty, reason: p.id);
        expect(p.baseUrl.endsWith('/'), isFalse, reason: '${p.id} 不应带尾部斜杠');
      }
    });
  });
}
