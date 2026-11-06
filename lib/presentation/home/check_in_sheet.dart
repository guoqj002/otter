import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/habit.dart';
import '../widgets/habit_icon_art.dart';

/// 数值 / 时长类型打卡输入弹层
class CheckInSheet extends StatefulWidget {
  const CheckInSheet({super.key, required this.habit, this.initialValue});

  final HabitModel habit;
  final double? initialValue;

  @override
  State<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<CheckInSheet> {
  late final TextEditingController _controller;

  double get _target => widget.habit.targetValue ?? 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _fmt(widget.initialValue ?? _target),
    );
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final color = Color(habit.colorHex);
    final scheme = Theme.of(context).colorScheme;
    final isDuration = habit.type == HabitType.duration;

    // 快捷值：目标的一半 / 目标 / 1.5 倍 / 2 倍
    final quick = [_target * 0.5, _target, _target * 1.5, _target * 2];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: HabitIconArtImage(code: habit.iconCode, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(habit.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(habit.goalLabel,
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      fontFeatures: [FontFeature.tabularFigures()]),
                  decoration: InputDecoration(
                    labelText: isDuration ? '完成时长' : '完成数量',
                    suffixText: habit.unit,
                    suffixStyle: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final q in quick.toSet())
                ActionChip(
                  label: Text('${_fmt(q)}${habit.unit ?? ''}'),
                  onPressed: () {
                    setState(() => _controller.text = _fmt(q));
                  },
                ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: () {
                final v = double.tryParse(_controller.text.trim());
                if (v == null || v <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入有效的数值')),
                  );
                  return;
                }
                Navigator.of(context).pop(v);
              },
              child: const Text('完成打卡'),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// 里程碑庆祝弹窗
Future<void> showMilestoneDialog(BuildContext context, String kind, HabitModel habit) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_fire_department_rounded,
                  size: 44, color: AppColors.warning),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            milestoneTitle(kind),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '"${habit.name}" ${milestoneDesc(kind)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('继续加油'),
          ),
        ),
      ],
    ),
  );
}

String milestoneTitle(String kind) {
  switch (kind) {
    case 'streak_3':
      return '连续 3 天 🌱';
    case 'streak_7':
      return '连续一周 🔥';
    case 'streak_30':
      return '连续 30 天 🏆';
    case 'streak_100':
      return '连续 100 天 💎';
    case 'total_10':
      return '累计 10 次 👏';
    case 'total_100':
      return '累计 100 次 🎉';
    default:
      return '达成里程碑';
  }
}

String milestoneDesc(String kind) {
  switch (kind) {
    case 'streak_3':
      return '已经连续 3 天了，习惯正在形成。';
    case 'streak_7':
      return '整整一周没断，这就是坚持的样子。';
    case 'streak_30':
      return '一个月不间断，你已经超过了大多数人。';
    case 'streak_100':
      return '一百天，这是传说级别的自律。';
    case 'total_10':
      return '累计完成 10 次，开头最难的部分已经过去了。';
    case 'total_100':
      return '累计完成 100 次，回头看会很惊讶。';
    default:
      return '继续保持。';
  }
}
