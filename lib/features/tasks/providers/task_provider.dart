import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/datasources/task_database.dart';
import '../../../data/models/subtask.dart';
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

final subtasksProvider = FutureProvider.family<List<Subtask>, String>((
  ref,
  id,
) {
  return ref.watch(taskRepositoryProvider).getSubtasks(id);
});

class IncompleteSubtasksException implements Exception {
  const IncompleteSubtasksException(this.remainingCount);

  final int remainingCount;
}

class ParentTaskReopenRequiredException implements Exception {}

class ReminderDateRequiredException implements Exception {}

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
    final existingSubtasks = await _repository.getAllSubtasks();
    final task = Task(
      id: const Uuid().v4(),
      title: title,
      description: description,
      category: category,
      priority: priority,
      sortOrder:
          existingTasks
              .where((task) => task.priority == priority)
              .fold(-1, (highest, task) => max(highest, task.sortOrder)) +
          1,
      createdAt: DateTime.now(),
      startDate: startDate,
      dueDate: dueDate,
      status: status,
      reminderEnabled: reminderEnabled,
      reminderDate: reminderDate,
      reminderType: reminderType,
      notificationId: _createNotificationId(existingTasks, existingSubtasks),
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
      isPinned: currentTask.isPinned,
      sortOrder: currentTask.sortOrder,
      createdAt: currentTask.createdAt,
      notificationId: notificationId,
      clearReminder: task.status == TaskStatus.completed,
    );
    if (updatedTask.status == TaskStatus.completed) {
      final subtasks = await _repository.getSubtasks(updatedTask.id);
      final remaining = subtasks
          .where((subtask) => !subtask.isCompleted)
          .length;
      if (remaining > 0) throw IncompleteSubtasksException(remaining);
    }

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
    if (status == TaskStatus.completed) {
      final subtasks = await _repository.getSubtasks(task.id);
      final remaining = subtasks
          .where((subtask) => !subtask.isCompleted)
          .length;
      if (remaining > 0) throw IncompleteSubtasksException(remaining);
    }

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
    final subtasks = await _repository.getSubtasks(id);
    for (final subtask in subtasks.where((item) => item.hasReminder)) {
      await _reminderScheduler.cancelTaskReminder(
        subtask.reminderNotificationId,
      );
    }
    if (task != null && task.hasReminder) {
      await _reminderScheduler.cancelTaskReminder(task.reminderNotificationId);
    }
    await _repository.deleteTask(id);
    state = AsyncData(await _repository.getTasks());
  }

  Future<void> setTaskPinned(Task task, bool isPinned) async {
    final currentTasks = await _repository.getTasks();
    final currentTask = currentTasks.firstWhere(
      (savedTask) => savedTask.id == task.id,
      orElse: () => task,
    );
    await _repository.saveTask(currentTask.copyWith(isPinned: isPinned));
    state = AsyncData(await _repository.getTasks());
  }

  Future<void> saveTaskOrder(List<Task> orderedTasks) async {
    final currentTasks = await _repository.getTasks();
    final currentById = {for (final task in currentTasks) task.id: task};
    final updates = [
      for (var index = 0; index < orderedTasks.length; index++)
        currentById[orderedTasks[index].id]!.copyWith(
          priority: orderedTasks[index].priority,
          sortOrder: index,
        ),
    ];
    await _repository.saveTasks(updates);
    state = AsyncData(await _repository.getTasks());
  }

  Future<void> addSubtask({
    required Task parentTask,
    required String title,
    String description = '',
    String status = SubtaskStatus.pending,
    DateTime? dueDate,
    bool reminderEnabled = false,
    DateTime? reminderDate,
    String reminderType = ReminderType.notification,
    bool reopenCompletedParent = false,
  }) async {
    final tasks = await _repository.getTasks();
    final savedParent = tasks.firstWhere((task) => task.id == parentTask.id);
    final parentUpdate = _parentAfterSubtaskChange(
      savedParent,
      status,
      reopenCompletedParent,
    );
    final subtasks = await _repository.getAllSubtasks();
    final siblings = subtasks
        .where((subtask) => subtask.parentTaskId == parentTask.id)
        .toList();
    final subtask = Subtask(
      id: const Uuid().v4(),
      parentTaskId: parentTask.id,
      title: title,
      description: description,
      status: status,
      dueDate: dueDate,
      reminderEnabled: reminderEnabled,
      reminderDate: reminderDate,
      reminderType: reminderType,
      notificationId: _createNotificationId(tasks, subtasks),
      sortOrder: siblings.length,
    );

    var scheduled = false;
    try {
      await _scheduleSubtaskReminderIfNeeded(subtask);
      scheduled = subtask.hasReminder;
      if (parentUpdate == null) {
        await _repository.saveSubtask(subtask);
      } else {
        await _repository.saveTaskAndSubtask(parentUpdate, subtask);
      }
    } catch (_) {
      if (scheduled) {
        await _reminderScheduler.cancelTaskReminder(
          subtask.reminderNotificationId,
        );
      }
      rethrow;
    }

    state = AsyncData(await _repository.getTasks());
    ref.invalidate(subtasksProvider(parentTask.id));
  }

  Future<void> updateSubtask(
    Subtask subtask, {
    bool reopenCompletedParent = false,
  }) async {
    final siblings = await _repository.getSubtasks(subtask.parentTaskId);
    final current = siblings.firstWhere((item) => item.id == subtask.id);
    final tasks = await _repository.getTasks();
    final parent = tasks.firstWhere((task) => task.id == subtask.parentTaskId);
    final parentUpdate = _parentAfterSubtaskChange(
      parent,
      subtask.status,
      reopenCompletedParent,
    );
    final notificationId =
        subtask.notificationId ??
        current.notificationId ??
        current.reminderNotificationId;
    final updated = subtask.copyWith(
      notificationId: notificationId,
      clearReminder: subtask.status == SubtaskStatus.completed,
    );

    if (current.hasReminder) {
      await _reminderScheduler.cancelTaskReminder(
        current.reminderNotificationId,
      );
    }

    var scheduled = false;
    try {
      await _scheduleSubtaskReminderIfNeeded(updated);
      scheduled = updated.hasReminder;
      if (parentUpdate == null) {
        await _repository.saveSubtask(updated);
      } else {
        await _repository.saveTaskAndSubtask(parentUpdate, updated);
      }
    } catch (_) {
      if (scheduled) {
        await _reminderScheduler.cancelTaskReminder(
          updated.reminderNotificationId,
        );
      }
      if (current.hasReminder) {
        try {
          await _scheduleSubtaskReminderIfNeeded(current);
        } catch (_) {}
      }
      rethrow;
    }

    state = AsyncData(await _repository.getTasks());
    ref.invalidate(subtasksProvider(subtask.parentTaskId));
  }

  Future<void> removeSubtask(Subtask subtask) async {
    if (subtask.hasReminder) {
      await _reminderScheduler.cancelTaskReminder(
        subtask.reminderNotificationId,
      );
    }
    await _repository.deleteSubtask(subtask.id);
    ref.invalidate(subtasksProvider(subtask.parentTaskId));
  }

  Task? _parentAfterSubtaskChange(
    Task parent,
    String subtaskStatus,
    bool reopenCompletedParent,
  ) {
    if (parent.status != TaskStatus.completed ||
        subtaskStatus == SubtaskStatus.completed) {
      return null;
    }
    if (!reopenCompletedParent) throw ParentTaskReopenRequiredException();
    return parent.copyWith(status: TaskStatus.inProgress, clearReminder: true);
  }

  int _createNotificationId(List<Task> tasks, List<Subtask> subtasks) {
    final usedIds = {
      ...tasks.map((task) => task.reminderNotificationId),
      ...subtasks.map((subtask) => subtask.reminderNotificationId),
    };
    var notificationId = 0;
    do {
      notificationId = _random.nextInt(0x7ffffffe) + 1;
    } while (usedIds.contains(notificationId));
    return notificationId;
  }

  Future<void> _requireReminderPermissions(Task task) async {
    if (task.reminderEnabled && task.reminderDate == null) {
      throw ReminderDateRequiredException();
    }
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
    if (task.reminderEnabled && task.reminderDate == null) {
      throw ReminderDateRequiredException();
    }
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

  Future<void> _scheduleSubtaskReminderIfNeeded(Subtask subtask) async {
    if (subtask.reminderEnabled && subtask.reminderDate == null) {
      throw ReminderDateRequiredException();
    }
    if (!subtask.hasReminder || subtask.isCompleted) return;
    final reminderDate = subtask.reminderDate!;
    if (!reminderDate.isAfter(DateTime.now())) {
      throw ReminderTimeInPastException();
    }
    if (!await _reminderScheduler.requestPermissions()) {
      throw NotificationPermissionDeniedException();
    }
    if (!await _reminderScheduler.requestExactAlarmPermission()) {
      throw ExactAlarmPermissionDeniedException();
    }
    await _reminderScheduler.scheduleTaskReminder(
      taskId: subtask.reminderNotificationId,
      title: subtask.title,
      description: subtask.description,
      reminderDate: reminderDate,
      reminderType: subtask.reminderType,
    );
  }
}
