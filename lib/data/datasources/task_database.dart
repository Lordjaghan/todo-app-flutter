import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/activity.dart';
import '../models/subtask.dart';
import '../models/task.dart';

class TaskDatabase {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final dbPath = kIsWeb
        ? 'todo_app.db'
        : p.join(await getDatabasesPath(), 'todo_app.db');

    _database = await openDatabase(
      dbPath,
      version: 9,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            category TEXT NOT NULL,
            priority TEXT NOT NULL,
            isPinned INTEGER NOT NULL DEFAULT 0,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            createdAt INTEGER NOT NULL,
            startDate INTEGER NOT NULL,
            dueDate INTEGER,
            status TEXT NOT NULL DEFAULT 'inProgress',
            reminderDate INTEGER,
            reminderEnabled INTEGER NOT NULL DEFAULT 0,
            reminderType TEXT NOT NULL DEFAULT 'notification',
            notificationId INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE subtasks (
            id TEXT PRIMARY KEY,
            parentTaskId TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'pending',
            dueDate INTEGER,
            reminderDate INTEGER,
            reminderEnabled INTEGER NOT NULL DEFAULT 0,
            reminderType TEXT NOT NULL DEFAULT 'notification',
            notificationId INTEGER,
            sortOrder INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX subtasks_parent_order ON subtasks(parentTaskId, sortOrder)',
        );
        await _createActivityTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN startDate INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            '''
           UPDATE tasks
           SET startDate = ?
           WHERE startDate = 0
            ''',
            [DateTime.now().millisecondsSinceEpoch],
          );
        }

        if (oldVersion < 3) {
          await db.execute('ALTER TABLE tasks ADD COLUMN reminderDate INTEGER');
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminderEnabled INTEGER NOT NULL DEFAULT 0',
          );
        }

        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN reminderType TEXT NOT NULL DEFAULT 'notification'",
          );
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN notificationId INTEGER',
          );
        }

        if (oldVersion < 5) {
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN status TEXT NOT NULL DEFAULT 'inProgress'",
          );
          await db.execute('''
            UPDATE tasks
            SET status = CASE WHEN isCompleted = 1 THEN 'completed' ELSE 'inProgress' END
          ''');
        }

        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN isPinned INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN sortOrder INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN createdAt INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('UPDATE tasks SET createdAt = startDate');
          final existingTasks = await db.query(
            'tasks',
            columns: ['id'],
            orderBy: '''
              CASE status
                WHEN 'completed' THEN 2
                WHEN 'onHold' THEN 1
                ELSE 0
              END,
              dueDate ASC
            ''',
          );
          for (var index = 0; index < existingTasks.length; index++) {
            await db.update(
              'tasks',
              {'sortOrder': index},
              where: 'id = ?',
              whereArgs: [existingTasks[index]['id']],
            );
          }
          await db.execute('''
            CREATE TABLE subtasks (
              id TEXT PRIMARY KEY,
              parentTaskId TEXT NOT NULL,
              title TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              status TEXT NOT NULL DEFAULT 'pending',
              dueDate INTEGER,
              reminderDate INTEGER,
              reminderEnabled INTEGER NOT NULL DEFAULT 0,
              reminderType TEXT NOT NULL DEFAULT 'notification',
              notificationId INTEGER,
              sortOrder INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute(
            'CREATE INDEX subtasks_parent_order ON subtasks(parentTaskId, sortOrder)',
          );
        }

        if (oldVersion < 7) {
          await _createActivityTables(db);
        }

        if (oldVersion == 7) {
          await db.execute(
            'ALTER TABLE routine_step_checkins ADD COLUMN durationMinutes INTEGER',
          );
        }

        if (oldVersion >= 7 && oldVersion < 9) {
          await db.execute(
            'ALTER TABLE habits ADD COLUMN reminderNotificationId INTEGER',
          );
        }
      },
    );

    return _database!;
  }

  Future<List<Task>> getTasks() async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      orderBy: '''
        isPinned DESC,
        CASE status
          WHEN 'completed' THEN 2
          WHEN 'onHold' THEN 1
          ELSE 0
        END,
        CASE priority WHEN 'High' THEN 0 WHEN 'Medium' THEN 1 ELSE 2 END,
        sortOrder ASC,
        dueDate ASC
      ''',
    );

    return rows.map(Task.fromMap).toList();
  }

  Future<void> saveTask(Task task) async {
    final db = await database;

    await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveTasks(List<Task> tasks) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final task in tasks) {
        await transaction.insert(
          'tasks',
          task.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> saveTaskAndSubtask(Task task, Subtask subtask) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.insert(
        'tasks',
        task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.insert(
        'subtasks',
        subtask.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'subtasks',
        where: 'parentTaskId = ?',
        whereArgs: [id],
      );
      await transaction.delete('tasks', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Subtask>> getSubtasks(String parentTaskId) async {
    final db = await database;
    final rows = await db.query(
      'subtasks',
      where: 'parentTaskId = ?',
      whereArgs: [parentTaskId],
      orderBy: 'sortOrder ASC, dueDate ASC',
    );
    return rows.map(Subtask.fromMap).toList();
  }

  Future<List<Subtask>> getAllSubtasks() async {
    final db = await database;
    final rows = await db.query('subtasks');
    return rows.map(Subtask.fromMap).toList();
  }

  Future<void> saveSubtask(Subtask subtask) async {
    final db = await database;
    await db.insert(
      'subtasks',
      subtask.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSubtask(String id) async {
    final db = await database;
    await db.delete('subtasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Habit>> getHabits() async {
    final db = await database;
    final rows = await db.query('habits', orderBy: 'archived ASC, title ASC');
    return rows.map(Habit.fromMap).toList();
  }

  Future<void> saveHabit(Habit habit) async {
    final db = await database;
    await db.insert(
      'habits',
      habit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<HabitCheckIn>> getHabitCheckIns({
    String? startDay,
    String? endDay,
  }) async {
    final db = await database;
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (startDay != null) {
      clauses.add('dayKey >= ?');
      arguments.add(startDay);
    }
    if (endDay != null) {
      clauses.add('dayKey <= ?');
      arguments.add(endDay);
    }
    final rows = await db.query(
      'habit_checkins',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'dayKey ASC, completedAt ASC',
    );
    return rows.map(HabitCheckIn.fromMap).toList();
  }

  Future<void> saveHabitCheckIn(HabitCheckIn checkIn) async {
    final db = await database;
    await db.insert(
      'habit_checkins',
      checkIn.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ActivitySession>> getActivitySessions({
    String? startDay,
    String? endDay,
  }) async {
    final db = await database;
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (startDay != null) {
      clauses.add('dayKey >= ?');
      arguments.add(startDay);
    }
    if (endDay != null) {
      clauses.add('dayKey <= ?');
      arguments.add(endDay);
    }
    final rows = await db.query(
      'activity_sessions',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'startedAt ASC',
    );
    return rows.map(ActivitySession.fromMap).toList();
  }

  Future<void> saveActivitySession(ActivitySession session) async {
    final db = await database;
    await db.insert(
      'activity_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteActivitySession(String id) async {
    final db = await database;
    await db.delete('activity_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Routine>> getRoutines() async {
    final db = await database;
    final rows = await db.query('routines', orderBy: 'archived ASC, title ASC');
    return rows.map(Routine.fromMap).toList();
  }

  Future<List<RoutineStep>> getRoutineSteps() async {
    final db = await database;
    final rows = await db.query(
      'routine_steps',
      orderBy: 'routineId ASC, sortOrder ASC',
    );
    return rows.map(RoutineStep.fromMap).toList();
  }

  Future<void> saveRoutine(Routine routine, List<RoutineStep> steps) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.insert(
        'routines',
        routine.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final step in steps) {
        await transaction.insert(
          'routine_steps',
          step.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<RoutineStepCheckIn>> getRoutineStepCheckIns({
    String? startDay,
    String? endDay,
  }) async {
    final db = await database;
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (startDay != null) {
      clauses.add('dayKey >= ?');
      arguments.add(startDay);
    }
    if (endDay != null) {
      clauses.add('dayKey <= ?');
      arguments.add(endDay);
    }
    final rows = await db.query(
      'routine_step_checkins',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'dayKey ASC, stepId ASC',
    );
    return rows.map(RoutineStepCheckIn.fromMap).toList();
  }

  Future<void> saveRoutineStepCheckIn(RoutineStepCheckIn checkIn) async {
    final db = await database;
    await db.insert(
      'routine_step_checkins',
      checkIn.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ActivityGoal>> getActivityGoals() async {
    final db = await database;
    final rows = await db.query('activity_goals', orderBy: 'category ASC');
    return rows.map(ActivityGoal.fromMap).toList();
  }

  Future<void> saveActivityGoal(ActivityGoal goal) async {
    final db = await database;
    await db.insert(
      'activity_goals',
      goal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _createActivityTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE habits (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        period TEXT NOT NULL DEFAULT 'daily',
        targetCount INTEGER NOT NULL DEFAULT 1,
        archived INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL,
        reminderTime TEXT,
        reminderNotificationId INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE habit_checkins (
        id TEXT PRIMARY KEY,
        habitId TEXT NOT NULL,
        dayKey TEXT NOT NULL,
        status TEXT NOT NULL,
        value REAL,
        durationMinutes INTEGER,
        completedAt INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE activity_sessions (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        startedAt INTEGER NOT NULL,
        dayKey TEXT NOT NULL,
        durationMinutes INTEGER NOT NULL,
        distanceKm REAL,
        calories INTEGER,
        pages INTEGER,
        words INTEGER,
        status TEXT NOT NULL DEFAULT 'completed'
      )
    ''');
    await db.execute('''
      CREATE TABLE routines (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        period TEXT NOT NULL DEFAULT 'custom',
        archived INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE routine_steps (
        id TEXT PRIMARY KEY,
        routineId TEXT NOT NULL,
        title TEXT NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE routine_step_checkins (
        stepId TEXT NOT NULL,
        dayKey TEXT NOT NULL,
        status TEXT NOT NULL,
        completedAt INTEGER,
        durationMinutes INTEGER,
        PRIMARY KEY (stepId, dayKey)
      )
    ''');
    await db.execute('''
      CREATE TABLE activity_goals (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        period TEXT NOT NULL,
        target INTEGER NOT NULL,
        unit TEXT NOT NULL,
        UNIQUE (category, period)
      )
    ''');
    await db.execute(
      'CREATE INDEX habit_checkins_day ON habit_checkins(dayKey, habitId)',
    );
    await db.execute(
      'CREATE INDEX activity_sessions_day ON activity_sessions(dayKey, category)',
    );
    await db.execute(
      'CREATE INDEX routine_steps_order ON routine_steps(routineId, sortOrder)',
    );
  }
}
