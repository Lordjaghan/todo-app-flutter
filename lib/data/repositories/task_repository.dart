import '../datasources/task_database.dart';
import '../models/subtask.dart';
import '../models/task.dart';

class TaskRepository {
  final TaskDatabase _database;

  TaskRepository(this._database);

  Future<List<Task>> getTasks() => _database.getTasks();

  Future<void> saveTask(Task task) => _database.saveTask(task);

  Future<void> saveTasks(List<Task> tasks) => _database.saveTasks(tasks);

  Future<void> saveTaskAndSubtask(Task task, Subtask subtask) =>
      _database.saveTaskAndSubtask(task, subtask);

  Future<void> deleteTask(String id) => _database.deleteTask(id);

  Future<List<Subtask>> getSubtasks(String parentTaskId) =>
      _database.getSubtasks(parentTaskId);

  Future<List<Subtask>> getAllSubtasks() => _database.getAllSubtasks();

  Future<void> saveSubtask(Subtask subtask) => _database.saveSubtask(subtask);

  Future<void> deleteSubtask(String id) => _database.deleteSubtask(id);
}
