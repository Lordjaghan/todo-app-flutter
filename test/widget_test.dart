// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:to_do_app/data/datasources/task_database.dart';
import 'package:to_do_app/data/models/activity.dart';
import 'package:to_do_app/data/models/subtask.dart';
import 'package:to_do_app/data/models/task.dart';
import 'package:to_do_app/data/repositories/task_repository.dart';
import 'package:to_do_app/data/repositories/activity_repository.dart';
import 'package:to_do_app/features/activity/providers/activity_provider.dart';
import 'package:to_do_app/features/tasks/providers/task_provider.dart';
import 'package:to_do_app/features/tasks/widgets/task_card.dart';
import 'package:to_do_app/main.dart';

void main() {
  testWidgets('saving a task returns Home with its start date', (tester) async {
    final database = _MemoryTaskDatabase();
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Write tests');

    final today = DateUtils.dateOnly(DateTime.now());
    final todayLabel = _formatDate(today);
    await tester.scrollUntilVisible(
      find.text('Start date'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text(todayLabel));
    await tester.tap(find.text(todayLabel));
    await tester.pumpAndSettle();
    expect(find.text('Select start date'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create Task'));
    await tester.tap(find.text('Create Task'));
    await tester.pumpAndSettle();

    expect(find.text('Add Task'), findsNothing);
    expect(find.text('Write tests'), findsOneWidget);
    expect(find.text('Start: $todayLabel'), findsOneWidget);
    expect(database.tasks.single.startDate, today);
    expect(database.tasks.single.dueDate, isNull);
  });

  testWidgets('save failures stay on the form and show an error', (
    tester,
  ) async {
    final database = _MemoryTaskDatabase()..failSave = true;
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Write tests');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create Task'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Create Task'));
    await tester.pumpAndSettle();

    expect(find.text('Could not save task. Please try again.'), findsOneWidget);
    expect(find.text('Add Task'), findsOneWidget);
  });

  testWidgets('editing a task prepopulates and saves its updated values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final task = Task(
      id: 'edit-task',
      title: 'Original task',
      description: 'Existing details',
      startDate: DateTime(2026, 10, 8),
    );
    final database = _MemoryTaskDatabase()..tasks.add(task);
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byTooltip('Edit task'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byTooltip('Edit task'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Task'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller
          ?.text,
      'Original task',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller
          ?.text,
      'Existing details',
    );

    await tester.enterText(find.byType(TextFormField).first, 'Updated task');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save Changes'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(database.tasks.single.id, 'edit-task');
    expect(database.tasks.single.title, 'Updated task');
    expect(find.text('Updated task'), findsOneWidget);
  });

  testWidgets('editing a completed task asks before reopening it', (
    tester,
  ) async {
    final task = Task(
      id: 'completed-edit-task',
      title: 'Finished task',
      startDate: DateTime(2026, 10, 8),
      status: TaskStatus.completed,
    );
    final database = _MemoryTaskDatabase()..tasks.add(task);
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit task'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Reopen completed task?'), findsOneWidget);
    await tester.tap(find.text('Reopen Task'));
    await tester.pumpAndSettle();

    expect(database.tasks.single.status, TaskStatus.inProgress);
  });

  testWidgets('task card shows a leading reminder bell and status selector', (
    tester,
  ) async {
    TaskStatus? selectedStatus;
    final task = Task(
      id: 'reminder-task',
      title: 'Reminder task',
      startDate: DateTime(2026, 10, 8),
      reminderEnabled: true,
      reminderDate: DateTime(2030, 10, 8, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCard(
            task: task,
            onStatusChanged: (status) => selectedStatus = status,
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(
      tester.getCenter(find.byIcon(Icons.notifications_active_rounded)).dx,
      lessThan(tester.getCenter(find.text('Reminder task')).dx),
    );
    expect(find.text('In Progress'), findsOneWidget);
    expect(
      tester.getCenter(find.byTooltip('Edit task')).dy,
      lessThan(tester.getCenter(find.byTooltip('Delete task')).dy),
    );
    await tester.tap(find.byTooltip('Change task status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On Hold').last);
    await tester.pumpAndSettle();
    expect(selectedStatus, TaskStatus.onHold);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCard(
            task: task.copyWith(clearReminder: true),
            onStatusChanged: (_) {},
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
  });

  testWidgets('task cards mark due-soon yellow and overdue red', (
    tester,
  ) async {
    Future<void> pumpTask(DateTime reminderDate) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(
              task: Task(
                id: 'urgency-task',
                title: 'Urgency task',
                startDate: DateTime.now(),
                reminderDate: reminderDate,
              ),
              onStatusChanged: (_) {},
              onEdit: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
    }

    await pumpTask(DateTime.now().add(const Duration(minutes: 30)));
    expect(
      tester.widget<Card>(find.byType(Card)).color,
      const Color(0xFFFFF2CC),
    );

    await pumpTask(DateTime.now().subtract(const Duration(seconds: 1)));
    expect(
      tester.widget<Card>(find.byType(Card)).color,
      const Color(0xFFFFE4E4),
    );
  });

  testWidgets('pinning a task keeps it in the pinned section', (tester) async {
    final task = Task(
      id: 'pin-task',
      title: 'Pinned task',
      startDate: DateTime(2026, 10, 8),
    );
    final database = _MemoryTaskDatabase()..tasks.add(task);
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Pin task'));
    await tester.pumpAndSettle();

    expect(database.tasks.single.isPinned, isTrue);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.byTooltip('Unpin task'), findsOneWidget);
  });

  testWidgets('dragging a task into another priority updates its priority', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final database = _MemoryTaskDatabase()
      ..tasks.addAll([
        Task(
          id: 'high-task',
          title: 'High priority task',
          priority: 'High',
          startDate: DateTime(2026, 10, 8),
        ),
        Task(
          id: 'low-task',
          title: 'Low priority task',
          priority: 'Low',
          startDate: DateTime(2026, 10, 8),
        ),
      ]);
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    final start = tester.getCenter(find.text('High priority task'));
    final target = tester.getCenter(find.text('Low priority task'));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    final distance = target.dy - start.dy;
    for (var step = 1; step <= 6; step++) {
      await gesture.moveTo(start + Offset(0, distance * step / 6));
      await tester.pump(const Duration(milliseconds: 80));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      database.tasks.firstWhere((task) => task.id == 'high-task').priority,
      'Low',
    );
  });

  testWidgets('create and update a subtask from the task card', (tester) async {
    final task = Task(
      id: 'parent-task',
      title: 'Parent task',
      startDate: DateTime(2026, 10, 8),
    );
    final database = _MemoryTaskDatabase()..tasks.add(task);
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add subtask'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Review notes');
    await tester.tap(find.text('Add subtask').last);
    await tester.pumpAndSettle();

    expect(database.subtasks.single.title, 'Review notes');
    await tester.tap(find.text('1 subtask'));
    await tester.pumpAndSettle();
    expect(find.text('Review notes'), findsOneWidget);
    expect(find.text('0/1 completed'), findsOneWidget);

    await tester.tap(find.byTooltip('Change subtask status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();

    expect(database.subtasks.single.status, SubtaskStatus.completed);
    expect(find.text('1/1 completed'), findsOneWidget);
  });

  testWidgets('changing to on hold asks before saving without a reminder', (
    tester,
  ) async {
    final task = Task(
      id: 'hold-task',
      title: 'Task to pause',
      startDate: DateTime.now(),
    );
    final database = _MemoryTaskDatabase()..tasks.add(task);
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Change task status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On Hold').last);
    await tester.pumpAndSettle();
    expect(find.text('Set a reminder for on hold?'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    expect(database.tasks.single.status, TaskStatus.onHold);
    expect(database.tasks.single.hasReminder, isFalse);
  });

  testWidgets('Activity creates a habit and logs a cardio session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final database = _MemoryTaskDatabase();
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.insights_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quick actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add habit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Read each day');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(database.habits.single.title, 'Read each day');
    await tester.tap(find.byTooltip('Record habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '7');
    await tester.enterText(find.byType(TextFormField).last, '12');
    await tester.tap(find.text('Complete').last);
    await tester.pumpAndSettle();
    expect(database.habitCheckIns.single.status, ActivityStatus.completed);
    expect(database.habitCheckIns.single.value, 7);
    expect(database.habitCheckIns.single.durationMinutes, 12);

    await tester.tap(find.byTooltip('Quick actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cardio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Evening run');
    await tester.enterText(find.byType(TextField).at(1), '24');
    await tester.enterText(find.byType(TextField).at(2), '4.5');
    await tester.enterText(find.byType(TextField).at(3), '250');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(database.sessions.single.title, 'Evening run');
    expect(database.sessions.single.durationMinutes, 24);
    expect(database.sessions.single.distanceKm, 4.5);
    expect(database.sessions.single.calories, 250);
  });

  testWidgets('Activity creates routines and records completed steps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final database = _MemoryTaskDatabase();
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.insights_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quick actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add routine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Morning reset');
    await tester.enterText(find.byType(TextField).last, 'Stretch\nRead');
    await tester.tap(find.text('Create').last);
    await tester.pumpAndSettle();

    expect(database.routines.single.title, 'Morning reset');
    expect(database.routineSteps.map((step) => step.title).toList(), [
      'Stretch',
      'Read',
    ]);

    await tester.ensureVisible(find.text('Routines').last);
    await tester.tap(find.text('Routines').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Update routine step').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '8');
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();

    expect(
      database.routineStepCheckIns.single.status,
      ActivityStatus.completed,
    );
    expect(database.routineStepCheckIns.single.durationMinutes, 8);

    await tester.ensureVisible(find.text('Calendar').last);
    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
    expect(find.text('Mon'), findsOneWidget);
    await tester.ensureVisible(find.text('Reports').last);
    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();
    expect(find.text('Activity by hour'), findsOneWidget);
    expect(find.text('No activity in this period'), findsNothing);
  });
}

Widget _testApp(_MemoryTaskDatabase database) {
  return ProviderScope(
    overrides: [
      taskRepositoryProvider.overrideWith((ref) => TaskRepository(database)),
      activityRepositoryProvider.overrideWith(
        (ref) => ActivityRepository(database),
      ),
    ],
    child: const TodoApp(),
  );
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}

class _MemoryTaskDatabase extends TaskDatabase {
  final List<Task> tasks = [];
  final List<Subtask> subtasks = [];
  final List<Habit> habits = [];
  final List<HabitCheckIn> habitCheckIns = [];
  final List<ActivitySession> sessions = [];
  final List<Routine> routines = [];
  final List<RoutineStep> routineSteps = [];
  final List<RoutineStepCheckIn> routineStepCheckIns = [];
  final List<ActivityGoal> goals = [];
  bool failSave = false;

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
    if (failSave) throw StateError('Save failed');
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
  }) async => habitCheckIns.where((item) {
    return (startDay == null || item.dayKey.compareTo(startDay) >= 0) &&
        (endDay == null || item.dayKey.compareTo(endDay) <= 0);
  }).toList();

  @override
  Future<void> saveHabitCheckIn(HabitCheckIn checkIn) async {
    habitCheckIns.removeWhere((saved) => saved.id == checkIn.id);
    habitCheckIns.add(checkIn);
  }

  @override
  Future<List<ActivitySession>> getActivitySessions({
    String? startDay,
    String? endDay,
  }) async => sessions.where((item) {
    return (startDay == null || item.dayKey.compareTo(startDay) >= 0) &&
        (endDay == null || item.dayKey.compareTo(endDay) <= 0);
  }).toList();

  @override
  Future<void> saveActivitySession(ActivitySession session) async {
    sessions.removeWhere((saved) => saved.id == session.id);
    sessions.add(session);
  }

  @override
  Future<void> deleteActivitySession(String id) async {
    sessions.removeWhere((session) => session.id == id);
  }

  @override
  Future<List<Routine>> getRoutines() async => List.of(routines);

  @override
  Future<List<RoutineStep>> getRoutineSteps() async => List.of(routineSteps);

  @override
  Future<void> saveRoutine(Routine routine, List<RoutineStep> steps) async {
    routines.removeWhere((saved) => saved.id == routine.id);
    routines.add(routine);
    for (final step in steps) {
      routineSteps.removeWhere((saved) => saved.id == step.id);
      routineSteps.add(step);
    }
  }

  @override
  Future<List<RoutineStepCheckIn>> getRoutineStepCheckIns({
    String? startDay,
    String? endDay,
  }) async => routineStepCheckIns.where((item) {
    return (startDay == null || item.dayKey.compareTo(startDay) >= 0) &&
        (endDay == null || item.dayKey.compareTo(endDay) <= 0);
  }).toList();

  @override
  Future<void> saveRoutineStepCheckIn(RoutineStepCheckIn checkIn) async {
    routineStepCheckIns.removeWhere(
      (saved) =>
          saved.stepId == checkIn.stepId && saved.dayKey == checkIn.dayKey,
    );
    routineStepCheckIns.add(checkIn);
  }

  @override
  Future<List<ActivityGoal>> getActivityGoals() async => List.of(goals);

  @override
  Future<void> saveActivityGoal(ActivityGoal goal) async {
    goals.removeWhere(
      (saved) => saved.category == goal.category && saved.period == goal.period,
    );
    goals.add(goal);
  }
}
