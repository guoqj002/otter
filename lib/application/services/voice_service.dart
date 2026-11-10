import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 小獭的音色风格
///
/// 系统 TTS 没有「卡通音色」这个开关，只能靠三件事拼出来：
/// 1. **音高**（pitch）—— 决定「儿童 / 少女 / 成人」的听感，是最关键的一项；
/// 2. **语速**（rate）—— 偏快显活泼、偏慢显软萌；
/// 3. **语音包**（voice）—— 在中文本地语音里优先挑偏细偏亮的那个。
class OtterVoice {
  const OtterVoice({
    required this.id,
    required this.label,
    required this.desc,
    required this.pitch,
    required this.rate,
    this.voiceHints = const [],
  });

  /// 持久化用的稳定标识
  final String id;
  final String label;
  final String desc;

  /// 音高：系统默认 1.0，1.3 以上会明显偏「小孩/卡通」，超过 1.8 开始失真
  final double pitch;

  /// 语速：系统默认 0.5
  final double rate;

  /// 语音包名字的偏好关键词，命中越靠前越优先
  final List<String> voiceHints;

  /// 默认音色：清脆偏高的少女音，慢一点软一点
  static const cute = OtterVoice(
    id: 'cute',
    label: '萌系小獭',
    desc: '清脆偏高的少女音，软一点、慢一点',
    pitch: 1.45,
    rate: 0.50,
    voiceHints: ['ssa', 'ccc', 'female', 'child'],
  );

  /// 更尖更快，跳脱的调皮感
  static const playful = OtterVoice(
    id: 'playful',
    label: '活泼调皮',
    desc: '音调更高、语速更快，说话带点跳脱',
    pitch: 1.66,
    rate: 0.58,
    voiceHints: ['ssa', 'ccc', 'female'],
  );

  /// 像小朋友说话
  static const soft = OtterVoice(
    id: 'soft',
    label: '软萌童声',
    desc: '音调高、语速慢，像小朋友在念',
    pitch: 1.56,
    rate: 0.44,
    voiceHints: ['child', 'ssc', 'female', 'ccc'],
  );

  /// 不加工，听什么是什么
  static const natural = OtterVoice(
    id: 'natural',
    label: '标准朗读',
    desc: '系统默认音色，平稳不夸张',
    pitch: 1.0,
    rate: 0.5,
  );

  static const all = <OtterVoice>[cute, playful, soft, natural];

  /// 按 id 查找，未知 id 回退到默认音色
  static OtterVoice byId(String? id) {
    for (final v in all) {
      if (v.id == id) return v;
    }
    return cute;
  }
}

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

  /// 当前音色（默认萌系）
  OtterVoice _voice = OtterVoice.cute;

  /// 已真正下发给引擎的音色 id，null 表示还没下发
  String? _appliedVoiceId;

  OtterVoice get voice => _voice;

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
    if (!_ttsReady) {
      try {
        await _tts.awaitSpeakCompletion(true);
        _ttsReady = true;
      } catch (_) {
        _ttsReady = false;
      }
    }
    if (_appliedVoiceId != _voice.id) await applyVoiceStyle(_voice);
  }

  /// 切换音色：把音高、语速、语音包一起下发（幂等，同一音色不重复设置）
  Future<void> applyVoiceStyle(OtterVoice v) async {
    _voice = v;
    if (_appliedVoiceId == v.id) return;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setPitch(v.pitch);
      await _tts.setSpeechRate(v.rate);
      final pick = await _pickVoiceName(v);
      if (pick != null) {
        await _tts.setVoice({'name': pick, 'locale': 'zh-CN'});
      }
    } catch (_) {
      // 语音包切换失败不影响朗读，继续用引擎默认音色 + 音高/语速
    }
    _appliedVoiceId = v.id;
  }

  /// 在中文本地语音里挑一个最贴近「可爱」的：按 [OtterVoice.voiceHints] 打分，
  /// 纯语种占位项（`zh-CN-language` 之类）排在最后
  Future<String?> _pickVoiceName(OtterVoice v) async {
    if (v.voiceHints.isEmpty) return null;
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return null;
      String? best;
      var bestScore = 0;
      for (final e in raw) {
        if (e is! Map) continue;
        final name = (e['name'] ?? '').toString();
        final locale = (e['locale'] ?? '').toString().toLowerCase();
        if (name.isEmpty) continue;
        if (!locale.startsWith('zh') && !locale.startsWith('cmn')) continue;
        final n = name.toLowerCase();
        var score = 0;
        for (var i = 0; i < v.voiceHints.length; i++) {
          if (n.contains(v.voiceHints[i])) score += (v.voiceHints.length - i) * 10;
        }
        if (n.contains('language')) score -= 5; // 占位项，音色不固定
        if (score > bestScore) {
          bestScore = score;
          best = name;
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  /// 试听用的示例句（本身也写成小獭的口吻）
  static const previewText =
      '主人你好呀，我是小獭，今天也一起把账记好、把习惯坚持下来吧！';

  /// 试听某个音色：切换到该音色并念一句示例
  Future<bool> preview(OtterVoice v) async {
    _voice = v;
    await initTts(); // 内部会检测到音色变化并下发参数
    return speak(previewText);
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
