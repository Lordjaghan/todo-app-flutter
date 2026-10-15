import '../../../data/models/activity.dart';
import '../../../data/repositories/activity_repository.dart';

enum ReportRange { daily, weekly, monthly }

enum ReportMeasure { activeMinutes, completedHabits }

enum ActivityReportCategory { habits, cardio, routines, reading, writing }

class ActivityReportPoint {
  const ActivityReportPoint({
    required this.label,
    required this.date,
    required this.values,
    required this.habitCompletions,
    required this.plannedActivities,
  });

  final String label;
  final DateTime date;
  final Map<ActivityReportCategory, int> values;
  final int habitCompletions;
  final int plannedActivities;

  int get activeMinutes =>
      values.values.fold(0, (total, value) => total + value);
}

class ActivityReport {
  const ActivityReport({
    required this.range,
    required this.points,
    required this.totalHabitCompletions,
    required this.completedActivities,
    required this.plannedActivities,
    required this.hasRecords,
    required this.currentStreak,
    required this.longestStreak,
    required this.weeklyConsistency,
    required this.previousWeekChangePercent,
  });

  final ReportRange range;
  final List<ActivityReportPoint> points;
  final int totalHabitCompletions;
  final int completedActivities;
  final int plannedActivities;
  final bool hasRecords;
  final int currentStreak;
  final int longestStreak;
  final int? weeklyConsistency;
  final int? previousWeekChangePercent;

  int get activeMinutes =>
      points.fold(0, (total, point) => total + point.activeMinutes);

  int get completedHabits => totalHabitCompletions;

  int? get completionPercent => plannedActivities == 0
      ? null
      : (completedActivities * 100 / plannedActivities).round().clamp(0, 100);

  DateTime? get bestDay {
    if (points.isEmpty) return null;
    final best = points.reduce(
      (left, right) => right.activeMinutes > left.activeMinutes ? right : left,
    );
    return best.activeMinutes == 0 ? null : best.date;
  }
}

class HabitStreak {
  const HabitStreak({required this.current, required this.longest});

  final int current;
  final int longest;
}

class ActivityAnalytics {
  static ActivityReport buildReport(
    ActivitySnapshot snapshot, {
    required ReportRange range,
    required DateTime anchor,
  }) {
    final anchorDay = _day(anchor);
    final dates = switch (range) {
      ReportRange.daily => [anchorDay],
      ReportRange.weekly => List.generate(
        7,
        (index) => _weekStart(anchorDay).add(Duration(days: index)),
      ),
      ReportRange.monthly => List.generate(
        DateTime(anchorDay.year, anchorDay.month + 1, 0).day,
        (index) => DateTime(anchorDay.year, anchorDay.month, index + 1),
      ),
    };

    final points = range == ReportRange.daily
        ? _hourlyPoints(snapshot, anchorDay)
        : dates.map((date) => _dailyPoint(snapshot, date, range)).toList();
    final expected = _periodCompletion(snapshot, dates, range);
    final currentStreak = _aggregateCurrentStreak(snapshot, anchorDay);
    final longestStreak = _aggregateLongestStreak(snapshot, anchorDay);
    final weekNow = _weeklyMinutes(snapshot, _weekStart(anchorDay));
    final weekBefore = _weeklyMinutes(
      snapshot,
      _weekStart(anchorDay).subtract(const Duration(days: 7)),
    );
    final weeklyChange = weekBefore == 0
        ? null
        : ((weekNow - weekBefore) * 100 / weekBefore).round();

    return ActivityReport(
      range: range,
      points: points,
      totalHabitCompletions: _habitCompletionCount(
        snapshot,
        dates.first,
        dates.last.add(const Duration(days: 1)),
      ),
      completedActivities: expected.$1,
      plannedActivities: expected.$2,
      hasRecords: _hasRecords(snapshot, dates.first, dates.last),
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      weeklyConsistency: expected.$2 == 0
          ? null
          : (expected.$1 * 100 / expected.$2).round().clamp(0, 100),
      previousWeekChangePercent: weeklyChange,
    );
  }

  static HabitStreak streakForHabit(
    Habit habit,
    List<HabitCheckIn> checkIns, {
    required DateTime through,
  }) {
    final completedByPeriod = <String, int>{};
    for (final checkIn in checkIns.where(
      (item) =>
          item.habitId == habit.id && item.status == ActivityStatus.completed,
    )) {
      final date = DateTime.parse(checkIn.dayKey);
      final periodStart = habit.period == ActivityPeriod.daily
          ? _day(date)
          : _weekStart(date);
      final key = activityDayKey(periodStart);
      completedByPeriod.update(key, (count) => count + 1, ifAbsent: () => 1);
    }

    final start = habit.period == ActivityPeriod.daily
        ? _day(habit.createdAt)
        : _weekStart(habit.createdAt);
    var end = habit.period == ActivityPeriod.daily
        ? _day(through)
        : _weekStart(through);
    final currentPeriodKey = activityDayKey(end);
    if ((completedByPeriod[currentPeriodKey] ?? 0) < habit.targetCount) {
      end = habit.period == ActivityPeriod.daily
          ? end.subtract(const Duration(days: 1))
          : end.subtract(const Duration(days: 7));
    }

    var current = 0;
    var cursor = end;
    while (!cursor.isBefore(start) &&
        (completedByPeriod[activityDayKey(cursor)] ?? 0) >= habit.targetCount) {
      current++;
      cursor = cursor.subtract(
        Duration(days: habit.period == ActivityPeriod.daily ? 1 : 7),
      );
    }

    var longest = 0;
    var sequence = 0;
    cursor = start;
    while (!cursor.isAfter(_periodStart(through, habit.period))) {
      if ((completedByPeriod[activityDayKey(cursor)] ?? 0) >=
          habit.targetCount) {
        sequence++;
        if (sequence > longest) longest = sequence;
      } else {
        sequence = 0;
      }
      cursor = cursor.add(
        Duration(days: habit.period == ActivityPeriod.daily ? 1 : 7),
      );
    }
    return HabitStreak(current: current, longest: longest);
  }

  static String? mostConsistentHabit(
    ActivitySnapshot snapshot, {
    required DateTime through,
  }) {
    final end = _day(through);
    final start = end.subtract(const Duration(days: 29));
    String? bestTitle;
    var bestRate = 0.0;
    for (final habit in snapshot.habits.where((item) => !item.archived)) {
      final activeStart = _day(habit.createdAt).isAfter(start)
          ? _day(habit.createdAt)
          : start;
      if (activeStart.isAfter(end)) continue;
      final days = end.difference(activeStart).inDays + 1;
      final periods = habit.period == ActivityPeriod.daily
          ? days
          : _mondayCount(activeStart, end.add(const Duration(days: 1)));
      final done = snapshot.habitCheckIns
          .where(
            (item) =>
                item.habitId == habit.id &&
                item.status == ActivityStatus.completed &&
                !DateTime.parse(item.dayKey).isBefore(activeStart) &&
                !DateTime.parse(item.dayKey).isAfter(end),
          )
          .length;
      final rate = (done / (periods * habit.targetCount))
          .clamp(0, 1)
          .toDouble();
      if (rate > bestRate) {
        bestRate = rate;
        bestTitle = habit.title;
      }
    }
    return bestTitle;
  }

  static int goalProgress(
    ActivitySnapshot snapshot,
    ActivityGoal goal, {
    required DateTime through,
  }) {
    final day = _day(through);
    final start = goal.period == ActivityPeriod.daily ? day : _weekStart(day);
    final end = start.add(
      Duration(days: goal.period == ActivityPeriod.daily ? 1 : 7),
    );
    return _goalProgress(snapshot, goal.category, goal.unit, start, end);
  }

  static ActivityReportPoint _dailyPoint(
    ActivitySnapshot snapshot,
    DateTime day,
    ReportRange range,
  ) {
    final dayKey = activityDayKey(day);
    final values = _emptyValues();
    final habits = snapshot.habitCheckIns.where(
      (item) =>
          item.dayKey == dayKey && item.status == ActivityStatus.completed,
    );
    for (final checkIn in habits) {
      values[ActivityReportCategory.habits] =
          values[ActivityReportCategory.habits]! +
          (checkIn.durationMinutes ?? 0);
    }
    for (final checkIn in snapshot.routineStepCheckIns.where(
      (item) =>
          item.dayKey == dayKey && item.status == ActivityStatus.completed,
    )) {
      values[ActivityReportCategory.routines] =
          values[ActivityReportCategory.routines]! +
          (checkIn.durationMinutes ?? 0);
    }
    for (final session in snapshot.sessions.where(
      (item) =>
          item.dayKey == dayKey && item.status == ActivityStatus.completed,
    )) {
      final category = switch (session.category) {
        ActivityCategory.cardio => ActivityReportCategory.cardio,
        ActivityCategory.reading => ActivityReportCategory.reading,
        ActivityCategory.writing => ActivityReportCategory.writing,
      };
      values[category] = values[category]! + session.durationMinutes;
    }
    final planned = _plannedForDay(snapshot, day);
    return ActivityReportPoint(
      label: range == ReportRange.weekly ? _weekday(day.weekday) : '${day.day}',
      date: day,
      values: values,
      habitCompletions: habits.length,
      plannedActivities: planned,
    );
  }

  static List<ActivityReportPoint> _hourlyPoints(
    ActivitySnapshot snapshot,
    DateTime day,
  ) {
    final points = List.generate(
      24,
      (hour) => ActivityReportPoint(
        label: hour.toString().padLeft(2, '0'),
        date: DateTime(day.year, day.month, day.day, hour),
        values: _emptyValues(),
        habitCompletions: snapshot.habitCheckIns
            .where(
              (checkIn) =>
                  checkIn.dayKey == activityDayKey(day) &&
                  checkIn.completedAt.hour == hour &&
                  checkIn.status == ActivityStatus.completed,
            )
            .length,
        plannedActivities: 0,
      ),
    );
    final dayStart = _day(day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    void distribute(
      DateTime start,
      int duration,
      ActivityReportCategory category,
    ) {
      if (duration <= 0) return;
      var cursor = start;
      final end = start.add(Duration(minutes: duration));
      while (cursor.isBefore(end)) {
        final nextHour = DateTime(
          cursor.year,
          cursor.month,
          cursor.day,
          cursor.hour + 1,
        );
        final segmentEnd = nextHour.isBefore(end) ? nextHour : end;
        final overlapStart = cursor.isBefore(dayStart) ? dayStart : cursor;
        final overlapEnd = segmentEnd.isAfter(dayEnd) ? dayEnd : segmentEnd;
        if (overlapEnd.isAfter(overlapStart)) {
          final hour = overlapStart.hour;
          points[hour].values[category] =
              points[hour].values[category]! +
              (overlapEnd.difference(overlapStart).inSeconds / 60).round();
        }
        cursor = segmentEnd;
      }
    }

    for (final session in snapshot.sessions.where(
      (item) => item.status == ActivityStatus.completed,
    )) {
      final category = switch (session.category) {
        ActivityCategory.cardio => ActivityReportCategory.cardio,
        ActivityCategory.reading => ActivityReportCategory.reading,
        ActivityCategory.writing => ActivityReportCategory.writing,
      };
      distribute(session.startedAt, session.durationMinutes, category);
    }
    for (final checkIn in snapshot.habitCheckIns.where(
      (item) => item.status == ActivityStatus.completed,
    )) {
      distribute(
        checkIn.completedAt.subtract(
          Duration(minutes: checkIn.durationMinutes ?? 0),
        ),
        checkIn.durationMinutes ?? 0,
        ActivityReportCategory.habits,
      );
    }
    for (final checkIn in snapshot.routineStepCheckIns.where(
      (item) =>
          item.status == ActivityStatus.completed && item.completedAt != null,
    )) {
      distribute(
        checkIn.completedAt!.subtract(
          Duration(minutes: checkIn.durationMinutes ?? 0),
        ),
        checkIn.durationMinutes ?? 0,
        ActivityReportCategory.routines,
      );
    }
    return points;
  }

  static (int, int) _periodCompletion(
    ActivitySnapshot snapshot,
    List<DateTime> dates,
    ReportRange range,
  ) {
    if (dates.isEmpty) return (0, 0);
    var completed = 0;
    var planned = 0;
    if (range == ReportRange.daily) {
      planned = _plannedForDay(snapshot, dates.first);
      completed = _completedForDay(snapshot, dates.first);
      return (completed.clamp(0, planned), planned);
    }
    if (range == ReportRange.weekly) {
      final weekStart = dates.first;
      final weekEnd = weekStart.add(const Duration(days: 7));
      for (final habit in snapshot.habits.where((item) => !item.archived)) {
        if (habit.period == ActivityPeriod.daily) {
          final expected = habit.targetCount * 7;
          planned += expected;
          final actual = snapshot.habitCheckIns
              .where(
                (item) =>
                    item.habitId == habit.id &&
                    item.status == ActivityStatus.completed &&
                    _within(item.dayKey, weekStart, weekEnd),
              )
              .length;
          completed += actual.clamp(0, expected);
        } else {
          planned += habit.targetCount;
          final actual = snapshot.habitCheckIns
              .where(
                (item) =>
                    item.habitId == habit.id &&
                    item.status == ActivityStatus.completed &&
                    _within(item.dayKey, weekStart, weekEnd),
              )
              .length;
          completed += actual.clamp(0, habit.targetCount);
        }
      }
      for (final day in dates) {
        final routineSteps = _activeRoutineStepIds(snapshot, onDate: day);
        planned += routineSteps.length;
        completed += snapshot.routineStepCheckIns
            .where(
              (item) =>
                  routineSteps.contains(item.stepId) &&
                  item.dayKey == activityDayKey(day) &&
                  item.status == ActivityStatus.completed,
            )
            .length
            .clamp(0, routineSteps.length);
      }
      for (final goal in snapshot.goals.where(
        (item) => item.period == ActivityPeriod.weekly,
      )) {
        planned++;
        if (_goalMet(
          snapshot,
          goal.category,
          goal.unit,
          goal.target,
          weekStart,
          weekEnd,
        )) {
          completed++;
        }
      }
      return (completed.clamp(0, planned), planned);
    }

    for (final date in dates) {
      final result = _periodCompletion(snapshot, [date], ReportRange.daily);
      completed += result.$1;
      planned += result.$2;
    }
    final monthStart = dates.first;
    final monthEnd = dates.last.add(const Duration(days: 1));
    final numberWeeks = _mondayCount(monthStart, monthEnd);
    for (final habit in snapshot.habits.where(
      (item) => !item.archived && item.period == ActivityPeriod.weekly,
    )) {
      final expected = habit.targetCount * numberWeeks;
      planned += expected;
      final actual = snapshot.habitCheckIns
          .where(
            (item) =>
                item.habitId == habit.id &&
                item.status == ActivityStatus.completed &&
                _within(item.dayKey, monthStart, monthEnd),
          )
          .length;
      completed += actual.clamp(0, expected);
    }
    for (final goal in snapshot.goals.where(
      (item) => item.period == ActivityPeriod.weekly,
    )) {
      planned += numberWeeks;
      var week = _weekStart(monthStart);
      while (week.isBefore(monthEnd)) {
        final weekEnd = week.add(const Duration(days: 7));
        if (_goalMet(
          snapshot,
          goal.category,
          goal.unit,
          goal.target,
          week,
          weekEnd,
        )) {
          completed++;
        }
        week = weekEnd;
      }
    }
    return (completed.clamp(0, planned), planned);
  }

  static int _plannedForDay(ActivitySnapshot snapshot, DateTime date) {
    var planned = snapshot.habits
        .where(
          (habit) =>
              !habit.archived &&
              habit.period == ActivityPeriod.daily &&
              !_day(date).isBefore(_day(habit.createdAt)),
        )
        .fold<int>(0, (total, habit) => total + habit.targetCount);
    planned += _activeRoutineStepIds(snapshot, onDate: date).length;
    planned += snapshot.goals
        .where((item) => item.period == ActivityPeriod.daily)
        .length;
    return planned;
  }

  static int _completedForDay(ActivitySnapshot snapshot, DateTime date) {
    final dayStart = _day(date);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var completed = 0;
    for (final habit in snapshot.habits.where(
      (item) =>
          !item.archived &&
          item.period == ActivityPeriod.daily &&
          !dayStart.isBefore(_day(item.createdAt)),
    )) {
      final count = snapshot.habitCheckIns
          .where(
            (item) =>
                item.habitId == habit.id &&
                item.dayKey == activityDayKey(date) &&
                item.status == ActivityStatus.completed,
          )
          .length;
      completed += count.clamp(0, habit.targetCount);
    }
    final activeSteps = _activeRoutineStepIds(snapshot, onDate: date);
    completed += snapshot.routineStepCheckIns
        .where(
          (item) =>
              activeSteps.contains(item.stepId) &&
              item.dayKey == activityDayKey(date) &&
              item.status == ActivityStatus.completed,
        )
        .length
        .clamp(0, activeSteps.length);
    for (final goal in snapshot.goals.where(
      (item) => item.period == ActivityPeriod.daily,
    )) {
      if (_goalMet(
        snapshot,
        goal.category,
        goal.unit,
        goal.target,
        dayStart,
        dayEnd,
      )) {
        completed++;
      }
    }
    return completed;
  }

  static Set<String> _activeRoutineStepIds(
    ActivitySnapshot snapshot, {
    required DateTime onDate,
  }) {
    final activeRoutines = snapshot.routines
        .where(
          (routine) =>
              !routine.archived &&
              !_day(onDate).isBefore(_day(routine.createdAt)),
        )
        .map((routine) => routine.id)
        .toSet();
    return snapshot.routineSteps
        .where((step) => activeRoutines.contains(step.routineId))
        .map((step) => step.id)
        .toSet();
  }

  static bool _goalMet(
    ActivitySnapshot snapshot,
    String category,
    String unit,
    int target,
    DateTime start,
    DateTime end,
  ) => _goalProgress(snapshot, category, unit, start, end) >= target;

  static int _goalProgress(
    ActivitySnapshot snapshot,
    String category,
    String unit,
    DateTime start,
    DateTime end,
  ) {
    var total = 0;
    for (final session in snapshot.sessions.where(
      (item) =>
          item.category.name == category &&
          item.status == ActivityStatus.completed &&
          !item.startedAt.isBefore(start) &&
          item.startedAt.isBefore(end),
    )) {
      total += switch (unit.toLowerCase()) {
        'pages' => session.pages ?? 0,
        'words' => session.words ?? 0,
        'km' || 'kilometers' => (session.distanceKm ?? 0).round(),
        'calories' || 'kcal' => session.calories ?? 0,
        _ => session.durationMinutes,
      };
    }
    return total;
  }

  static int _weeklyMinutes(ActivitySnapshot snapshot, DateTime start) {
    final end = start.add(const Duration(days: 7));
    var total = 0;
    for (final session in snapshot.sessions.where(
      (item) =>
          item.status == ActivityStatus.completed &&
          !item.startedAt.isBefore(start) &&
          item.startedAt.isBefore(end),
    )) {
      total += session.durationMinutes;
    }
    for (final checkIn in snapshot.habitCheckIns.where(
      (item) =>
          item.status == ActivityStatus.completed &&
          _within(item.dayKey, start, end),
    )) {
      total += checkIn.durationMinutes ?? 0;
    }
    for (final checkIn in snapshot.routineStepCheckIns.where(
      (item) =>
          item.status == ActivityStatus.completed &&
          _within(item.dayKey, start, end),
    )) {
      total += checkIn.durationMinutes ?? 0;
    }
    return total;
  }

  static int _habitCompletionCount(
    ActivitySnapshot snapshot,
    DateTime start,
    DateTime exclusiveEnd,
  ) => snapshot.habitCheckIns
      .where(
        (item) =>
            item.status == ActivityStatus.completed &&
            _within(item.dayKey, start, exclusiveEnd),
      )
      .length;

  static int _aggregateCurrentStreak(
    ActivitySnapshot snapshot,
    DateTime through,
  ) {
    final streaks = snapshot.habits
        .where((habit) => !habit.archived)
        .map(
          (habit) => streakForHabit(
            habit,
            snapshot.habitCheckIns,
            through: through,
          ).current,
        );
    return streaks.fold<int>(0, (best, value) => value > best ? value : best);
  }

  static int _aggregateLongestStreak(
    ActivitySnapshot snapshot,
    DateTime through,
  ) {
    final streaks = snapshot.habits
        .where((habit) => !habit.archived)
        .map(
          (habit) => streakForHabit(
            habit,
            snapshot.habitCheckIns,
            through: through,
          ).longest,
        );
    return streaks.fold<int>(0, (best, value) => value > best ? value : best);
  }

  static bool _hasRecords(
    ActivitySnapshot snapshot,
    DateTime start,
    DateTime end,
  ) {
    final afterEnd = end.add(const Duration(days: 1));
    return snapshot.sessions.any(
          (item) =>
              !item.startedAt.isBefore(start) &&
              item.startedAt.isBefore(afterEnd),
        ) ||
        snapshot.habitCheckIns.any(
          (item) => _within(item.dayKey, start, afterEnd),
        ) ||
        snapshot.routineStepCheckIns.any(
          (item) => _within(item.dayKey, start, afterEnd),
        );
  }

  static bool _within(String dayKey, DateTime start, DateTime exclusiveEnd) {
    final date = DateTime.parse(dayKey);
    return !date.isBefore(_day(start)) && date.isBefore(_day(exclusiveEnd));
  }

  static int _mondayCount(DateTime start, DateTime exclusiveEnd) {
    var monday = _weekStart(start);
    var count = 0;
    while (monday.isBefore(exclusiveEnd)) {
      count++;
      monday = monday.add(const Duration(days: 7));
    }
    return count;
  }

  static DateTime _periodStart(DateTime date, ActivityPeriod period) =>
      period == ActivityPeriod.daily ? _day(date) : _weekStart(date);

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _weekStart(DateTime date) {
    final day = _day(date);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static String _weekday(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

  static Map<ActivityReportCategory, int> _emptyValues() => {
    for (final category in ActivityReportCategory.values) category: 0,
  };
}
