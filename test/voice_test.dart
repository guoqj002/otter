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

  group('OtterVoice 音色', () {
    test('四档音色 id 唯一、文案齐全', () {
      final ids = OtterVoice.all.map((v) => v.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final v in OtterVoice.all) {
        expect(v.label, isNotEmpty);
        expect(v.desc, isNotEmpty);
      }
    });

    test('默认音色是萌系小獭', () {
      expect(OtterVoice.byId(null), OtterVoice.cute);
      expect(OtterVoice.byId('unknown'), OtterVoice.cute);
      expect(OtterVoice.byId('cute'), OtterVoice.cute);
    });

    test('可爱音色音高明显高于系统默认，且在失真阈值内', () {
      for (final v in [OtterVoice.cute, OtterVoice.playful, OtterVoice.soft]) {
        expect(v.pitch, greaterThan(1.3), reason: '${v.id} 音高不够，听不出童声感');
        expect(v.pitch, lessThanOrEqualTo(1.8), reason: '${v.id} 音高过高会失真');
        expect(v.rate, inInclusiveRange(0.4, 0.6), reason: '${v.id} 语速超出可听范围');
      }
      expect(OtterVoice.natural.pitch, 1.0);
      expect(OtterVoice.natural.rate, 0.5);
    });

    test('活泼档比萌系档更高更快', () {
      expect(OtterVoice.playful.pitch, greaterThan(OtterVoice.cute.pitch));
      expect(OtterVoice.playful.rate, greaterThan(OtterVoice.cute.rate));
    });

    test('软萌童声比萌系慢，且带童声语音包偏好', () {
      expect(OtterVoice.soft.rate, lessThan(OtterVoice.cute.rate));
      expect(OtterVoice.soft.voiceHints.first, 'child');
      expect(OtterVoice.natural.voiceHints, isEmpty);
    });

    test('蜡笔小新档：比软萌童声更慢，音高在失真阈值内', () {
      expect(OtterVoice.shinchan.rate, lessThan(OtterVoice.soft.rate));
      expect(OtterVoice.shinchan.pitch, inInclusiveRange(1.3, 1.8));
      expect(OtterVoice.shinchan.voiceHints.first, 'child');
    });

    test('试听示例句本身不带指令块 / Markdown', () {
      final out = ttsClean(VoiceService.previewText);
      expect(out, isNotEmpty);
      expect(out.contains('```'), isFalse);
      expect(out.contains('*'), isFalse);
    });
  });
}
