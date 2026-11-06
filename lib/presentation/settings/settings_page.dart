import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/providers/data_providers.dart';
import '../../application/providers/expense_providers.dart';
import '../../application/providers/invest_providers.dart';
import '../../application/providers/lock_provider.dart';
import '../../application/providers/settings_provider.dart';
import '../../core/notification/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../lock/pin_setup_page.dart';
import '../widgets/habit_icon_art.dart';
import '../widgets/common.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _ProfileHeader(),
          const SizedBox(height: 20),
          const SectionTitle('外观'),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: settings.themeMode,
                  onChanged: (v) => notifier.setThemeMode(v!),
                  title: const Text('跟随系统'),
                  dense: true,
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: settings.themeMode,
                  onChanged: (v) => notifier.setThemeMode(v!),
                  title: const Text('浅色'),
                  dense: true,
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: settings.themeMode,
                  onChanged: (v) => notifier.setThemeMode(v!),
                  title: const Text('深色'),
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('打卡'),
          Card(
            child: SwitchListTile(
              value: settings.allowBackfill,
              onChanged: (v) => notifier.setAllowBackfill(v),
              title: const Text('允许补卡'),
              subtitle: const Text('可在习惯详情里补打最近 7 天的卡'),
              secondary: const Icon(Icons.event_repeat_rounded),
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('提醒'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('通知权限'),
                  subtitle: const Text('未授权时提醒不会生效'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final ok = await NotificationService.instance.permissionGranted();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok
                            ? '通知权限已开启'
                            : '通知未开启，请到系统设置 → 应用 → 水獭管家 → 通知 中允许'),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: const Text('取消全部提醒'),
                  onTap: () async {
                    await NotificationService.instance.cancelAll();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已取消全部本地提醒')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('安全'),
          const _SecuritySection(),
          const SizedBox(height: 20),
          const SectionTitle('数据'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('导出数据'),
                  subtitle: const Text('习惯 / 打卡 / 记账 / 昵称，打包为 JSON 分享'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _export(context, ref),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: const Text('导入数据'),
                  subtitle: const Text('从备份 JSON 恢复（覆盖现有数据）'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _import(context, ref),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('已归档的习惯'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showArchived(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('关于'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('隐私'),
                  subtitle: Text('不联网、不注册、不采集任何数据。\n所有记录只保存在这台手机上。'),
                  isThreeLine: true,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('版本'),
                  trailing: Text('2.4.4',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Image.asset(
                    'assets/habit_icons/otter_face.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: 6),
                Text('水獭管家 · 养成好习惯',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final backup = ref.read(backupServiceProvider);
      final file = await backup.writeExportFile();
      final payload = await backup.buildPayload();
      final counts = '${payload['habits']?.length ?? 0} 个习惯 · '
          '${payload['checkIns']?.length ?? 0} 条打卡 · '
          '${payload['expenses']?.length ?? 0} 笔记账 · '
          '${payload['investRecords']?.length ?? 0} 条理财';

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '水獭管家数据备份（$counts）',
        ),
      );
      messenger.showSnackBar(
        SnackBar(content: Text('已生成备份：$counts，可通过分享面板保存或发送')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = picked?.path;
      if (path == null) return;
      if (!context.mounted) return;

      // 读取摘要供确认
      final backup = ref.read(backupServiceProvider);
      final summary = await backup.inspect(path);

      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入备份？'),
          content: Text(
            '备份时间：${summary.exportedAt.isEmpty ? '未知' : summary.exportedAt.substring(0, 19).replaceAll('T', ' ')}\n'
            '内容：${summary.habits} 个习惯 · ${summary.checkIns} 条打卡'
            '${summary.version >= 2 ? ' · ${summary.expenses} 笔记账' : ''}'
            '${summary.investRecords > 0 ? ' · ${summary.investRecords} 条理财' : ''}'
            '${summary.nickname.isNotEmpty ? '\n昵称：${summary.nickname}' : ''}\n\n'
            '⚠️ 导入将覆盖当前 App 里的全部数据，且无法恢复。',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('覆盖导入')),
          ],
        ),
      );
      if (confirmed != true) return;

      final done = await backup.importFrom(path);

      // 刷新所有依赖数据库的 Provider
      ref.invalidate(habitsProvider);
      ref.invalidate(todayCheckInsProvider);
      ref.invalidate(dateSetsProvider);
      ref.invalidate(statsProvider);
      ref.invalidate(habitCountProvider);
      ref.invalidate(expensesOfPeriodProvider);
      ref.invalidate(investListOfPeriodProvider);
      ref.invalidate(settingsProvider);

      messenger.showSnackBar(SnackBar(
        content: Text(
            '导入成功：${done.habits} 个习惯 · ${done.checkIns} 条打卡 · ${done.expenses} 笔记账 · ${done.investRecords} 条理财'),
      ));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：${e.message}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  Future<void> _showArchived(BuildContext context, WidgetRef ref) async {
    final archived = await ref.read(repoProvider).archivedHabits();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已归档的习惯',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (archived.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('没有归档的习惯',
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                    ),
                  )
                else
                  ...archived.map((h) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: HabitIconArtImage(code: h.iconCode, size: 36),
                        title: Text(h.name),
                        subtitle: Text(h.frequencyLabel),
                        trailing: TextButton(
                          onPressed: () async {
                            await ref.read(repoProvider).restoreHabit(h.id);
                            ref.invalidate(habitsProvider);
                            ref.invalidate(statsProvider);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('恢复'),
                        ),
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final count = ref.watch(habitCountProvider).valueOrNull ?? 0;
    final nickname = ref.watch(settingsProvider).nickname;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.seed.withValues(alpha: 0.14),
            AppColors.seed.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.seed.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.seed.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Image.asset(
              'assets/habit_icons/otter_sleep.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname.trim().isEmpty ? '小水獭' : nickname.trim(),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text('正在坚持 $count 个习惯',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          // 点击修改昵称
          IconButton(
            tooltip: '修改昵称',
            icon: Icon(Icons.edit_rounded,
                size: 20, color: scheme.onSurfaceVariant),
            onPressed: () => _editNickname(context, ref, nickname),
          ),
        ],
      ),
    );
  }

  Future<void> _editNickname(
      BuildContext context, WidgetRef ref, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(
            hintText: '例如：小水獭、阿健、卷卷',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(settingsProvider.notifier).setNickname(name);
    }
  }
}

/// 安全区块：密码锁 / 指纹 / 自动锁定
class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(lockProvider);
    final supported = ref.watch(biometricSupportProvider).valueOrNull ?? false;

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: lock.pinEnabled,
            secondary: const Icon(Icons.pin_outlined),
            title: const Text('密码锁'),
            subtitle: Text(lock.pinEnabled
                ? '已开启 · 进入 App 需输入 6 位密码'
                : '开启后每次进入 App 需输入 6 位密码'),
            onChanged: (v) => _togglePin(context, ref, enable: v),
          ),
          if (lock.pinEnabled) ...[
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: const Text('修改密码'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _changePin(context, ref),
            ),
            const Divider(height: 1, indent: 56),
            SwitchListTile(
              value: lock.biometricEnabled,
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('指纹解锁'),
              subtitle: Text(supported
                  ? (lock.biometricEnabled
                      ? '已开启 · 可用指纹替代密码'
                      : '开启后可用指纹快速解锁')
                  : '此设备尚未录入指纹，请先在系统设置中添加'),
              onChanged: supported
                  ? (v) => _toggleBiometric(context, ref, enable: v)
                  : null,
            ),
            const Divider(height: 1, indent: 56),
            SwitchListTile(
              value: lock.autoLock,
              secondary: const Icon(Icons.lock_clock_rounded),
              title: const Text('离开后自动锁定'),
              subtitle: const Text('切到后台超过 30 秒，回来需要重新解锁'),
              onChanged: (v) =>
                  ref.read(lockProvider.notifier).setAutoLock(v),
            ),
          ],
        ],
      ),
    );
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _togglePin(BuildContext context, WidgetRef ref,
      {required bool enable}) async {
    if (enable) {
      final ok = await PinSetupPage.push(context, PinSetupMode.create);
      if (!context.mounted) return;
      if (ok == true) _toast(context, '密码锁已开启，下次进入需要输入密码');
      ref.invalidate(biometricSupportProvider);
      return;
    }

    // 关闭前先验证身份
    final verified = await PinSetupPage.push(context, PinSetupMode.verify);
    if (!context.mounted) return;
    if (verified != true) return;
    await ref.read(lockProvider.notifier).disablePin();
    if (context.mounted) _toast(context, '密码锁已关闭');
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final ok = await PinSetupPage.push(context, PinSetupMode.change);
    if (!context.mounted) return;
    if (ok == true) _toast(context, '密码已更新');
  }

  Future<void> _toggleBiometric(BuildContext context, WidgetRef ref,
      {required bool enable}) async {
    if (enable) {
      // 开启前先验证一次，确保指纹真的可用
      final r = await ref
          .read(lockServiceProvider)
          .authenticateBiometric(reason: '验证身份以开启指纹解锁');
      if (!context.mounted) return;
      if (!r.success) {
        if (r.message != null && r.message != '已取消指纹验证') {
          _toast(context, r.message!);
        }
        return;
      }
      await ref.read(lockProvider.notifier).setBiometric(true);
      if (context.mounted) _toast(context, '指纹解锁已开启');
      return;
    }
    await ref.read(lockProvider.notifier).setBiometric(false);
    if (context.mounted) _toast(context, '指纹解锁已关闭');
  }
}
