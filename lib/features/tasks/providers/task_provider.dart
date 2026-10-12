import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/datasources/task_database.dart';
import '../../../data/models/task.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../services/notification_services.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(TaskDatabase());
});

final taskReminderSchedulerProvider = Provider<TaskReminderScheduler>((ref) {
  return NotificationService.instance;
});

final taskProvider = AsyncNotifierProvider<TaskNotifier, List<Task>>(
  TaskNotifier.new,
);

class TaskNotifier extends AsyncNotifier<List<Task>> {
  static final Random _random = Random.secure();

  late final TaskRepository _repository;
  late final TaskReminderScheduler _reminderScheduler;

  @override
  Future<List<Task>> build() async {
    _repository = ref.read(taskRepositoryProvider);
    _reminderScheduler = ref.read(taskReminderSchedulerProvider);
    return _repository.getTasks();
  }

  Future<void> addTask({
    required String title,
    String description = '',
    String category = 'Personal',
    String priority = 'Medium',
    required DateTime startDate,
    DateTime? dueDate,
    bool reminderEnabled = false,
    DateTime? reminderDate,
    String reminderType = ReminderType.alarm,
    TaskStatus status = TaskStatus.inProgress,
  }) async {
    final existingTasks = await _repository.getTasks();
    final task = Task(
      id: const Uuid().v4(),
      title: title,
      description: description,
      category: category,
      priority: priority,
      startDate: startDate,
      dueDate: dueDate,
      status: status,
      reminderEnabled: reminderEnabled,
      reminderDate: reminderDate,
      reminderType: reminderType,
      notificationId: _createNotificationId(existingTasks),
    );

    var scheduled = false;
    try {
      await _scheduleReminderIfNeeded(task);
      scheduled = task.hasReminder && task.status != TaskStatus.completed;
      await _repository.saveTask(task);
    } catch (_) {
      if (scheduled) {
        await _reminderScheduler.cancelTaskReminder(
          task.reminderNotificationId,
        );
      }
      rethrow;
    }

    state = AsyncData(await _repository.getTasks());
  }

  Future<void> updateTask(Task task) async {
    final tasks = await _repository.getTasks();
    final currentTask = tasks.firstWhere(
      (savedTask) => savedTask.id == task.id,
      orElse: () => task,
    );
    final notificationId =
        task.notificationId ??
        currentTask.notificationId ??
        currentTask.reminderNotificationId;
    final updatedTask = task.copyWith(
      notificationId: notificationId,
      clearReminder: task.status == TaskStatus.completed,
    );

    await _requireReminderPermissions(updatedTask);
    if (currentTask.hasReminder) {
      await _reminderScheduler.cancelTaskReminder(
        currentTask.reminderNotificationId,
      );
    }

    var scheduled = false;
    try {
      await _scheduleReminderIfNeeded(updatedTask, requestPermissions: false);
      scheduled =
          updatedTask.hasReminder && updatedTask.status != TaskStatus.completed;
      await _repository.saveTask(updatedTask);
    } catch (_) {
      if (scheduled) {
        await _reminderScheduler.cancelTaskReminder(
          updatedTask.reminderNotificationId,
        );
      }
      if (currentTask.hasReminder &&
          currentTask.status != TaskStatus.completed) {
        try {
          await _scheduleReminderIfNeeded(currentTask);
        } catch (_) {
          // Keep the original update error; the task can be retried in the UI.
        }
      }
      rethrow;
    }

    state = AsyncData(await _repository.getTasks());
  }

  Future<void> setTaskStatus(
    Task task,
    TaskStatus status, {
    bool reminderEnabled = false,
    DateTime? reminderDate,
  }) async {
    final updatedTask = task.copyWith(
      status: status,
      notificationId: task.notificationId ?? task.reminderNotificationId,
      reminderEnabled: reminderEnabled,
      reminderDate: reminderDate,
      clearReminder:
          status == TaskStatus.completed ||
          (!reminderEnabled && reminderDate == null),
      reminderType: ReminderType.alarm,
    );

    if (task.hasReminder) {
      await _reminderScheduler.cancelTaskReminder(task.reminderNotificationId);
    }

    var scheduled = false;
    try {
      await _scheduleReminderIfNeeded(updatedTask);
      scheduled =
          updatedTask.hasReminder && updatedTask.status != TaskStatus.completed;
      await _repository.saveTask(updatedTask);
    } catch (_) {
      if (scheduled) {
        await _reminderScheduler.cancelTaskReminder(
          updatedTask.reminderNotificationId,
        );
      }
      if (task.hasReminder && task.status != TaskStatus.completed) {
        try {
          await _scheduleReminderIfNeeded(task);
        } catch (_) {
          // Keep the original update error; the task can be retried in the UI.
        }
      }
      rethrow;
    }

    state = AsyncData(await _repository.getTasks());
  }

  Future<void> removeTask(String id) async {
    final tasks = await _repository.getTasks();
    final task = tasks.where((savedTask) => savedTask.id == id).firstOrNull;
    if (task != null && task.hasReminder) {
      await _reminderScheduler.cancelTaskReminder(task.reminderNotificationId);
    }
    await _repository.deleteTask(id);
    state = AsyncData(await _repository.getTasks());
  }

  int _createNotificationId(List<Task> tasks) {
    final usedIds = tasks
        .map((task) => task.notificationId ?? task.reminderNotificationId)
        .toSet();
    var notificationId = 0;
    do {
      notificationId = _random.nextInt(0x7ffffffe) + 1;
    } while (usedIds.contains(notificationId));
    return notificationId;
  }

  Future<void> _requireReminderPermissions(Task task) async {
    if (!task.hasReminder || task.status == TaskStatus.completed) return;
    final reminderDate = task.reminderDate!;
    if (!reminderDate.isAfter(DateTime.now())) {
      throw ReminderTimeInPastException();
    }
    if (!await _reminderScheduler.requestPermissions()) {
      throw NotificationPermissionDeniedException();
    }
    if (!await _reminderScheduler.requestExactAlarmPermission()) {
      throw ExactAlarmPermissionDeniedException();
    }
  }

  Future<void> _scheduleReminderIfNeeded(
    Task task, {
    bool requestPermissions = true,
  }) async {
    if (!task.hasReminder || task.status == TaskStatus.completed) return;
    if (requestPermissions) await _requireReminderPermissions(task);
    await _reminderScheduler.scheduleTaskReminder(
      taskId: task.reminderNotificationId,
      title: task.title,
      description: task.description,
      reminderDate: task.reminderDate!,
      reminderType: task.reminderType,
    );
  }
}
