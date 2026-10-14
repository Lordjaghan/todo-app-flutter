import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
      version: 6,
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
}
