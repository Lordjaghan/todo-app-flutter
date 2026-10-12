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
import 'package:to_do_app/data/models/task.dart';
import 'package:to_do_app/data/repositories/task_repository.dart';
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
}

Widget _testApp(_MemoryTaskDatabase database) {
  return ProviderScope(
    overrides: [
      taskRepositoryProvider.overrideWith((ref) => TaskRepository(database)),
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
  bool failSave = false;

  @override
  Future<List<Task>> getTasks() async => List.of(tasks);

  @override
  Future<void> saveTask(Task task) async {
    if (failSave) throw StateError('Save failed');
    tasks.removeWhere((savedTask) => savedTask.id == task.id);
    tasks.add(task);
  }

  @override
  Future<void> deleteTask(String id) async {
    tasks.removeWhere((task) => task.id == id);
  }
}
