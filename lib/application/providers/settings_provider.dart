import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用级偏好设置
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.allowBackfill = false,
    this.onboarded = false,
    this.nickname = '',
  });

  final ThemeMode themeMode;
  final bool allowBackfill;
  final bool onboarded;

  /// 用户昵称（首次启动时设置）
  final String nickname;

  bool get hasNickname => nickname.trim().isNotEmpty;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? allowBackfill,
    bool? onboarded,
    String? nickname,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        allowBackfill: allowBackfill ?? this.allowBackfill,
        onboarded: onboarded ?? this.onboarded,
        nickname: nickname ?? this.nickname,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _kTheme = 'theme_mode';
  static const _kBackfill = 'allow_backfill';
  static const _kOnboarded = 'onboarded';
  static const _kNickname = 'nickname';

  SharedPreferences? _prefs;

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    final t = p.getString(_kTheme) ?? 'system';
    state = AppSettings(
      themeMode: switch (t) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      allowBackfill: p.getBool(_kBackfill) ?? false,
      onboarded: p.getBool(_kOnboarded) ?? false,
      nickname: p.getString(_kNickname) ?? '',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs?.setString(_kTheme, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  Future<void> setAllowBackfill(bool v) async {
    state = state.copyWith(allowBackfill: v);
    await _prefs?.setBool(_kBackfill, v);
  }

  Future<void> setNickname(String v) async {
    final name = v.trim();
    state = state.copyWith(nickname: name);
    await _prefs?.setString(_kNickname, name);
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(onboarded: true);
    await _prefs?.setBool(_kOnboarded, true);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
