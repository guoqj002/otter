import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers/ai_providers.dart';
import '../../application/services/ai_service.dart';

/// 「小獭」AI 对话页：数字人家庭理财管家
class OtterChatPage extends ConsumerStatefulWidget {
  const OtterChatPage({super.key});

  @override
  ConsumerState<OtterChatPage> createState() => _OtterChatPageState();
}

class _OtterChatPageState extends ConsumerState<OtterChatPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final prompt = ref.read(otterSystemPromptProvider).valueOrNull;
    if (prompt == null) return;
    _input.clear();
    _focus.unfocus();
    ref.read(chatProvider.notifier).send(text, prompt);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(aiConfigProvider);
    final chat = ref.watch(chatProvider);
    // 必须监听财务快照，autoDispose provider 才会真正加载
    final promptReady = ref.watch(otterSystemPromptProvider).hasValue;
    final scheme = Theme.of(context).colorScheme;

    if (!config.isConfigured) return _NotConfiguredView(config: config);

    final messages = chat.messages;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const _OtterAvatar(size: 30),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('小獭'),
              Text(
                '${config.provider.name} · ${config.model}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ]),
        actions: [
          IconButton(
            tooltip: '清空对话',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: chat.messages.isEmpty || chat.sending
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('清空对话'),
                        content: const Text('确定要清空与小獭的全部对话记录吗？'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('清空')),
                        ],
                      ),
                    );
                    if (ok == true) ref.read(chatProvider.notifier).clear();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty && !chat.sending
                ? _WelcomeView(onPick: (t) {
                    _input.text = t;
                    _send();
                  })
                // reverse 列表：新消息自动锚定在底部
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: messages.length + (chat.sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      final idx = messages.length - 1 - i;
                      if (idx < 0) return const _TypingBubble();
                      final m = messages[idx];
                      return _Bubble(message: m);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      enabled: !chat.sending,
                      decoration: InputDecoration(
                        hintText: chat.sending ? '小獭思考中…' : '问问小獭，比如“我这个月花得怎么样？”',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: (chat.sending || !promptReady) ? null : _send,
                    icon: chat.sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 未配置引导
// ---------------------------------------------------------------------------

class _NotConfiguredView extends StatelessWidget {
  const _NotConfiguredView({required this.config});

  final AiConfig config;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Row(children: [
        _OtterAvatar(size: 30),
        SizedBox(width: 8),
        Text('小獭'),
      ])),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _OtterAvatar(size: 96),
              const SizedBox(height: 20),
              Text('小獭还在睡觉…',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '先到「我的 → AI 助手」里选个服务商（DeepSeek / 通义千问 / 智谱 / Kimi / OpenAI），'
                '填入对应的 API Key，叫醒小獭后它就能帮你分析记账和理财啦。',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('去配置 AI'),
                onPressed: () => context.go('/settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 欢迎语与快捷问题
// ---------------------------------------------------------------------------

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({required this.onPick});

  final ValueChanged<String> onPick;

  static const _suggestions = [
    '这个月我花得怎么样？',
    '帮我分析一下理财盈亏',
    '我在哪个分类花得最多？',
    '给点省钱的小建议吧',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const _OtterAvatar(size: 88),
          const SizedBox(height: 16),
          Text('主人好呀，我是小獭 🦦',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            '我看过你这个月的账本和理财记录了，\n有什么想问的尽管问我～',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final s in _suggestions)
                ActionChip(
                  label: Text(s),
                  onPressed: () => onPick(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 气泡
// ---------------------------------------------------------------------------

class _OtterAvatar extends StatelessWidget {
  const _OtterAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/habit_icons/otter_face.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final scheme = Theme.of(context).colorScheme;
    final isError = message.content.startsWith('⚠️');

    final bubbleColor = isUser
        ? scheme.primary
        : isError
            ? scheme.errorContainer
            : scheme.surfaceContainerHighest;
    final textColor = isUser
        ? scheme.onPrimary
        : isError
            ? scheme.onErrorContainer
            : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isUser) ...[
              const _OtterAvatar(size: 28),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Container(
                margin: EdgeInsets.only(
                    left: isUser ? 48 : 0, right: isUser ? 0 : 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                child: SelectableText(
                  message.content,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: textColor, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const _OtterAvatar(size: 28),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  return Container(
                    width: 7,
                    height: 7,
                    margin: EdgeInsets.only(right: i == 2 ? 0 : 5),
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
