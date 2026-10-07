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
import 'package:to_do_app/main.dart';

void main() {
  testWidgets('saving a task returns Home with its start date', (
    tester,
  ) async {
    final database = _MemoryTaskDatabase();
    await tester.pumpWidget(_testApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

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

    await tester.enterText(find.byType(TextFormField).first, 'Write tests');
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
}

Widget _testApp(_MemoryTaskDatabase database) {
  return ProviderScope(
    overrides: [
      taskRepositoryProvider.overrideWith(
        (ref) => TaskRepository(database),
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
