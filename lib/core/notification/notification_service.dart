import 'dart:io';

import 'package:flutter/foundation.dart' show PlatformDispatcher, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/utils/date_utils.dart';
import '../../domain/entities/habit.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});

/// 本地提醒：每习惯一个固定 id，改时间/删除时先取消再重排
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;
  Future<void>? _initFuture;

  static const _channelId = 'habit_reminder';
  static const _channelName = '习惯提醒';

  Future<void> init() {
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    if (_inited) return;
    tzdata.initializeTimeZones();
    // 用设备时区名，失败退回 UTC+8
    try {
      final name = PlatformDispatcher.instance.locale.countryCode;
      tz.setLocalLocation(tz.getLocation(_tzNameFromLocale()));
      debugPrint('tz set: $name');
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: '提醒你完成今天的习惯打卡',
          importance: Importance.high,
        ),
      );
    }
    _inited = true;
  }

  String _tzNameFromLocale() {
    // 常见时区兜底映射，未命中时使用 +08
    final offset = DateTime.now().timeZoneOffset;
    if (offset == const Duration(hours: 8)) return 'Asia/Shanghai';
    if (offset == const Duration(hours: 9)) return 'Asia/Tokyo';
    if (offset == const Duration(hours: 0)) return 'UTC';
    if (offset == const Duration(hours: -5)) return 'America/New_York';
    return 'Asia/Shanghai';
  }

  int _notifId(String habitId) => habitId.hashCode.abs() % 100000;

  Future<void> scheduleHabitReminder(HabitModel habit) async {
    await init();
    if (habit.reminderTime == null) return;
    final t = Dates.parseTimeOfDay(habit.reminderTime);
    if (t == null) return;

    await cancelHabitReminder(habit.id);

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: _notifId(habit.id),
      title: '该打卡了：${habit.name}',
      body: '${habit.goalLabel} · 别断了连续记录 🔥',
      scheduledDate: next,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '提醒你完成今天的习惯打卡',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: habit.id,
    );
  }

  Future<void> cancelHabitReminder(String habitId) async {
    await init();
    await _plugin.cancel(id: _notifId(habitId));
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  Future<bool> permissionGranted() async {
    await init();
    if (!Platform.isAndroid) return true;
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await impl?.areNotificationsEnabled() ?? false;
  }
}
