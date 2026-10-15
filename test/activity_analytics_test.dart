import 'package:flutter_test/flutter_test.dart';
import 'package:to_do_app/data/models/activity.dart';
import 'package:to_do_app/data/repositories/activity_repository.dart';
import 'package:to_do_app/features/activity/analytics/activity_analytics.dart';

void main() {
  group('daily reports', () {
    test('use 24 hourly buckets and split sessions at midnight', () {
      final day = DateTime(2026, 10, 14);
      final snapshot = ActivitySnapshot(
        habitCheckIns: [
          HabitCheckIn(
            id: 'meditation',
            habitId: 'meditation-habit',
            dayKey: activityDayKey(day),
            status: ActivityStatus.completed,
            completedAt: DateTime(2026, 10, 14, 12, 30),
            durationMinutes: 20,
          ),
        ],
        sessions: [
          ActivitySession(
            id: 'late-run',
            category: ActivityCategory.cardio,
            title: 'Evening run',
            startedAt: DateTime(2026, 10, 14, 23, 50),
            durationMinutes: 20,
          ),
          ActivitySession(
            id: 'reading',
            category: ActivityCategory.reading,
            title: 'Read',
            startedAt: DateTime(2026, 10, 14, 0, 10),
            durationMinutes: 30,
          ),
        ],
      );

      final report = ActivityAnalytics.buildReport(
        snapshot,
        range: ReportRange.daily,
        anchor: day,
      );

      expect(report.points, hasLength(24));
      expect(report.points.first.label, '00');
      expect(report.points.last.label, '23');
      expect(report.points.first.values[ActivityReportCategory.reading], 30);
      expect(report.points.last.values[ActivityReportCategory.cardio], 10);
      expect(report.points[12].values[ActivityReportCategory.habits], 20);
      expect(report.activeMinutes, 60);
      expect(report.hasRecords, isTrue);
    });

    test('completion counts only saved planned check-ins, not skips', () {
      final day = DateTime(2026, 10, 14);
      final habit = Habit(
        id: 'walk',
        title: 'Walk',
        targetCount: 2,
        createdAt: DateTime(2026, 10, 1),
      );
      final snapshot = ActivitySnapshot(
        habits: [habit],
        habitCheckIns: [
          _checkIn('done-1', habit.id, day, ActivityStatus.completed),
          _checkIn('done-2', habit.id, day, ActivityStatus.completed),
          _checkIn('skip', habit.id, day, ActivityStatus.skipped),
        ],
      );

      final report = ActivityAnalytics.buildReport(
        snapshot,
        range: ReportRange.daily,
        anchor: day,
      );

      expect(report.completedActivities, 2);
      expect(report.plannedActivities, 2);
      expect(report.completionPercent, 100);
      expect(report.completedHabits, 2);
    });
  });

  test(
    'weekly reports use Monday through Sunday with real category totals',
    () {
      final snapshot = ActivitySnapshot(
        sessions: [
          ActivitySession(
            id: 'monday-cardio',
            category: ActivityCategory.cardio,
            title: 'Run',
            startedAt: DateTime(2026, 10, 12, 8),
            durationMinutes: 20,
          ),
          ActivitySession(
            id: 'sunday-reading',
            category: ActivityCategory.reading,
            title: 'Read',
            startedAt: DateTime(2026, 10, 18, 19),
            durationMinutes: 30,
          ),
        ],
      );

      final report = ActivityAnalytics.buildReport(
        snapshot,
        range: ReportRange.weekly,
        anchor: DateTime(2026, 10, 14),
      );

      expect(report.points, hasLength(7));
      expect(report.points.map((point) => point.label).toList(), [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ]);
      expect(report.points.first.values[ActivityReportCategory.cardio], 20);
      expect(report.points.last.values[ActivityReportCategory.reading], 30);
      expect(report.activeMinutes, 50);
    },
  );

  test(
    'measured goals use saved activity values and contribute to completion',
    () {
      final day = DateTime(2026, 10, 14);
      const goal = ActivityGoal(
        id: 'cardio-minutes',
        category: 'cardio',
        period: ActivityPeriod.daily,
        target: 30,
        unit: 'minutes',
      );
      final firstSession = ActivitySession(
        id: 'first-cardio',
        category: ActivityCategory.cardio,
        title: 'Walk',
        startedAt: DateTime(2026, 10, 14, 9),
        durationMinutes: 25,
      );
      final snapshot = ActivitySnapshot(
        goals: [goal],
        sessions: [firstSession],
      );
      expect(ActivityAnalytics.goalProgress(snapshot, goal, through: day), 25);
      expect(
        ActivityAnalytics.buildReport(
          snapshot,
          range: ReportRange.daily,
          anchor: day,
        ).completionPercent,
        0,
      );

      final completedReport = ActivityAnalytics.buildReport(
        ActivitySnapshot(
          goals: [goal],
          sessions: [
            firstSession,
            ActivitySession(
              id: 'second-cardio',
              category: ActivityCategory.cardio,
              title: 'Ride',
              startedAt: DateTime(2026, 10, 14, 18),
              durationMinutes: 10,
            ),
          ],
        ),
        range: ReportRange.daily,
        anchor: day,
      );
      expect(completedReport.completedActivities, 1);
      expect(completedReport.completionPercent, 100);
    },
  );

  test('weekly routine opportunities begin on the routine creation date', () {
    final routine = Routine(
      id: 'new-routine',
      title: 'Evening routine',
      period: 'evening',
      createdAt: DateTime(2026, 10, 14),
    );
    const step = RoutineStep(
      id: 'journal',
      routineId: 'new-routine',
      title: 'Journal',
      sortOrder: 0,
    );
    final snapshot = ActivitySnapshot(
      routines: [routine],
      routineSteps: [step],
      routineStepCheckIns: [
        RoutineStepCheckIn(
          stepId: step.id,
          dayKey: '2026-10-15',
          status: ActivityStatus.completed,
          completedAt: DateTime(2026, 10, 15, 20),
        ),
      ],
    );

    final report = ActivityAnalytics.buildReport(
      snapshot,
      range: ReportRange.weekly,
      anchor: DateTime(2026, 10, 14),
    );

    expect(report.plannedActivities, 5);
    expect(report.completedActivities, 1);
  });

  test('monthly reports honor month length and expose empty planned state', () {
    final dayHabit = Habit(
      id: 'journal',
      title: 'Journal',
      createdAt: DateTime(2026, 10, 1),
    );
    final snapshot = ActivitySnapshot(
      habits: [dayHabit],
      habitCheckIns: [
        _checkIn(
          'oct-first',
          dayHabit.id,
          DateTime(2026, 10, 1),
          ActivityStatus.completed,
        ),
        _checkIn(
          'oct-last',
          dayHabit.id,
          DateTime(2026, 10, 31),
          ActivityStatus.completed,
        ),
      ],
    );
    final monthly = ActivityAnalytics.buildReport(
      snapshot,
      range: ReportRange.monthly,
      anchor: DateTime(2026, 10, 14),
    );
    final empty = ActivityAnalytics.buildReport(
      const ActivitySnapshot(),
      range: ReportRange.monthly,
      anchor: DateTime(2026, 2, 1),
    );

    expect(monthly.points, hasLength(31));
    expect(monthly.completedHabits, 2);
    expect(monthly.plannedActivities, 31);
    expect(monthly.completionPercent, 6);
    expect(monthly.points.first.habitCompletions, 1);
    expect(monthly.points.last.habitCompletions, 1);
    expect(empty.points, hasLength(28));
    expect(empty.hasRecords, isFalse);
    expect(empty.plannedActivities, 0);
    expect(empty.completionPercent, isNull);
  });

  test('daily and weekly streaks respect consecutive target periods', () {
    final dailyHabit = Habit(
      id: 'daily',
      title: 'Daily',
      createdAt: DateTime(2026, 10, 10),
    );
    final weeklyHabit = Habit(
      id: 'weekly',
      title: 'Weekly',
      period: ActivityPeriod.weekly,
      createdAt: DateTime(2026, 10, 1),
    );
    final checkIns = [
      for (final date in [
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 13),
        DateTime(2026, 10, 14),
      ])
        _checkIn(
          'daily-${date.day}',
          dailyHabit.id,
          date,
          ActivityStatus.completed,
        ),
      _checkIn(
        'weekly-1',
        weeklyHabit.id,
        DateTime(2026, 10, 5),
        ActivityStatus.completed,
      ),
      _checkIn(
        'weekly-2',
        weeklyHabit.id,
        DateTime(2026, 10, 12),
        ActivityStatus.completed,
      ),
    ];

    final dailyStreak = ActivityAnalytics.streakForHabit(
      dailyHabit,
      checkIns,
      through: DateTime(2026, 10, 14),
    );
    final weeklyStreak = ActivityAnalytics.streakForHabit(
      weeklyHabit,
      checkIns,
      through: DateTime(2026, 10, 14),
    );
    expect(dailyStreak.current, 3);
    expect(dailyStreak.longest, 3);
    expect(weeklyStreak.current, 2);
    expect(weeklyStreak.longest, 2);
  });
}

HabitCheckIn _checkIn(
  String id,
  String habitId,
  DateTime day,
  ActivityStatus status,
) => HabitCheckIn(
  id: id,
  habitId: habitId,
  dayKey: activityDayKey(day),
  status: status,
  completedAt: DateTime(day.year, day.month, day.day, 12),
);
