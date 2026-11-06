import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers/data_providers.dart';
import '../../core/notification/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/habit.dart';
import '../widgets/habit_icon_art.dart';
import '../widgets/common.dart';

/// 新建 / 编辑习惯（同一页，habitId 为空即新建）
class HabitEditPage extends ConsumerStatefulWidget {
  const HabitEditPage({super.key, this.habitId, this.preset});

  final String? habitId;
  final HabitModel? preset;

  @override
  ConsumerState<HabitEditPage> createState() => _HabitEditPageState();
}

class _HabitEditPageState extends ConsumerState<HabitEditPage> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController(text: '30');
  final _unitCtrl = TextEditingController(text: '个');

  HabitType _type = HabitType.check;
  HabitFrequency _frequency = HabitFrequency.daily;
  int _weeklyTarget = 3;
  int _weekdaysMask = 0x7F;
  int _iconCode = kHabitIcons.first.codePoint;
  int _colorHex = AppColors.seed.toARGB32();
  TimeOfDay? _reminder;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.habitId != null;

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    if (p != null) {
      _apply(p);
      _loaded = true;
    }
    if (_isEdit) {
      _load();
    } else if (p == null) {
      // 新建模式没有异步数据要等，直接渲染表单
      _loaded = true;
    }
  }

  Future<void> _load() async {
    try {
      final habit =
          await ref.read(repoProvider).habitDao.getById(widget.habitId!);
      if (habit != null && mounted) {
        setState(() => _apply(habit));
      }
    } catch (e, st) {
      debugPrint('load habit failed: $e\n$st');
    } finally {
      // 无论成功失败都要放开 loading，避免页面永久卡住
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _apply(HabitModel h) {
    _nameCtrl.text = h.name;
    _type = h.type;
    _frequency = h.frequency;
    _weeklyTarget = h.weeklyTarget;
    _weekdaysMask = h.weekdaysMask;
    _iconCode = h.iconCode;
    _colorHex = h.colorHex;
    _reminder = Dates.parseTimeOfDay(h.reminderTime);
    _targetCtrl.text = h.targetValue == null
        ? ''
        : (h.targetValue! == h.targetValue!.roundToDouble()
            ? h.targetValue!.toInt().toString()
            : h.targetValue!.toString());
    _unitCtrl.text = h.unit ?? (h.type == HabitType.duration ? '分钟' : '个');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('给习惯起个名字吧');
      return;
    }
    if (_frequency == HabitFrequency.days && _weekdaysMask == 0) {
      _toast('至少选择一天');
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(repoProvider);
    final now = DateTime.now().millisecondsSinceEpoch;

    double? target;
    if (_type != HabitType.check) {
      target = double.tryParse(_targetCtrl.text.trim());
      if (target == null || target <= 0) {
        setState(() => _saving = false);
        _toast('请输入有效的目标值');
        return;
      }
    }

    final habit = HabitModel(
      id: widget.habitId ?? _uuid(),
      name: name,
      iconCode: _iconCode,
      colorHex: _colorHex,
      type: _type,
      targetValue: target,
      unit: _type == HabitType.check ? null : _unitCtrl.text.trim(),
      frequency: _frequency,
      weeklyTarget: _weeklyTarget,
      weekdaysMask: _weekdaysMask,
      reminderTime: _reminder == null ? null : Dates.timeOfDayLabel(_reminder!),
      sortOrder: _isEdit ? 0 : DateTime.now().millisecondsSinceEpoch % 100000,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final existing =
          _isEdit ? await repo.habitDao.getById(widget.habitId!) : null;
      await repo.saveHabit(
        existing == null
            ? habit
            : habit.copyWithCreated(existing.createdAt, existing.sortOrder, existing.archivedAt),
      );
      if (_reminder != null) {
        await ref
            .read(notificationServiceProvider)
            .scheduleHabitReminder(habit);
      } else {
        await ref.read(notificationServiceProvider).cancelHabitReminder(habit.id);
      }
      ref.invalidate(habitsProvider);
      ref.invalidate(statsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _saving = false);
      _toast('保存失败：$e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _uuid() {
    final r = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'h-$r-${(1000 + DateTime.now().microsecond % 9000)}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final color = Color(_colorHex);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑习惯' : '新建习惯'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: '删除',
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _preview(color),
          const SizedBox(height: 20),
          const SectionTitle('名称'),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.done,
            maxLength: 20,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              hintText: '例如：俯卧撑、跑步、早起',
              counterText: '',
            ),
          ),
          const SizedBox(height: 18),
          const SectionTitle('打卡方式'),
          SegmentedButton<HabitType>(
            segments: [
              for (final t in HabitType.values)
                ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {_type},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              setState(() {
                _type = s.first;
                if (_type == HabitType.duration) {
                  _unitCtrl.text = '分钟';
                  if (_targetCtrl.text.isEmpty) _targetCtrl.text = '20';
                } else if (_type == HabitType.count) {
                  _unitCtrl.text = '个';
                  if (_targetCtrl.text.isEmpty) _targetCtrl.text = '30';
                }
              });
            },
          ),
          if (_type != HabitType.check) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _targetCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    decoration: const InputDecoration(labelText: '目标值'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _unitCtrl,
                    maxLength: 4,
                    decoration:
                        const InputDecoration(labelText: '单位', counterText: ''),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          const SectionTitle('频率'),
          SegmentedButton<HabitFrequency>(
            segments: [
              for (final f in HabitFrequency.values)
                ButtonSegment(value: f, label: Text(f.label)),
            ],
            selected: {_frequency},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _frequency = s.first),
          ),
          if (_frequency == HabitFrequency.weekly) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Text('每周目标', style: TextStyle(fontSize: 14)),
                    const Spacer(),
                    IconButton(
                      onPressed: _weeklyTarget > 1
                          ? () => setState(() => _weeklyTarget--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text('$_weeklyTarget',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                    IconButton(
                      onPressed: _weeklyTarget < 7
                          ? () => setState(() => _weeklyTarget++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ],
          if (_frequency == HabitFrequency.days) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 7; i++)
                  _WeekdayChip(
                    label: Dates.weekdayNames[i],
                    selected: (_weekdaysMask >> i) & 1 == 1,
                    color: color,
                    onTap: () => setState(() => _weekdaysMask ^= (1 << i)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          const SectionTitle('图标与颜色'),
          _IconPicker(
            selected: _iconCode,
            color: color,
            onChanged: (c) => setState(() => _iconCode = c),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in AppColors.palette)
                GestureDetector(
                  onTap: () => setState(() => _colorHex = c.toARGB32()),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorHex == c.toARGB32()
                            ? scheme.onSurface
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: _colorHex == c.toARGB32()
                        ? const Icon(Icons.check_rounded,
                            size: 17, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const SectionTitle('每日提醒'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(_reminder == null ? '未设置' : Dates.timeOfDayLabel(_reminder!)),
              subtitle: Text(_reminder == null ? '到点提醒你打卡' : '每天 ${Dates.timeOfDayLabel(_reminder!)} 提醒'),
              trailing: _reminder == null
                  ? const Icon(Icons.chevron_right_rounded)
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() => _reminder = null),
                    ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _reminder ?? const TimeOfDay(hour: 20, minute: 0),
                );
                if (picked != null) setState(() => _reminder = picked);
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '提示：水獭管家不联网、不注册，所有数据只保存在这台手机上。',
            style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isEdit ? '保存修改' : '创建习惯'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview(Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(13),
            ),
            child: HabitIconArtImage(code: _iconCode, size: 38),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameCtrl.text.trim().isEmpty ? '习惯名称' : _nameCtrl.text.trim(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_frequencyLabel()} · ${_goalLabel()}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _frequencyLabel() {
    switch (_frequency) {
      case HabitFrequency.daily:
        return '每天';
      case HabitFrequency.weekly:
        return '每周 $_weeklyTarget 次';
      case HabitFrequency.days:
        final names = [
          for (var i = 0; i < 7; i++)
            if ((_weekdaysMask >> i) & 1 == 1) Dates.weekdayNames[i]
        ];
        return names.isEmpty ? '未选择' : '周 ${names.join(' ')}';
    }
  }

  String _goalLabel() {
    switch (_type) {
      case HabitType.check:
        return '点击完成';
      case HabitType.count:
      case HabitType.duration:
        final t = _targetCtrl.text.trim();
        return '目标 ${t.isEmpty ? '—' : t}${_unitCtrl.text}';
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个习惯？'),
        content: const Text('所有历史打卡记录会一并删除，且无法恢复。\n如果只是暂时不想做，可以改为归档。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repoProvider).deleteHabit(widget.habitId!);
    await ref.read(notificationServiceProvider).cancelHabitReminder(widget.habitId!);
    ref.invalidate(habitsProvider);
    ref.invalidate(statsProvider);
    ref.invalidate(todayCheckInsProvider);
    ref.invalidate(dateSetsProvider);
    if (mounted) {
      context.go('/');
    }
  }
}

extension on HabitModel {
  HabitModel copyWithCreated(int createdAt, int sortOrder, int? archivedAt) => HabitModel(
        id: id,
        name: name,
        iconCode: iconCode,
        colorHex: colorHex,
        type: type,
        targetValue: targetValue,
        unit: unit,
        frequency: frequency,
        weeklyTarget: weeklyTarget,
        weekdaysMask: weekdaysMask,
        reminderTime: reminderTime,
        sortOrder: sortOrder,
        archivedAt: archivedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? color
                : Theme.of(context).colorScheme.outlineVariant,
            width: 1.4,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

final _iconCodes = kHabitIconCodes;

class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  final int selected;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _iconCodes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final code = _iconCodes[i];
          final isSel = code == selected;
          return GestureDetector(
            onTap: () => onChanged(code),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSel ? color.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSel ? color : Theme.of(context).colorScheme.outlineVariant,
                  width: isSel ? 1.6 : 1,
                ),
              ),
              child: HabitIconArtImage(
                code: code,
                size: 40,
              ),
            ),
          );
        },
      ),
    );
  }
}
