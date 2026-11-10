import 'package:flutter_test/flutter_test.dart';
import 'package:fitstreak/application/services/voice_service.dart';

void main() {
  group('ttsClean', () {
    test('去掉 otter 指令块，只念正文', () {
      const raw = '''
好的，主人～已经帮你记好了。
```otter
{"action":"add_expense","amount":25,"category":"food"}
```
''';
      final out = ttsClean(raw);
      expect(out.contains('otter'), isFalse);
      expect(out.contains('action'), isFalse);
      expect(out, contains('已经帮你记好了'));
    });

    test('去掉 Markdown 标记与列表符号', () {
      const raw = '## 本月小结\n- **收入** ¥3000\n- *支出* ¥1200\n> 结余为正';
      final out = ttsClean(raw);
      expect(out.contains('#'), isFalse);
      expect(out.contains('*'), isFalse);
      expect(out.contains('>'), isFalse);
      expect(out, contains('本月小结'));
      expect(out, contains('收入'));
    });

    test('emoji 不念出来', () {
      const raw = '主人好呀 🦦 这个月表现很棒 👍🏻';
      final out = ttsClean(raw);
      expect(out, contains('主人好呀'));
      expect(out, contains('表现很棒'));
      expect(out.runes.any((r) => r >= 0x1F000), isFalse);
    });

    test('链接只保留文字', () {
      const raw = '可以看看[这份说明](https://example.com/a)';
      final out = ttsClean(raw);
      expect(out, contains('这份说明'));
      expect(out.contains('example.com'), isFalse);
    });

    test('多余空白合并、首尾修剪', () {
      const raw = '  第一行\n\n  第二行   ';
      expect(ttsClean(raw), '第一行 第二行');
    });

    test('纯指令/空白返回空串', () {
      expect(ttsClean('```otter\n{"action":"add_invest","amount":10}\n```'),
          isEmpty);
      expect(ttsClean('   \n '), isEmpty);
    });
  });
}
