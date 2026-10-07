import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:to_do_app/data/datasources/task_database.dart';
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
        },
      ),
    );
    await legacyDatabase.close();

    final database = TaskDatabase();
    final migratedTasks = await database.getTasks();
    expect(migratedTasks, hasLength(1));
    expect(migratedTasks.single.startDate.millisecondsSinceEpoch, greaterThan(0));

    final task = Task(
      id: 'new',
      title: 'New task',
      startDate: DateTime(2026, 10, 5),
      dueDate: DateTime(2026, 10, 8),
    );
    await database.saveTask(task);

    final savedTasks = await database.getTasks();
    final savedTask = savedTasks.singleWhere((item) => item.id == 'new');
    expect(savedTask.startDate, task.startDate);
    expect(savedTask.dueDate, task.dueDate);

    final openedDatabase = await databaseFactoryFfi.openDatabase(databasePath);
    await openedDatabase.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });
}