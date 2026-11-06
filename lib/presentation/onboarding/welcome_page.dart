import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';

/// 欢迎页：首次使用必须给自己起一个昵称
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _nameOk => _nameCtrl.text.trim().isNotEmpty;

  Future<void> _start() async {
    if (!_nameOk || _saving) return;
    setState(() => _saving = true);
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setNickname(_nameCtrl.text);
    await notifier.completeOnboarding();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 1),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.seed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Image.asset(
                  'assets/habit_icons/otter_sleep.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                '您好主人，\n我是你的管家小獭。',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                '习惯打卡 + 记账，帮你管好每一天。\n完全离线，不用注册，数据只在你的手机上。',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.6,
                    ),
              ),
              const SizedBox(height: 24),
              // 昵称输入（必填）
              TextField(
                controller: _nameCtrl,
                maxLength: 12,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _start(),
                decoration: InputDecoration(
                  labelText: '给自己起个昵称',
                  hintText: '例如：小水獭、阿健、卷卷',
                  counterText: '',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Image.asset(
                      'assets/habit_icons/otter_yoga.png',
                      width: 26,
                      height: 26,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const Spacer(flex: 1),
              _FeatureRow(
                icon: Icons.touch_app_rounded,
                title: '一秒钟打卡',
                subtitle: '点一下就算完成，不打断你的节奏',
              ),
              const SizedBox(height: 16),
              _FeatureRow(
                icon: Icons.local_fire_department_outlined,
                title: '连续天数 + 热力图',
                subtitle: '看得见的进步，才是最强的动力',
              ),
              const SizedBox(height: 16),
              _FeatureRow(
                icon: Icons.savings_outlined,
                title: '记账管家',
                subtitle: '收支一目了然，日 / 月 / 年报表统计',
              ),
              const SizedBox(height: 16),
              _FeatureRow(
                icon: Icons.wifi_off_rounded,
                title: '离线可用',
                subtitle: '无网络权限，无账号，数据留在本机',
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _nameOk ? _start : null,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('开始使用'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
