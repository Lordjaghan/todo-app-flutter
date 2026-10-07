import '../datasources/task_database.dart';
import '../models/task.dart';

class TaskRepository {
  final TaskDatabase _database;

  TaskRepository(this._database);

  Future<List<Task>> getTasks() => _database.getTasks();

  Future<void> saveTask(Task task) =>
      _database.saveTask(task);

  Future<void> deleteTask(String id) =>
      _database.deleteTask(id);
}