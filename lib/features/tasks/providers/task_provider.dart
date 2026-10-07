import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/datasources/task_database.dart';
import '../../../data/models/task.dart';
import '../../../data/repositories/task_repository.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(TaskDatabase());
});

final taskProvider =
    AsyncNotifierProvider<TaskNotifier, List<Task>>(
  TaskNotifier.new,
);

class TaskNotifier extends AsyncNotifier<List<Task>> {
  late final TaskRepository _repository;

  @override
  Future<List<Task>> build() async {
    _repository = ref.read(taskRepositoryProvider);
    return _repository.getTasks();
  }

  Future<void> addTask({
    required String title,
    String description = '',
    String category = 'Personal',
    String priority = 'Medium',
    required DateTime startDate,
    DateTime? dueDate,
  }) async {
    final task = Task(
      id: const Uuid().v4(),
      title: title,
      description: description,
      category: category,
      priority: priority,
      startDate: startDate,
      dueDate: dueDate,
    );

    await _repository.saveTask(task);
    state = AsyncData(await _repository.getTasks());
  }

  Future<void> toggleTask(Task task) async {
    await _repository.saveTask(
      task.copyWith(isCompleted: !task.isCompleted),
    );

    state = AsyncData(await _repository.getTasks());
  }

  Future<void> removeTask(String id) async {
    await _repository.deleteTask(id);
    state = AsyncData(await _repository.getTasks());
  }
}