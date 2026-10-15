import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:to_do_app/data/datasources/task_database.dart';
import 'package:to_do_app/data/models/activity.dart';
import 'package:to_do_app/data/models/subtask.dart';
import 'package:to_do_app/data/models/task.dart';
import 'package:to_do_app/data/repositories/task_repository.dart';
import 'package:to_do_app/data/repositories/activity_repository.dart';
import 'package:to_do_app/features/activity/providers/activity_provider.dart';
import 'package:to_do_app/features/tasks/providers/task_provider.dart';
import 'package:to_do_app/services/notification_services.dart';

void main() {
  group('notification details by reminder type', () {
    test('uses alarm audio attributes and a dedicated Android channel', () {
      final details = NotificationService.notificationDetailsForReminderType(
        ReminderType.alarm,
      );

      expect(details.android?.channelId, 'task_alarm_alerts_v2');
      expect(details.android?.audioAttributesUsage, AudioAttributesUsage.alarm);
      expect(details.android?.importance, Importance.max);
      expect(details.android?.priority, Priority.max);
      expect(details.android?.playSound, isTrue);
      expect(details.iOS?.presentSound, isTrue);
      expect(details.iOS?.categoryIdentifier, 'TASK_ALARM');
    });

    test('preserves ordinary notification sound configuration', () {
      final details = NotificationService.notificationDetailsForReminderType(
        ReminderType.notification,
      );

      expect(details.android?.channelId, 'task_alarms');
      expect(
        details.android?.audioAttributesUsage,
        AudioAttributesUsage.notification,
      );
      expect(details.android?.importance, Importance.max);
      expect(details.android?.priority, Priority.max);
      expect(details.android?.playSound, isTrue);
      expect(details.iOS?.presentSound, isTrue);
      expect(details.iOS?.categoryIdentifier, isNull);
    });

    test('snoozes reminders for exactly five minutes', () {
      final currentTime = DateTime(2026, 10, 12, 9);

      expect(
        NotificationService.snoozedReminderDate(currentTime),
        currentTime.add(const Duration(minutes: 5)),
      );
    });

    test('finds the next daily reminder without scheduling in the past', () {
      expect(
        NotificationService.nextActivityReminderDate(
          DateTime(2026, 10, 14, 9),
          '09:30',
          ActivityPeriod.daily,
        ),
        DateTime(2026, 10, 14, 9, 30),
      );
      expect(
        NotificationService.nextActivityReminderDate(
          DateTime(2026, 10, 14, 10),
          '09:30',
          ActivityPeriod.daily,
        ),
        DateTime(2026, 10, 15, 9, 30),
      );
    });

    test('weekly reminders recur on Monday at the configured time', () {
      expect(
        NotificationService.nextActivityReminderDate(
          DateTime(2026, 10, 14, 10),
          '08:30',
          ActivityPeriod.weekly,
        ),
        DateTime(2026, 10, 19, 8, 30),
      );
      expect(
        NotificationService.nextActivityReminderDate(
          DateTime(2026, 10, 19, 10),
          '08:30',
          ActivityPeriod.weekly,
        ),
        DateTime(2026, 10, 26, 8, 30),
      );
    });
  });

  test('keeps reminder IDs stable while scheduling and cancelling', () async {
    final database = _MemoryTaskDatabase();
    final scheduler = _FakeTaskReminderScheduler();
    final container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWith((ref) => TaskRepository(database)),
        taskReminderSchedulerProvider.overrideWith((ref) => scheduler),
      ],
    );
    addTearDown(container.dispose);
    await container.read(taskProvider.future);

    final notifier = container.read(taskProvider.notifier);
    await notifier.addTask(
      title: 'Prepare presentation',
      startDate: DateTime(2026, 10, 8),
      reminderEnabled: true,
      reminderDate: DateTime.now().add(const Duration(hours: 1)),
      reminderType: ReminderType.alarm,
    );

    var task = database.tasks.single;
    final notificationId = task.notificationId;
    expect(notificationId, isPositive);
    expect(scheduler.scheduled.single.taskId, notificationId);
    expect(scheduler.scheduled.single.reminderType, ReminderType.alarm);

    await notifier.updateTask(
      task.copyWith(
        title: 'Prepare the presentation',
        reminderDate: DateTime.now().add(const Duration(hours: 2)),
      ),
    );
    task = database.tasks.single;
    expect(task.notificationId, notificationId);
    expect(scheduler.cancelled, contains(notificationId));
    expect(scheduler.scheduled, hasLength(2));

    await notifier.setTaskStatus(task, TaskStatus.completed);
    expect(database.tasks.single.status, TaskStatus.completed);
    expect(scheduler.cancelled.last, notificationId);

    await notifier.setTaskStatus(
      database.tasks.single,
      TaskStatus.inProgress,
      reminderEnabled: true,
      reminderDate: DateTime.now().add(const Duration(hours: 3)),
    );
    expect(database.tasks.single.status, TaskStatus.inProgress);
    expect(scheduler.scheduled.last.taskId, notificationId);

    await notifier.removeTask(task.id);
    expect(scheduler.cancelled.last, notificationId);
    expect(database.tasks, isEmpty);
  });

  test(
    'does not save a reminder when notification permission is denied',
    () async {
      final database = _MemoryTaskDatabase();
      final scheduler = _FakeTaskReminderScheduler()
        ..notificationPermissionGranted = false;
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWith(
            (ref) => TaskRepository(database),
          ),
          taskReminderSchedulerProvider.overrideWith((ref) => scheduler),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskProvider.future);

      await expectLater(
        container
            .read(taskProvider.notifier)
            .addTask(
              title: 'Permission test',
              startDate: DateTime(2026, 10, 8),
              reminderEnabled: true,
              reminderDate: DateTime.now().add(const Duration(hours: 1)),
            ),
        throwsA(isA<NotificationPermissionDeniedException>()),
      );
      expect(database.tasks, isEmpty);
    },
  );

  test(
    'does not save a reminder when exact alarm permission is denied',
    () async {
      final database = _MemoryTaskDatabase();
      final scheduler = _FakeTaskReminderScheduler()
        ..exactAlarmPermissionGranted = false;
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWith(
            (ref) => TaskRepository(database),
          ),
          taskReminderSchedulerProvider.overrideWith((ref) => scheduler),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskProvider.future);

      await expectLater(
        container
            .read(taskProvider.notifier)
            .addTask(
              title: 'Exact alarm test',
              startDate: DateTime(2026, 10, 8),
              reminderEnabled: true,
              reminderDate: DateTime.now().add(const Duration(hours: 1)),
            ),
        throwsA(isA<ExactAlarmPermissionDeniedException>()),
      );
      expect(scheduler.scheduled, isEmpty);
      expect(database.tasks, isEmpty);
    },
  );

  test(
    'status changes schedule reminders and completion cancels them',
    () async {
      final database = _MemoryTaskDatabase();
      final scheduler = _FakeTaskReminderScheduler();
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWith(
            (ref) => TaskRepository(database),
          ),
          taskReminderSchedulerProvider.overrideWith((ref) => scheduler),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskProvider.future);

      final notifier = container.read(taskProvider.notifier);
      await notifier.addTask(
        title: 'Status test',
        description: 'Review the draft',
        startDate: DateTime(2026, 10, 8),
      );
      var task = database.tasks.single;

      await notifier.setTaskStatus(
        task,
        TaskStatus.onHold,
        reminderEnabled: true,
        reminderDate: DateTime.now().add(const Duration(hours: 1)),
      );
      task = database.tasks.single;
      expect(task.status, TaskStatus.onHold);
      expect(scheduler.scheduled.single.title, 'Status test');
      expect(scheduler.scheduled.single.description, 'Review the draft');

      await notifier.setTaskStatus(task, TaskStatus.completed);
      expect(database.tasks.single.status, TaskStatus.completed);
      expect(database.tasks.single.hasReminder, isFalse);
      expect(scheduler.cancelled, contains(task.reminderNotificationId));
    },
  );

  test('subtasks block parent completion and manage reminders', () async {
    final database = _MemoryTaskDatabase();
    final scheduler = _FakeTaskReminderScheduler();
    final container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWith((ref) => TaskRepository(database)),
        taskReminderSchedulerProvider.overrideWith((ref) => scheduler),
      ],
    );
    addTearDown(container.dispose);
    await container.read(taskProvider.future);

    final notifier = container.read(taskProvider.notifier);
    await notifier.addTask(
      title: 'Prepare release',
      startDate: DateTime(2026, 10, 8),
    );
    final parent = database.tasks.single;
    await notifier.addSubtask(
      parentTask: parent,
      title: 'Review release notes',
      reminderEnabled: true,
      reminderDate: DateTime.now().add(const Duration(hours: 1)),
    );
    final subtask = database.subtasks.single;
    expect(subtask.notificationId, isNot(parent.reminderNotificationId));
    expect(scheduler.scheduled.single.taskId, subtask.reminderNotificationId);

    final updatedReminderDate = DateTime.now().add(const Duration(hours: 2));
    await notifier.updateSubtask(
      subtask.copyWith(reminderDate: updatedReminderDate),
    );
    expect(scheduler.scheduled, hasLength(2));
    expect(scheduler.scheduled.last.reminderDate, updatedReminderDate);
    expect(scheduler.cancelled, contains(subtask.reminderNotificationId));

    await expectLater(
      notifier.updateTask(parent.copyWith(status: TaskStatus.completed)),
      throwsA(isA<IncompleteSubtasksException>()),
    );
    await expectLater(
      notifier.setTaskStatus(parent, TaskStatus.completed),
      throwsA(isA<IncompleteSubtasksException>()),
    );
    expect(database.tasks.single.status, TaskStatus.inProgress);

    await notifier.updateSubtask(
      subtask.copyWith(status: SubtaskStatus.completed),
    );
    expect(scheduler.cancelled, contains(subtask.reminderNotificationId));
    await notifier.setTaskStatus(database.tasks.single, TaskStatus.completed);
    expect(database.tasks.single.status, TaskStatus.completed);

    await expectLater(
      notifier.addSubtask(parentTask: database.tasks.single, title: 'Publish'),
      throwsA(isA<ParentTaskReopenRequiredException>()),
    );
    await notifier.addSubtask(
      parentTask: database.tasks.single,
      title: 'Publish',
      reopenCompletedParent: true,
    );
    expect(database.tasks.single.status, TaskStatus.inProgress);
    expect(database.subtasks, hasLength(2));

    await notifier.addSubtask(
      parentTask: database.tasks.single,
      title: 'Publish release',
      reminderEnabled: true,
      reminderDate: DateTime.now().add(const Duration(hours: 3)),
    );
    final activeReminderId = database.subtasks.last.reminderNotificationId;
    await notifier.removeTask(parent.id);
    expect(scheduler.cancelled, contains(activeReminderId));
    expect(database.subtasks, isEmpty);
  });

  test(
    'pin and ordering updates persist without rescheduling reminders',
    () async {
      final database = _MemoryTaskDatabase();
      final scheduler = _FakeTaskReminderScheduler();
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWith(
            (ref) => TaskRepository(database),
          ),
          taskReminderSchedulerProvider.overrideWith((ref) => scheduler),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskProvider.future);

      final notifier = container.read(taskProvider.notifier);
      await notifier.addTask(
        title: 'First',
        startDate: DateTime(2026, 10, 8),
        priority: 'High',
      );
      await notifier.addTask(
        title: 'Second',
        startDate: DateTime(2026, 10, 8),
        priority: 'Low',
      );
      final first = database.tasks.firstWhere((task) => task.title == 'First');
      final second = database.tasks.firstWhere(
        (task) => task.title == 'Second',
      );

      await notifier.setTaskPinned(first, true);
      await notifier.saveTaskOrder([
        second,
        first.copyWith(priority: 'Medium'),
      ]);

      expect(
        database.tasks.firstWhere((task) => task.id == first.id).isPinned,
        isTrue,
      );
      expect(
        database.tasks.firstWhere((task) => task.id == first.id).priority,
        'Medium',
      );
      expect(
        database.tasks.firstWhere((task) => task.id == second.id).sortOrder,
        0,
      );
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelled, isEmpty);
    },
  );

  test(
    'habit reminders use stable separate IDs and archive cancellation',
    () async {
      final database = _MemoryTaskDatabase();
      final scheduler = _FakeActivityReminderScheduler();
      final container = ProviderContainer(
        overrides: [
          activityRepositoryProvider.overrideWith(
            (ref) => ActivityRepository(database),
          ),
          activityReminderSchedulerProvider.overrideWith((ref) => scheduler),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activityProvider.future);

      final notifier = container.read(activityProvider.notifier);
      final scheduled = await notifier.saveHabit(
        title: 'Read',
        description: '',
        period: ActivityPeriod.daily,
        targetCount: 1,
        reminderTime: '08:30',
      );
      final habit = database.habits.single;

      expect(scheduled, isTrue);
      expect(habit.reminderNotificationId, isNegative);
      expect(
        scheduler.scheduled.single.reminderId,
        habit.reminderNotificationId,
      );
      await notifier.archiveHabit(habit, true);
      expect(scheduler.cancelled, contains(habit.reminderNotificationId));
      expect(database.habits.single.archived, isTrue);
    },
  );

  test(
    'unsupported activity reminders do not block habit persistence',
    () async {
      final database = _MemoryTaskDatabase();
      final scheduler = _FakeActivityReminderScheduler()..supports = false;
      final container = ProviderContainer(
        overrides: [
          activityRepositoryProvider.overrideWith(
            (ref) => ActivityRepository(database),
          ),
          activityReminderSchedulerProvider.overrideWith((ref) => scheduler),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activityProvider.future);

      final scheduled = await container
          .read(activityProvider.notifier)
          .saveHabit(
            title: 'Stretch',
            description: '',
            period: ActivityPeriod.weekly,
            targetCount: 3,
            reminderTime: '09:00',
          );

      expect(scheduled, isFalse);
      expect(database.habits.single.title, 'Stretch');
    },
  );
}

class _ScheduledReminder {
  const _ScheduledReminder({
    required this.taskId,
    required this.reminderDate,
    required this.reminderType,
    required this.title,
    required this.description,
  });

  final int taskId;
  final DateTime reminderDate;
  final String reminderType;
  final String title;
  final String description;
}

class _FakeTaskReminderScheduler implements TaskReminderScheduler {
  final List<_ScheduledReminder> scheduled = [];
  final List<int> cancelled = [];
  bool notificationPermissionGranted = true;
  bool exactAlarmPermissionGranted = true;

  @override
  Future<bool> requestPermissions() async => notificationPermissionGranted;

  @override
  Future<bool> requestExactAlarmPermission() async =>
      exactAlarmPermissionGranted;

  @override
  Future<void> scheduleTaskReminder({
    required int taskId,
    required String title,
    required String description,
    required DateTime reminderDate,
    required String reminderType,
  }) async {
    scheduled.add(
      _ScheduledReminder(
        taskId: taskId,
        reminderDate: reminderDate,
        reminderType: reminderType,
        title: title,
        description: description,
      ),
    );
  }

  @override
  Future<void> cancelTaskReminder(int taskId) async {
    cancelled.add(taskId);
  }
}

class _ScheduledActivityReminder {
  const _ScheduledActivityReminder({
    required this.reminderId,
    required this.title,
    required this.time,
    required this.period,
  });

  final int reminderId;
  final String title;
  final String time;
  final ActivityPeriod period;
}

class _FakeActivityReminderScheduler implements ActivityReminderScheduler {
  final List<_ScheduledActivityReminder> scheduled = [];
  final List<int> cancelled = [];
  bool supports = true;

  @override
  bool get supportsActivityReminders => supports;

  @override
  Future<void> scheduleActivityReminder({
    required int reminderId,
    required String title,
    required String time,
    required ActivityPeriod period,
  }) async {
    scheduled.add(
      _ScheduledActivityReminder(
        reminderId: reminderId,
        title: title,
        time: time,
        period: period,
      ),
    );
  }

  @override
  Future<void> cancelActivityReminder(int reminderId) async {
    cancelled.add(reminderId);
  }
}

class _MemoryTaskDatabase extends TaskDatabase {
  final List<Task> tasks = [];
  final List<Subtask> subtasks = [];
  final List<Habit> habits = [];

  @override
  Future<List<Task>> getTasks() async => List.of(tasks);

  @override
  Future<List<Subtask>> getSubtasks(String parentTaskId) async => subtasks
      .where((subtask) => subtask.parentTaskId == parentTaskId)
      .toList();

  @override
  Future<List<Subtask>> getAllSubtasks() async => List.of(subtasks);

  @override
  Future<void> saveTask(Task task) async {
    tasks.removeWhere((savedTask) => savedTask.id == task.id);
    tasks.add(task);
  }

  @override
  Future<void> saveTasks(List<Task> updatedTasks) async {
    for (final task in updatedTasks) {
      await saveTask(task);
    }
  }

  @override
  Future<void> saveSubtask(Subtask subtask) async {
    subtasks.removeWhere((savedSubtask) => savedSubtask.id == subtask.id);
    subtasks.add(subtask);
  }

  @override
  Future<void> saveTaskAndSubtask(Task task, Subtask subtask) async {
    await saveTask(task);
    await saveSubtask(subtask);
  }

  @override
  Future<void> deleteSubtask(String id) async {
    subtasks.removeWhere((subtask) => subtask.id == id);
  }

  @override
  Future<void> deleteTask(String id) async {
    tasks.removeWhere((task) => task.id == id);
    subtasks.removeWhere((subtask) => subtask.parentTaskId == id);
  }

  @override
  Future<List<Habit>> getHabits() async => List.of(habits);

  @override
  Future<void> saveHabit(Habit habit) async {
    habits.removeWhere((saved) => saved.id == habit.id);
    habits.add(habit);
  }

  @override
  Future<List<HabitCheckIn>> getHabitCheckIns({
    String? startDay,
    String? endDay,
  }) async => [];

  @override
  Future<List<ActivitySession>> getActivitySessions({
    String? startDay,
    String? endDay,
  }) async => [];

  @override
  Future<List<Routine>> getRoutines() async => [];

  @override
  Future<List<RoutineStep>> getRoutineSteps() async => [];

  @override
  Future<List<RoutineStepCheckIn>> getRoutineStepCheckIns({
    String? startDay,
    String? endDay,
  }) async => [];

  @override
  Future<List<ActivityGoal>> getActivityGoals() async => [];
}
