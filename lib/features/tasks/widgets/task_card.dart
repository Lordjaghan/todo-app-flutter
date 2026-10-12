import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/task.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final ValueChanged<TaskStatus> onStatusChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final priorityColor = switch (task.priority) {
      'High' => const Color(0xFFEF4444),
      'Low' => const Color(0xFF16A34A),
      _ => const Color(0xFFF59E0B),
    };
    final urgencyDate =
        task.reminderDate ??
        (task.dueDate == null
            ? null
            : DateTime(
                task.dueDate!.year,
                task.dueDate!.month,
                task.dueDate!.day,
                23,
                59,
                59,
              ));
    final now = DateTime.now();
    final cardColor = task.status == TaskStatus.completed || urgencyDate == null
        ? null
        : !urgencyDate.isAfter(now)
        ? const Color(0xFFFFE4E4)
        : urgencyDate.difference(now) <= const Duration(hours: 1)
        ? const Color(0xFFFFF2CC)
        : null;

    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (task.hasReminder)
              Tooltip(
                message: 'Exact reminder enabled',
                child: Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
              )
            else
              const SizedBox(width: 30),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            decoration: task.status == TaskStatus.completed
                                ? TextDecoration.lineThrough
                                : null,
                            color: task.status == TaskStatus.completed
                                ? Colors.grey
                                : AppTheme.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PopupMenuButton<TaskStatus>(
                    tooltip: 'Change task status',
                    onSelected: onStatusChanged,
                    itemBuilder: (context) => TaskStatus.values
                        .map(
                          (status) => PopupMenuItem<TaskStatus>(
                            value: status,
                            child: Text(status.label),
                          ),
                        )
                        .toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            task.status.label,
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      task.description,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: priorityColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          task.priority,
                          style: TextStyle(
                            color: priorityColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        task.category,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Start: ${DateFormat('dd/MM/yyyy').format(task.startDate)}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      if (task.dueDate != null)
                        Text(
                          'Due: ${DateFormat('dd/MM/yyyy').format(task.dueDate!)}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit task',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete task',
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
