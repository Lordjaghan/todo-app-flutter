enum ActivityPeriod { daily, weekly }

enum ActivityCategory { cardio, reading, writing }

enum ActivityStatus { completed, skipped }

String activityDayKey(DateTime date) {
  final localDate = DateTime(date.year, date.month, date.day);
  return '${localDate.year.toString().padLeft(4, '0')}-'
      '${localDate.month.toString().padLeft(2, '0')}-'
      '${localDate.day.toString().padLeft(2, '0')}';
}

class Habit {
  const Habit({
    required this.id,
    required this.title,
    this.description = '',
    this.period = ActivityPeriod.daily,
    this.targetCount = 1,
    this.archived = false,
    required this.createdAt,
    this.reminderTime,
    this.reminderNotificationId,
  });

  final String id;
  final String title;
  final String description;
  final ActivityPeriod period;
  final int targetCount;
  final bool archived;
  final DateTime createdAt;
  final String? reminderTime;
  final int? reminderNotificationId;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'period': period.name,
    'targetCount': targetCount,
    'archived': archived ? 1 : 0,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'reminderTime': reminderTime,
    'reminderNotificationId': reminderNotificationId,
  };

  factory Habit.fromMap(Map<String, Object?> map) => Habit(
    id: map['id'] as String,
    title: map['title'] as String,
    description: map['description'] as String? ?? '',
    period: ActivityPeriod.values.firstWhere(
      (period) => period.name == map['period'],
      orElse: () => ActivityPeriod.daily,
    ),
    targetCount: map['targetCount'] as int? ?? 1,
    archived: (map['archived'] as int? ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
    reminderTime: map['reminderTime'] as String?,
    reminderNotificationId: map['reminderNotificationId'] as int?,
  );

  Habit copyWith({
    String? title,
    String? description,
    ActivityPeriod? period,
    int? targetCount,
    bool? archived,
    String? reminderTime,
    int? reminderNotificationId,
    bool clearReminderTime = false,
  }) => Habit(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    period: period ?? this.period,
    targetCount: targetCount ?? this.targetCount,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    reminderTime: clearReminderTime
        ? null
        : (reminderTime ?? this.reminderTime),
    reminderNotificationId:
        reminderNotificationId ?? this.reminderNotificationId,
  );
}

class HabitCheckIn {
  const HabitCheckIn({
    required this.id,
    required this.habitId,
    required this.dayKey,
    required this.status,
    required this.completedAt,
    this.value,
    this.durationMinutes,
  });

  final String id;
  final String habitId;
  final String dayKey;
  final ActivityStatus status;
  final DateTime completedAt;
  final double? value;
  final int? durationMinutes;

  Map<String, Object?> toMap() => {
    'id': id,
    'habitId': habitId,
    'dayKey': dayKey,
    'status': status.name,
    'value': value,
    'durationMinutes': durationMinutes,
    'completedAt': completedAt.millisecondsSinceEpoch,
  };

  factory HabitCheckIn.fromMap(Map<String, Object?> map) => HabitCheckIn(
    id: map['id'] as String,
    habitId: map['habitId'] as String,
    dayKey: map['dayKey'] as String,
    status: ActivityStatus.values.firstWhere(
      (status) => status.name == map['status'],
      orElse: () => ActivityStatus.completed,
    ),
    value: (map['value'] as num?)?.toDouble(),
    durationMinutes: map['durationMinutes'] as int?,
    completedAt: DateTime.fromMillisecondsSinceEpoch(map['completedAt'] as int),
  );
}

class ActivitySession {
  const ActivitySession({
    required this.id,
    required this.category,
    required this.title,
    required this.startedAt,
    required this.durationMinutes,
    this.distanceKm,
    this.calories,
    this.pages,
    this.words,
    this.status = ActivityStatus.completed,
  });

  final String id;
  final ActivityCategory category;
  final String title;
  final DateTime startedAt;
  final int durationMinutes;
  final double? distanceKm;
  final int? calories;
  final int? pages;
  final int? words;
  final ActivityStatus status;

  String get dayKey => activityDayKey(startedAt);

  Map<String, Object?> toMap() => {
    'id': id,
    'category': category.name,
    'title': title,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'dayKey': dayKey,
    'durationMinutes': durationMinutes,
    'distanceKm': distanceKm,
    'calories': calories,
    'pages': pages,
    'words': words,
    'status': status.name,
  };

  factory ActivitySession.fromMap(Map<String, Object?> map) => ActivitySession(
    id: map['id'] as String,
    category: ActivityCategory.values.firstWhere(
      (category) => category.name == map['category'],
      orElse: () => ActivityCategory.cardio,
    ),
    title: map['title'] as String,
    startedAt: DateTime.fromMillisecondsSinceEpoch(map['startedAt'] as int),
    durationMinutes: map['durationMinutes'] as int,
    distanceKm: (map['distanceKm'] as num?)?.toDouble(),
    calories: map['calories'] as int?,
    pages: map['pages'] as int?,
    words: map['words'] as int?,
    status: ActivityStatus.values.firstWhere(
      (status) => status.name == map['status'],
      orElse: () => ActivityStatus.completed,
    ),
  );
}

class Routine {
  const Routine({
    required this.id,
    required this.title,
    required this.period,
    required this.createdAt,
    this.archived = false,
  });

  final String id;
  final String title;
  final String period;
  final DateTime createdAt;
  final bool archived;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'period': period,
    'archived': archived ? 1 : 0,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory Routine.fromMap(Map<String, Object?> map) => Routine(
    id: map['id'] as String,
    title: map['title'] as String,
    period: map['period'] as String,
    archived: (map['archived'] as int? ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
  );
}

class RoutineStep {
  const RoutineStep({
    required this.id,
    required this.routineId,
    required this.title,
    required this.sortOrder,
  });

  final String id;
  final String routineId;
  final String title;
  final int sortOrder;

  Map<String, Object?> toMap() => {
    'id': id,
    'routineId': routineId,
    'title': title,
    'sortOrder': sortOrder,
  };

  factory RoutineStep.fromMap(Map<String, Object?> map) => RoutineStep(
    id: map['id'] as String,
    routineId: map['routineId'] as String,
    title: map['title'] as String,
    sortOrder: map['sortOrder'] as int,
  );
}

class RoutineStepCheckIn {
  const RoutineStepCheckIn({
    required this.stepId,
    required this.dayKey,
    required this.status,
    this.completedAt,
    this.durationMinutes,
  });

  final String stepId;
  final String dayKey;
  final ActivityStatus status;
  final DateTime? completedAt;
  final int? durationMinutes;

  Map<String, Object?> toMap() => {
    'stepId': stepId,
    'dayKey': dayKey,
    'status': status.name,
    'completedAt': completedAt?.millisecondsSinceEpoch,
    'durationMinutes': durationMinutes,
  };

  factory RoutineStepCheckIn.fromMap(Map<String, Object?> map) =>
      RoutineStepCheckIn(
        stepId: map['stepId'] as String,
        dayKey: map['dayKey'] as String,
        status: ActivityStatus.values.firstWhere(
          (status) => status.name == map['status'],
          orElse: () => ActivityStatus.completed,
        ),
        completedAt: map['completedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['completedAt'] as int),
        durationMinutes: map['durationMinutes'] as int?,
      );
}

class ActivityGoal {
  const ActivityGoal({
    required this.id,
    required this.category,
    required this.period,
    required this.target,
    required this.unit,
  });

  final String id;
  final String category;
  final ActivityPeriod period;
  final int target;
  final String unit;

  Map<String, Object?> toMap() => {
    'id': id,
    'category': category,
    'period': period.name,
    'target': target,
    'unit': unit,
  };

  factory ActivityGoal.fromMap(Map<String, Object?> map) => ActivityGoal(
    id: map['id'] as String,
    category: map['category'] as String,
    period: ActivityPeriod.values.firstWhere(
      (period) => period.name == map['period'],
      orElse: () => ActivityPeriod.daily,
    ),
    target: map['target'] as int,
    unit: map['unit'] as String,
  );
}
