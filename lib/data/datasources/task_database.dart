import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            category TEXT NOT NULL,
            priority TEXT NOT NULL,
            startDate INTEGER NOT NULL,
            dueDate INTEGER,
            isCompleted INTEGER NOT NULL DEFAULT 0,
            reminderDate INTEGER,
            reminderEnabled INTEGER NOT NULL DEFAULT 0
          )
        ''');
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
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminderDate INTEGER',
          );
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminderEnabled INTEGER NOT NULL DEFAULT 0',
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
      orderBy: 'isCompleted ASC, dueDate ASC',
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

  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }
}
