import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers/data_providers.dart';
import '../habit_presets.dart';
import '../widgets/habit_icon_art.dart';

/// 创建引导：从模板一键创建第一个习惯
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, this.isQuickCreate = false});

  final bool isQuickCreate;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final Set<int> _selected = {0};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        title: const Text('选几个开始吧'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              '先选 1-3 个最容易坚持的，之后再慢慢加。\n选好可以直接开始打卡。',
              style: TextStyle(fontSize: 13.5, height: 1.6, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
              ),
              itemCount: habitPresets.length,
              itemBuilder: (context, i) {
                final p = habitPresets[i];
                final selected = _selected.contains(i);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (selected) {
                      _selected.remove(i);
                    } else {
                      _selected.add(i);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? p.color.withValues(alpha: 0.1)
                          : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? p.color : scheme.outlineVariant,
                        width: selected ? 1.8 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            HabitIconArtImage(code: p.icon.codePoint, size: 30),
                            const Spacer(),
                            if (selected)
                              Icon(Icons.check_circle_rounded,
                                  color: p.color, size: 18),
                          ],
                        ),
                        const Spacer(),
                        Text(p.name,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(p.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selected.isEmpty || _saving ? null : _create,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text('开始（${_selected.length} 个）'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/habit/new'),
                    child: const Text('自定义习惯'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    final repo = ref.read(repoProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    var order = 0;
    for (final i in _selected) {
      final p = habitPresets[i];
      final habit = p.toHabit(
        id: 'h-${now + i}-$i',
        sortOrder: order++,
        now: now,
      );
      await repo.saveHabit(habit);
    }
    ref.invalidate(habitsProvider);
    ref.invalidate(statsProvider);
    if (mounted) context.go('/');
  }
}
