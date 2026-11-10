import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/voice_service.dart';

const _kTtsEnabled = 'ai_tts_enabled';

/// 语音能力单例（页面销毁时停止识别与朗读）
final voiceServiceProvider = Provider<VoiceService>((ref) {
  final svc = VoiceService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// 小獭回复是否自动朗读（持久化，默认开启）
final voiceTtsEnabledProvider =
    StateNotifierProvider<TtsEnabledNotifier, bool>((ref) {
  return TtsEnabledNotifier();
});

class TtsEnabledNotifier extends StateNotifier<bool> {
  TtsEnabledNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getBool(_kTtsEnabled);
    if (v != null && mounted) state = v;
  }

  Future<void> set(bool v) async {
    state = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kTtsEnabled, v);
  }

  Future<void> toggle() => set(!state);
}
