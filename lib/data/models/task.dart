class Task {
  final String id;
  final String title;
  final String description;
  final String category;
  final String priority;
  final DateTime startDate;
  final DateTime? dueDate;
  final bool isCompleted;
  final DateTime? reminderDate;
  final bool reminderEnabled;

  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.category = 'Personal',
    this.priority = 'Medium',
    required this.startDate,
    this.dueDate,
    this.isCompleted = false,
    this.reminderDate,
    this.reminderEnabled = false,
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
      'reminderDate': reminderDate?.millisecondsSinceEpoch,
      'reminderEnabled': reminderEnabled ? 1 : 0,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? 'Personal',
      priority: map['priority'] as String? ?? 'Medium',
      startDate: DateTime.fromMillisecondsSinceEpoch(map['startDate'] as int),
      dueDate: map['dueDate'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['dueDate'] as int),
      reminderDate: map['reminderDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['reminderDate'])
          : null,
      reminderEnabled: (map['reminderEnabled'] as int? ?? 0) == 1,
      isCompleted: (map['isCompleted'] as int? ?? 0) == 1,
    );
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    String? priority,
    DateTime? startDate,
    DateTime? dueDate,
    bool? isCompleted,
    DateTime? reminderDate,
    bool? reminderEnabled,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      isCompleted: isCompleted ?? this.isCompleted,
      reminderDate: reminderDate ?? this.reminderDate,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    );
  }
}
