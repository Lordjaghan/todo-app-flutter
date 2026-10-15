import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:to_do_app/data/models/activity.dart';
import 'package:to_do_app/data/models/task.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

abstract interface class TaskReminderScheduler {
  Future<bool> requestPermissions();

  Future<bool> requestExactAlarmPermission();

  Future<void> scheduleTaskReminder({
    required int taskId,
    required String title,
    required String description,
    required DateTime reminderDate,
    required String reminderType,
  });

  Future<void> cancelTaskReminder(int taskId);
}

abstract interface class ActivityReminderScheduler {
  bool get supportsActivityReminders;

  Future<void> scheduleActivityReminder({
    required int reminderId,
    required String title,
    required String time,
    required ActivityPeriod period,
  });

  Future<void> cancelActivityReminder(int reminderId);
}

class NotificationPermissionDeniedException implements Exception {}

class ExactAlarmPermissionDeniedException implements Exception {}

class ReminderTimeInPastException implements Exception {}

class ActivityReminderUnsupportedException implements Exception {}

class NotificationService
    implements TaskReminderScheduler, ActivityReminderScheduler {
  static final NotificationService instance = NotificationService._internal();
  static const _alarmMethodChannel = MethodChannel('to_do_app/task_alarm');
  static const _alarmCategoryId = 'TASK_ALARM';
  static const _snoozeActionId = 'SNOOZE_5_MINUTES';
  static const _dismissActionId = 'DISMISS_ALARM';

  static final _alarmCategory = DarwinNotificationCategory(
    _alarmCategoryId,
    actions: <DarwinNotificationAction>[
      DarwinNotificationAction.plain(
        _snoozeActionId,
        'Snooze 5 min',
        options: <DarwinNotificationActionOption>{
          DarwinNotificationActionOption.foreground,
        },
      ),
      DarwinNotificationAction.plain(
        _dismissActionId,
        'Dismiss',
        options: <DarwinNotificationActionOption>{
          DarwinNotificationActionOption.foreground,
          DarwinNotificationActionOption.destructive,
        },
      ),
    ],
  );

  @visibleForTesting
  static DateTime snoozedReminderDate(DateTime currentTime) =>
      currentTime.add(const Duration(minutes: 5));

  @visibleForTesting
  static NotificationDetails notificationDetailsForReminderType(
    String reminderType,
  ) {
    final isAlarm = reminderType == ReminderType.alarm;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        isAlarm ? 'task_alarm_alerts_v2' : 'task_alarms',
        isAlarm ? 'Task Alarm Alerts' : 'Task Alarms',
        channelDescription: 'Exact-time alerts for scheduled tasks',
        importance: Importance.max,
        priority: Priority.max,
        enableVibration: true,
        playSound: true,
        audioAttributesUsage: isAlarm
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notification,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        categoryIdentifier: isAlarm ? _alarmCategoryId : null,
      ),
    );
  }

  factory NotificationService() {
    return instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();

    final localTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimeZone));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final iOSSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: <DarwinNotificationCategory>[_alarmCategory],
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    final initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iOSSettings,
      linux: linuxSettings,
    );

    await notifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    NotificationAppLaunchDetails? launchDetails;
    try {
      launchDetails = await notifications.getNotificationAppLaunchDetails();
    } on UnimplementedError {
      launchDetails = null;
    }
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails?.notificationResponse;
      if (response != null) await _handleNotificationAction(response);
    }
  }

  @override
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidPlugin?.requestNotificationsPermission() ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iOSPlugin = notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await iOSPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return false;
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final androidPlugin = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return false;

    if (await androidPlugin.canScheduleExactNotifications() ?? false) {
      return true;
    }

    return await androidPlugin.requestExactAlarmsPermission() ?? false;
  }

  @override
  Future<void> scheduleTaskReminder({
    required int taskId,
    required String title,
    required String description,
    required DateTime reminderDate,
    required String reminderType,
  }) async {
    if (!reminderDate.isAfter(DateTime.now())) {
      throw ReminderTimeInPastException();
    }

    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid &&
        !(await notifications
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.canScheduleExactNotifications() ??
            false)) {
      throw ExactAlarmPermissionDeniedException();
    }

    final body = description.trim().isEmpty
        ? 'This task is due now.'
        : description;
    if (isAndroid && reminderType == ReminderType.alarm) {
      await _alarmMethodChannel.invokeMethod<void>('schedule', {
        'taskId': taskId,
        'title': title,
        'body': body,
        'scheduledTime': reminderDate.millisecondsSinceEpoch,
      });
      return;
    }

    await notifications.zonedSchedule(
      id: taskId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(reminderDate, tz.local),
      notificationDetails: notificationDetailsForReminderType(reminderType),
      payload: jsonEncode({
        'taskId': taskId,
        'title': title,
        'description': description,
        'reminderType': reminderType,
      }),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  @override
  bool get supportsActivityReminders =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @visibleForTesting
  static DateTime nextActivityReminderDate(
    DateTime now,
    String time,
    ActivityPeriod period,
  ) {
    final values = time.split(':');
    final hour = int.parse(values[0]);
    final minute = int.parse(values[1]);
    var date = DateTime(now.year, now.month, now.day, hour, minute);
    if (period == ActivityPeriod.weekly) {
      final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
      date = date.add(Duration(days: daysUntilMonday));
      if (!date.isAfter(now)) date = date.add(const Duration(days: 7));
      return date;
    }
    if (!date.isAfter(now)) date = date.add(const Duration(days: 1));
    return date;
  }

  @override
  Future<void> scheduleActivityReminder({
    required int reminderId,
    required String title,
    required String time,
    required ActivityPeriod period,
  }) async {
    if (!supportsActivityReminders) {
      throw ActivityReminderUnsupportedException();
    }
    if (!await requestPermissions()) {
      throw NotificationPermissionDeniedException();
    }
    if (!await requestExactAlarmPermission()) {
      throw ExactAlarmPermissionDeniedException();
    }
    final next = nextActivityReminderDate(DateTime.now(), time, period);
    await notifications.zonedSchedule(
      id: reminderId,
      title: title,
      body: 'Time for your habit.',
      scheduledDate: tz.TZDateTime.from(next, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'activity_reminders',
          'Activity reminders',
          channelDescription: 'Daily and weekly habit reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      matchDateTimeComponents: period == ActivityPeriod.daily
          ? DateTimeComponents.time
          : DateTimeComponents.dayOfWeekAndTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancelActivityReminder(int reminderId) async {
    await notifications.cancel(id: reminderId);
  }

  @override
  Future<void> cancelTaskReminder(int taskId) async {
    await notifications.cancel(id: taskId);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _alarmMethodChannel.invokeMethod<void>('cancel', {
        'taskId': taskId,
      });
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    unawaited(_handleNotificationAction(response));
  }

  Future<void> _handleNotificationAction(NotificationResponse response) async {
    if (response.actionId == _dismissActionId) {
      final taskId = response.id;
      if (taskId != null) await notifications.cancel(id: taskId);
      return;
    }
    if (response.actionId != _snoozeActionId || response.payload == null) {
      return;
    }

    final payload = jsonDecode(response.payload!);
    if (payload is! Map<String, dynamic>) return;
    await scheduleTaskReminder(
      taskId: payload['taskId'] as int,
      title: payload['title'] as String,
      description: payload['description'] as String,
      reminderDate: snoozedReminderDate(DateTime.now()),
      reminderType: payload['reminderType'] as String,
    );
  }
}
