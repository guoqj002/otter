import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 语音能力封装：系统语音识别（STT）+ 系统朗读（TTS）
///
/// 全部走手机系统能力：不额外消耗 AI token，也不需要任何第三方密钥。
/// 识别语言固定中文（zh-CN），播报语言与识别一致。
class VoiceService {
  VoiceService();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttReady = false;
  bool _ttsReady = false;

  // 当前听音会话的回调（speech_to_text 7.x 把错误/状态回调放在 initialize）
  void Function(String message)? _onError;
  void Function(bool listening)? _onStatus;

  bool get isListening => _stt.isListening;

  // ------------------------------------------------------------- 语音识别

  /// 初始化识别引擎（含权限申请）。返回是否可用。
  Future<bool> initStt() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(
        onError: (SpeechRecognitionError e) =>
            _onError?.call(_mapError(e.errorMsg)),
        onStatus: (s) => _onStatus?.call(s == 'listening'),
        debugLogging: false,
      );
      return _sttReady;
    } catch (_) {
      _sttReady = false;
      return false;
    }
  }

  /// 开始聆听；[onResult] 会收到临时结果（isFinal=false）与最终结果，
  /// [onStatus] 用于同步「是否正在聆听」的 UI 状态
  Future<bool> startListening({
    required void Function(String text, bool isFinal) onResult,
    required void Function(String message) onError,
    void Function(bool listening)? onStatus,
  }) async {
    final ok = await initStt();
    if (!ok) {
      onError('这台设备没有可用的语音识别服务，请检查系统语音输入是否开启');
      return false;
    }
    _onError = onError;
    _onStatus = onStatus;
    try {
      await _stt.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'zh_CN',
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
        ),
        onResult: (SpeechRecognitionResult r) =>
            onResult(r.recognizedWords, r.finalResult),
      );
      return true;
    } catch (_) {
      onError('语音识别启动失败，请稍后再试');
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      if (_stt.isListening) await _stt.stop();
    } catch (_) {/* 忽略 */}
  }

  Future<void> cancelListening() async {
    try {
      if (_stt.isListening) await _stt.cancel();
    } catch (_) {/* 忽略 */}
  }

  static String _mapError(String code) => switch (code) {
        'error_no_match' => '没听清，再说一次吧',
        'error_speech_timeout' => '没听到声音，点麦克风再试一次',
        'error_network' || 'error_network_timeout' =>
          '语音识别服务连接失败，请检查网络或系统语音服务',
        'error_permission' || 'error_insufficient_permissions' =>
          '没有麦克风权限，请到系统设置里允许录音',
        'error_busy' => '语音识别正忙，稍后再试',
        'error_language_not_supported' => '系统缺少中文语音识别，请先安装中文语音包',
        _ => '语音识别出错了，请再试一次',
      };

  // ------------------------------------------------------------- 朗读

  Future<void> initTts() async {
    if (_ttsReady) return;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _ttsReady = true;
    } catch (_) {
      _ttsReady = false;
    }
  }

  /// 朗读一段文本（自动清洗 Markdown / 指令块 / emoji）
  Future<bool> speak(String raw) async {
    final text = ttsClean(raw);
    if (text.isEmpty) return false;
    await initTts();
    try {
      await _tts.stop();
      await _tts.speak(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {/* 忽略 */}
  }

  void dispose() {
    _stt.cancel();
    _tts.stop();
  }
}

/// 朗读前的文本清洗：去掉指令块、Markdown 标记与 emoji，
/// 只留适合念出来的中文句子
String ttsClean(String raw) {
  var s = raw;
  // 指令块整体去掉
  s = s.replaceAll(RegExp(r'```otter[\s\S]*?```'), ' ');
  // 其他代码块
  s = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  // Markdown 标题/加粗/列表/引用/行内代码
  s = s.replaceAll(RegExp(r'[#*`>_~]'), ' ');
  // 链接 [text](url) → text
  s = s.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
  // 合并空白
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  // emoji 与变体选择符
  s = s.replaceAll(
      RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]',
          unicode: true),
      '');
  return s.trim();
}
