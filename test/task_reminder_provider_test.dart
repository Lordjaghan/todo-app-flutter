import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:to_do_app/data/datasources/task_database.dart';
import 'package:to_do_app/data/models/subtask.dart';
import 'package:to_do_app/data/models/task.dart';
import 'package:to_do_app/data/repositories/task_repository.dart';
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

class _MemoryTaskDatabase extends TaskDatabase {
  final List<Task> tasks = [];
  final List<Subtask> subtasks = [];

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
}
