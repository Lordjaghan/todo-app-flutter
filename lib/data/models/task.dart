class ReminderType {
  static const String notification = 'notification';
  static const String alarm = 'alarm';

  const ReminderType._();
}

enum TaskStatus {
  inProgress,
  onHold,
  completed;

  String get label => switch (this) {
    inProgress => 'In Progress',
    onHold => 'On Hold',
    completed => 'Completed',
  };
}

class Task {
  final String id;
  final String title;
  final String description;
  final String category;
  final String priority;
  final bool isPinned;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime startDate;
  final DateTime? dueDate;
  final TaskStatus status;
  final DateTime? reminderDate;
  final bool reminderEnabled;
  final String reminderType;
  final int? notificationId;

  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.category = 'Personal',
    this.priority = 'Medium',
    this.isPinned = false,
    this.sortOrder = 0,
    DateTime? createdAt,
    required this.startDate,
    this.dueDate,
    TaskStatus? status,
    this.reminderDate,
    this.reminderEnabled = false,
    this.reminderType = ReminderType.alarm,
    this.notificationId,
  }) : createdAt = createdAt ?? startDate,
       status = status ?? TaskStatus.inProgress;

  /// Id used with the notification plugin. Tasks created before
  /// [notificationId] existed fall back to the id they were scheduled with.
  int get reminderNotificationId =>
      notificationId ?? (id.hashCode & 0x7fffffff);

  bool get hasReminder => reminderEnabled && reminderDate != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'priority': priority,
      'isPinned': isPinned ? 1 : 0,
      'sortOrder': sortOrder,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'startDate': startDate.millisecondsSinceEpoch,
      'dueDate': dueDate?.millisecondsSinceEpoch,
      'status': status.name,
      'reminderDate': reminderDate?.millisecondsSinceEpoch,
      'reminderEnabled': reminderEnabled ? 1 : 0,
      'reminderType': reminderType,
      'notificationId': notificationId,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    final storedStatus = map['status'] as String?;
    final legacyIsCompleted = map['isCompleted'] as int? ?? 0;
    final startDate = DateTime.fromMillisecondsSinceEpoch(
      map['startDate'] as int,
    );

    return Task(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? 'Personal',
      priority: map['priority'] as String? ?? 'Medium',
      isPinned: (map['isPinned'] as int? ?? 0) == 1,
      sortOrder: map['sortOrder'] as int? ?? 0,
      createdAt: map['createdAt'] == null
          ? startDate
          : DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      startDate: startDate,
      dueDate: map['dueDate'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['dueDate'] as int),
      reminderDate: map['reminderDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['reminderDate'] as int)
          : null,
      reminderEnabled: (map['reminderEnabled'] as int? ?? 0) == 1,
      reminderType: map['reminderType'] as String? ?? ReminderType.notification,
      notificationId: map['notificationId'] as int?,
      status: storedStatus == null
          ? (legacyIsCompleted == 1
                ? TaskStatus.completed
                : TaskStatus.inProgress)
          : TaskStatus.values.firstWhere(
              (status) => status.name == storedStatus,
              orElse: () => TaskStatus.inProgress,
            ),
    );
  }

  /// Pass [clearDueDate] / [clearReminder] to explicitly reset those values to
  /// null, since a null argument otherwise means "keep the current value".
  Task copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    String? priority,
    bool? isPinned,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? startDate,
    DateTime? dueDate,
    bool clearDueDate = false,
    TaskStatus? status,
    DateTime? reminderDate,
    bool? reminderEnabled,
    bool clearReminder = false,
    String? reminderType,
    int? notificationId,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      isPinned: isPinned ?? this.isPinned,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      startDate: startDate ?? this.startDate,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      status: status ?? this.status,
      reminderDate: clearReminder ? null : (reminderDate ?? this.reminderDate),
      reminderEnabled: clearReminder
          ? false
          : (reminderEnabled ?? this.reminderEnabled),
      reminderType: reminderType ?? this.reminderType,
      notificationId: notificationId ?? this.notificationId,
    );
  }
}
