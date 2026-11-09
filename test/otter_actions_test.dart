import 'package:flutter_test/flutter_test.dart';
import 'package:fitstreak/application/services/otter_actions.dart';
import 'package:fitstreak/domain/entities/habit.dart';

void main() {
  group('OtterAction.parse', () {
    test('普通回复无指令时返回空', () {
      expect(OtterAction.parse('这个月支出 ¥1200，结余为正，很棒哦～'), isEmpty);
    });

    test('单个 create_habit 指令', () {
      const reply = '''
好的主人，这就帮你建好～
```otter
{"action":"create_habit","name":"早睡","type":"check","frequency":"daily","icon":"sleep","color":2}
```
''';
      final actions = OtterAction.parse(reply);
      expect(actions.length, 1);
      final a = actions.first;
      expect(a.type, OtterActionType.createHabit);
      expect(a.data['name'], '早睡');
      expect(a.data['type'], HabitType.check);
      expect(a.data['frequency'], HabitFrequency.daily);
      expect(a.data['iconCode'], OtterAction.parse(reply).first.data['iconCode']);
      expect(a.data['colorHex'], 2);
      expect(a.summary, contains('早睡'));
      expect(a.summary, contains('每天'));
    });

    test('count/duration 补齐 targetValue 与 unit', () {
      const reply = '''
```otter
{"action":"create_habit","name":"俯卧撑","type":"count"}
{"action":"create_habit","name":"冥想","type":"duration","targetValue":15}
```
''';
      final actions = OtterAction.parse(reply);
      expect(actions.length, 2);
      expect(actions[0].data['type'], HabitType.count);
      expect(actions[0].data['targetValue'], 30);
      expect(actions[0].data['unit'], '个');
      expect(actions[1].data['targetValue'], 15);
      expect(actions[1].data['unit'], '分钟');
    });

    test('weekly / days 频率', () {
      const reply = '''
```otter
{"action":"create_habit","name":"跑步","type":"check","frequency":"weekly","weeklyTarget":3,"icon":"run"}
{"action":"create_habit","name":"拉伸","type":"check","frequency":"days","weekdays":[1,3,5]}
```
''';
      final actions = OtterAction.parse(reply);
      expect(actions[0].data['frequency'], HabitFrequency.weekly);
      expect(actions[0].data['weeklyTarget'], 3);
      expect(actions[1].data['weekdaysMask'], 21);
      expect(actions[1].summary, contains('周 一'));
      expect(actions[1].summary, contains('五'));
    });

    test('add_expense：金额转分、分类校验、日期兜底', () {
      const reply = '''
```otter
{"action":"add_expense","direction":"expense","amount":25.5,"category":"food","note":"午饭"}
```
''';
      final actions = OtterAction.parse(reply);
      expect(actions.length, 1);
      final a = actions.first;
      expect(a.type, OtterActionType.addExpense);
      expect(a.data['amountCents'], 2550);
      expect(a.data['type'], 'expense');
      expect(a.data['category'], 'food');
      expect(a.data['note'], '午饭');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(a.data['localDate'] as String), isTrue);
      expect(a.summary, contains('¥25.5'));
      expect(a.summary, contains('餐饮'));
    });

    test('add_expense 收入与非法分类兜底', () {
      const reply = '''
```otter
{"action":"add_expense","direction":"income","amount":3000,"category":"xxx","note":"工资"}
```
''';
      final a = OtterAction.parse(reply).first;
      expect(a.data['type'], 'income');
      expect(a.data['category'], 'otherin');
    });

    test('add_invest：亏损取负', () {
      const reply = '''
```otter
{"action":"add_invest","kind":"stock","amount":300,"direction":"loss","date":"2026-11-08"}
```
''';
      final a = OtterAction.parse(reply).first;
      expect(a.type, OtterActionType.addInvest);
      expect(a.data['amountCents'], -30000);
      expect(a.data['localDate'], '2026-11-08');
      expect(a.summary, contains('股票'));
      expect(a.summary, contains('-¥300'));
    });

    test('add_invest：非法 kind 兜底为股票', () {
      const reply = '''
```otter
{"action":"add_invest","kind":"btc","amount":100}
```
''';
      final a = OtterAction.parse(reply).first;
      expect(a.data['kind'], 'stock');
    });

    test('一行一条 JSON 的多指令块', () {
      const reply = '''
```otter
{"action":"add_expense","direction":"expense","amount":12,"category":"traffic"}
{"action":"add_invest","kind":"etf","amount":500}
```
''';
      final actions = OtterAction.parse(reply);
      expect(actions.length, 2);
      expect(actions[0].type, OtterActionType.addExpense);
      expect(actions[1].type, OtterActionType.addInvest);
    });

    test('非法指令被忽略（缺金额 / 缺名称 / 未知 action）', () {
      const reply = '''
```otter
{"action":"add_expense","amount":0}
{"action":"create_habit","name":""}
{"action":"delete_everything"}
{"action":"add_expense","amount":"abc"}
```
''';
      expect(OtterAction.parse(reply), isEmpty);
    });

    test('溢出日期回退今天', () {
      const reply = '''
```otter
{"action":"add_expense","amount":10,"date":"2026-13-99"}
```
''';
      final a = OtterAction.parse(reply).first;
      expect(a.data['localDate'], isNot('2026-13-99'));
    });
  });

  group('OtterAction.stripBlocks', () {
    test('剔除指令块保留正文', () {
      const reply = '''
好的，主人～已经记好了：
```otter
{"action":"add_expense","amount":25,"category":"food"}
```
还有什么要记的吗？
''';
      expect(OtterAction.stripBlocks(reply).contains('```'), isFalse);
      expect(OtterAction.stripBlocks(reply), contains('已经记好了'));
      expect(OtterAction.stripBlocks(reply), contains('还有什么'));
    });

    test('纯指令回复正文为空', () {
      const reply = '```otter\n{"action":"add_invest","amount":10}\n```';
      expect(OtterAction.stripBlocks(reply), isEmpty);
    });
  });

  group('guessIconCode', () {
    test('按名称关键词匹配', () {
      expect(guessIconCode('每天喝八杯水'), guessIconCode('喝水'));
      expect(guessIconCode('晨跑 30 分钟'), guessIconCode('跑步'));
      expect(guessIconCode('睡前阅读'), guessIconCode('读书'));
    });

    test('无匹配时回退第一个图标', () {
      expect(guessIconCode('神秘习惯'), isNonZero);
    });
  });
}
