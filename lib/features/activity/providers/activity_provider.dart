import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/datasources/task_database.dart';
import '../../../data/models/activity.dart';
import '../../../data/repositories/activity_repository.dart';
import '../../../services/notification_services.dart';

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return ActivityRepository(TaskDatabase());
});

final activityProvider =
    AsyncNotifierProvider<ActivityNotifier, ActivitySnapshot>(
      ActivityNotifier.new,
    );

final activityReminderSchedulerProvider = Provider<ActivityReminderScheduler>(
  (ref) => NotificationService.instance,
);

class ActivityNotifier extends AsyncNotifier<ActivitySnapshot> {
  late final ActivityRepository _repository;
  late final ActivityReminderScheduler _reminderScheduler;

  @override
  Future<ActivitySnapshot> build() {
    _repository = ref.read(activityRepositoryProvider);
    _reminderScheduler = ref.read(activityReminderSchedulerProvider);
    return _repository.loadSnapshot();
  }

  Future<bool> saveHabit({
    String? id,
    required String title,
    required String description,
    required ActivityPeriod period,
    required int targetCount,
    String? reminderTime,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const FormatException('Enter a habit name.');
    }
    if (targetCount < 1) {
      throw const FormatException('The target must be at least 1.');
    }
    final current = id == null
        ? null
        : state.asData?.value.habits
              .where((habit) => habit.id == id)
              .firstOrNull;
    final habitId = id ?? const Uuid().v4();
    final reminderId =
        current?.reminderNotificationId ??
        (reminderTime == null ? null : _notificationIdFor(habitId));
    if (current?.reminderTime != null &&
        current!.reminderTime != reminderTime &&
        current.reminderNotificationId != null) {
      try {
        await _reminderScheduler.cancelActivityReminder(
          current.reminderNotificationId!,
        );
      } catch (_) {}
    }
    var reminderScheduled = reminderTime == null;
    if (reminderTime != null && _reminderScheduler.supportsActivityReminders) {
      try {
        await _reminderScheduler.scheduleActivityReminder(
          reminderId: reminderId!,
          title: normalizedTitle,
          time: reminderTime,
          period: period,
        );
        reminderScheduled = true;
      } catch (_) {
        reminderScheduled = false;
      }
    }
    await _repository.saveHabit(
      Habit(
        id: habitId,
        title: normalizedTitle,
        description: description.trim(),
        period: period,
        targetCount: targetCount,
        createdAt: current?.createdAt ?? DateTime.now(),
        archived: current?.archived ?? false,
        reminderTime: reminderTime,
        reminderNotificationId: reminderId,
      ),
    );
    await _reload();
    return reminderScheduled;
  }

  Future<void> archiveHabit(Habit habit, bool archived) async {
    final reminderId = habit.reminderNotificationId;
    if (archived && reminderId != null) {
      try {
        await _reminderScheduler.cancelActivityReminder(reminderId);
      } catch (_) {}
    } else if (!archived && habit.reminderTime != null && reminderId != null) {
      if (_reminderScheduler.supportsActivityReminders) {
        try {
          await _reminderScheduler.scheduleActivityReminder(
            reminderId: reminderId,
            title: habit.title,
            time: habit.reminderTime!,
            period: habit.period,
          );
        } catch (_) {}
      }
    }
    await _repository.saveHabit(habit.copyWith(archived: archived));
    await _reload();
  }

  Future<void> recordHabit({
    required Habit habit,
    required ActivityStatus status,
    required DateTime day,
    double? value,
    int? durationMinutes,
  }) async {
    if (value != null && value < 0) {
      throw const FormatException('Value cannot be negative.');
    }
    if (durationMinutes != null && durationMinutes < 0) {
      throw const FormatException('Duration cannot be negative.');
    }
    final now = DateTime.now();
    final completedAt = DateTime(
      day.year,
      day.month,
      day.day,
      now.hour,
      now.minute,
      now.second,
    );
    await _repository.saveHabitCheckIn(
      HabitCheckIn(
        id: const Uuid().v4(),
        habitId: habit.id,
        dayKey: activityDayKey(day),
        status: status,
        completedAt: completedAt,
        value: value,
        durationMinutes: durationMinutes,
      ),
    );
    await _reload();
  }

  Future<void> logSession({
    String? id,
    required ActivityCategory category,
    required String title,
    required DateTime startedAt,
    required int durationMinutes,
    double? distanceKm,
    int? calories,
    int? pages,
    int? words,
    ActivityStatus status = ActivityStatus.completed,
  }) async {
    if (title.trim().isEmpty) throw const FormatException('Enter a title.');
    if (durationMinutes < 0) {
      throw const FormatException('Duration cannot be negative.');
    }
    if (distanceKm != null && distanceKm < 0 ||
        calories != null && calories < 0 ||
        pages != null && pages < 0 ||
        words != null && words < 0) {
      throw const FormatException('Activity values cannot be negative.');
    }
    await _repository.saveSession(
      ActivitySession(
        id: id ?? const Uuid().v4(),
        category: category,
        title: title.trim(),
        startedAt: startedAt,
        durationMinutes: durationMinutes,
        distanceKm: distanceKm,
        calories: calories,
        pages: pages,
        words: words,
        status: status,
      ),
    );
    await _reload();
  }

  Future<void> deleteSession(String id) async {
    await _repository.deleteSession(id);
    await _reload();
  }

  Future<void> createRoutine({
    required String title,
    required String period,
    required List<String> stepTitles,
  }) async {
    final normalizedTitle = title.trim();
    final steps = stepTitles.map((step) => step.trim()).toList();
    if (normalizedTitle.isEmpty) {
      throw const FormatException('Enter a routine name.');
    }
    if (steps.isEmpty || steps.any((step) => step.isEmpty)) {
      throw const FormatException('Add at least one non-empty routine step.');
    }
    final routineId = const Uuid().v4();
    final routine = Routine(
      id: routineId,
      title: normalizedTitle,
      period: period,
      createdAt: DateTime.now(),
    );
    final routineSteps = [
      for (var index = 0; index < steps.length; index++)
        RoutineStep(
          id: const Uuid().v4(),
          routineId: routineId,
          title: steps[index],
          sortOrder: index,
        ),
    ];
    await _repository.saveRoutine(routine, routineSteps);
    await _reload();
  }

  Future<void> setRoutineStepStatus({
    required RoutineStep step,
    required DateTime day,
    required ActivityStatus status,
    int? durationMinutes,
  }) async {
    if (durationMinutes != null && durationMinutes < 0) {
      throw const FormatException('Duration cannot be negative.');
    }
    await _repository.saveRoutineStepCheckIn(
      RoutineStepCheckIn(
        stepId: step.id,
        dayKey: activityDayKey(day),
        status: status,
        completedAt: status == ActivityStatus.completed ? DateTime.now() : null,
        durationMinutes: durationMinutes,
      ),
    );
    await _reload();
  }

  Future<void> saveGoal({
    String? id,
    required String category,
    required ActivityPeriod period,
    required int target,
    required String unit,
  }) async {
    if (target < 1) {
      throw const FormatException('The target must be at least 1.');
    }
    await _repository.saveGoal(
      ActivityGoal(
        id: id ?? const Uuid().v4(),
        category: category,
        period: period,
        target: target,
        unit: unit,
      ),
    );
    await _reload();
  }

  Future<void> _reload() async {
    state = AsyncData(await _repository.loadSnapshot());
  }

  int _notificationIdFor(String habitId) {
    var hash = 0x7fffffff;
    for (final codeUnit in habitId.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return -(hash == 0 ? 1 : hash);
  }
}
