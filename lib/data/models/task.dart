class Task {
  final String id;
  final String title;
  final String description;
  final String category;
  final String priority;
  final DateTime startDate;
  final DateTime? dueDate;
  final bool isCompleted;

  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.category = 'Personal',
    this.priority = 'Medium',
    required this.startDate,
    this.dueDate,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'priority': priority,
      'startDate': startDate.millisecondsSinceEpoch,
      'dueDate': dueDate?.millisecondsSinceEpoch,
      'isCompleted': isCompleted ? 1 : 0,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? 'Personal',
      priority: map['priority'] as String? ?? 'Medium',
      startDate: DateTime.fromMillisecondsSinceEpoch(
        map['startDate'] as int,
      ),
      dueDate: map['dueDate'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['dueDate'] as int,
            ),
      isCompleted: (map['isCompleted'] as int? ?? 0) == 1,
    );
  }

  Task copyWith({
    bool? isCompleted,
  }) {
    return Task(
      id: id,
      title: title,
      description: description,
      category: category,
      priority: priority,
      startDate: startDate,
      dueDate: dueDate,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}