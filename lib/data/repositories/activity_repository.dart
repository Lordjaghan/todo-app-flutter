import '../datasources/task_database.dart';
import '../models/activity.dart';

class ActivitySnapshot {
  const ActivitySnapshot({
    this.habits = const [],
    this.habitCheckIns = const [],
    this.sessions = const [],
    this.routines = const [],
    this.routineSteps = const [],
    this.routineStepCheckIns = const [],
    this.goals = const [],
  });

  final List<Habit> habits;
  final List<HabitCheckIn> habitCheckIns;
  final List<ActivitySession> sessions;
  final List<Routine> routines;
  final List<RoutineStep> routineSteps;
  final List<RoutineStepCheckIn> routineStepCheckIns;
  final List<ActivityGoal> goals;
}

class ActivityRepository {
  ActivityRepository(this._database);

  final TaskDatabase _database;

  Future<ActivitySnapshot> loadSnapshot() async {
    final results = await Future.wait<Object>([
      _database.getHabits(),
      _database.getHabitCheckIns(),
      _database.getActivitySessions(),
      _database.getRoutines(),
      _database.getRoutineSteps(),
      _database.getRoutineStepCheckIns(),
      _database.getActivityGoals(),
    ]);
    return ActivitySnapshot(
      habits: results[0] as List<Habit>,
      habitCheckIns: results[1] as List<HabitCheckIn>,
      sessions: results[2] as List<ActivitySession>,
      routines: results[3] as List<Routine>,
      routineSteps: results[4] as List<RoutineStep>,
      routineStepCheckIns: results[5] as List<RoutineStepCheckIn>,
      goals: results[6] as List<ActivityGoal>,
    );
  }

  Future<void> saveHabit(Habit habit) => _database.saveHabit(habit);

  Future<void> saveHabitCheckIn(HabitCheckIn checkIn) =>
      _database.saveHabitCheckIn(checkIn);

  Future<void> saveSession(ActivitySession session) =>
      _database.saveActivitySession(session);

  Future<void> deleteSession(String id) => _database.deleteActivitySession(id);

  Future<void> saveRoutine(Routine routine, List<RoutineStep> steps) =>
      _database.saveRoutine(routine, steps);

  Future<void> saveRoutineStepCheckIn(RoutineStepCheckIn checkIn) =>
      _database.saveRoutineStepCheckIn(checkIn);

  Future<void> saveGoal(ActivityGoal goal) => _database.saveActivityGoal(goal);
}
