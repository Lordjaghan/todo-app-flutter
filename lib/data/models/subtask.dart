class SubtaskStatus {
  static const String pending = 'pending';
  static const String inProgress = 'inProgress';
  static const String completed = 'completed';

  const SubtaskStatus._();
}

class Subtask {
  final String id;
  final String parentTaskId;
  final String title;
  final String description;
  final String status;
  final DateTime? dueDate;
  final DateTime? reminderDate;
  final bool reminderEnabled;
  final String reminderType;
  final int? notificationId;
  final int sortOrder;

  const Subtask({
    required this.id,
    required this.parentTaskId,
    required this.title,
    this.description = '',
    this.status = SubtaskStatus.pending,
    this.dueDate,
    this.reminderDate,
    this.reminderEnabled = false,
    this.reminderType = 'notification',
    this.notificationId,
    this.sortOrder = 0,
  });

  int get reminderNotificationId =>
      notificationId ?? (id.hashCode & 0x7fffffff);

  bool get hasReminder => reminderEnabled && reminderDate != null;

  bool get isCompleted => status == SubtaskStatus.completed;

  Map<String, dynamic> toMap() => {
    'id': id,
    'parentTaskId': parentTaskId,
    'title': title,
    'description': description,
    'status': status,
    'dueDate': dueDate?.millisecondsSinceEpoch,
    'reminderDate': reminderDate?.millisecondsSinceEpoch,
    'reminderEnabled': reminderEnabled ? 1 : 0,
    'reminderType': reminderType,
    'notificationId': notificationId,
    'sortOrder': sortOrder,
  };

  factory Subtask.fromMap(Map<String, dynamic> map) => Subtask(
    id: map['id'] as String,
    parentTaskId: map['parentTaskId'] as String,
    title: map['title'] as String,
    description: map['description'] as String? ?? '',
    status: map['status'] as String? ?? SubtaskStatus.pending,
    dueDate: map['dueDate'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['dueDate'] as int),
    reminderDate: map['reminderDate'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['reminderDate'] as int),
    reminderEnabled: (map['reminderEnabled'] as int? ?? 0) == 1,
    reminderType: map['reminderType'] as String? ?? 'notification',
    notificationId: map['notificationId'] as int?,
    sortOrder: map['sortOrder'] as int? ?? 0,
  );

  Subtask copyWith({
    String? title,
    String? description,
    String? status,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? reminderDate,
    bool clearReminder = false,
    bool? reminderEnabled,
    String? reminderType,
    int? notificationId,
    int? sortOrder,
  }) => Subtask(
    id: id,
    parentTaskId: parentTaskId,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    reminderDate: clearReminder ? null : (reminderDate ?? this.reminderDate),
    reminderEnabled: clearReminder
        ? false
        : (reminderEnabled ?? this.reminderEnabled),
    reminderType: reminderType ?? this.reminderType,
    notificationId: notificationId ?? this.notificationId,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}
