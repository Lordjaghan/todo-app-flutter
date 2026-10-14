import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:to_do_app/data/datasources/task_database.dart';
import 'package:to_do_app/data/models/subtask.dart';
import 'package:to_do_app/data/models/task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  sqflite.databaseFactory = databaseFactoryFfi;

  test('migrates existing tasks and saves tasks with both dates', () async {
    final databasePath = p.join(
      await databaseFactoryFfi.getDatabasesPath(),
      'todo_app.db',
    );
    await databaseFactoryFfi.deleteDatabase(databasePath);

    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              description TEXT NOT NULL,
              category TEXT NOT NULL,
              priority TEXT NOT NULL,
              dueDate INTEGER,
              isCompleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.insert('tasks', {
            'id': 'legacy',
            'title': 'Legacy task',
            'description': '',
            'category': 'Personal',
            'priority': 'Medium',
          });
          await db.insert('tasks', {
            'id': 'legacy-completed',
            'title': 'Completed legacy task',
            'description': '',
            'category': 'Personal',
            'priority': 'Medium',
            'isCompleted': 1,
          });
        },
      ),
    );
    await legacyDatabase.close();

    final database = TaskDatabase();
    final migratedTasks = await database.getTasks();
    expect(migratedTasks, hasLength(2));
    final legacyTask = migratedTasks.singleWhere((task) => task.id == 'legacy');
    final legacyCompletedTask = migratedTasks.singleWhere(
      (task) => task.id == 'legacy-completed',
    );
    expect(legacyTask.startDate.millisecondsSinceEpoch, greaterThan(0));
    expect(legacyTask.status, TaskStatus.inProgress);
    expect(legacyCompletedTask.status, TaskStatus.completed);

    final task = Task(
      id: 'new',
      title: 'New task',
      startDate: DateTime(2026, 10, 5),
      createdAt: DateTime(2026, 9, 1),
      isPinned: true,
      sortOrder: 4,
      dueDate: DateTime(2026, 10, 8),
      reminderDate: DateTime(2026, 10, 7, 9, 30),
      reminderEnabled: true,
      reminderType: ReminderType.alarm,
      notificationId: 12345,
      status: TaskStatus.onHold,
    );
    await database.saveTask(task);

    final savedTasks = await database.getTasks();
    final savedTask = savedTasks.singleWhere((item) => item.id == 'new');
    expect(savedTask.startDate, task.startDate);
    expect(savedTask.createdAt, task.createdAt);
    expect(savedTask.isPinned, isTrue);
    expect(savedTask.sortOrder, 4);
    expect(savedTask.dueDate, task.dueDate);
    expect(savedTask.reminderDate, task.reminderDate);
    expect(savedTask.reminderEnabled, isTrue);
    expect(savedTask.reminderType, ReminderType.alarm);
    expect(savedTask.notificationId, 12345);
    expect(savedTask.status, TaskStatus.onHold);

    final subtask = Subtask(
      id: 'new-subtask',
      parentTaskId: task.id,
      title: 'Review notes',
      description: 'Check the final section',
      status: SubtaskStatus.inProgress,
      dueDate: DateTime(2026, 10, 7, 15),
      reminderDate: DateTime(2026, 10, 7, 14),
      reminderEnabled: true,
      notificationId: 54321,
      sortOrder: 2,
    );
    await database.saveSubtask(subtask);
    final savedSubtask = (await database.getSubtasks(task.id)).single;
    expect(savedSubtask.title, subtask.title);
    expect(savedSubtask.description, subtask.description);
    expect(savedSubtask.status, subtask.status);
    expect(savedSubtask.dueDate, subtask.dueDate);
    expect(savedSubtask.reminderDate, subtask.reminderDate);
    expect(savedSubtask.reminderEnabled, isTrue);
    expect(savedSubtask.notificationId, 54321);
    expect(savedSubtask.sortOrder, 2);

    await database.deleteTask(task.id);
    expect(await database.getSubtasks(task.id), isEmpty);

    final openedDatabase = await databaseFactoryFfi.openDatabase(databasePath);
    await openedDatabase.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });
}
