import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/subtask.dart';
import '../../../data/models/task.dart';

class TaskCard extends StatefulWidget {
  final Task task;
  final ValueChanged<TaskStatus> onStatusChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onTogglePin;
  final List<Subtask> subtasks;
  final bool subtasksLoading;
  final String? subtaskError;
  final VoidCallback? onRetrySubtasks;
  final VoidCallback? onAddSubtask;
  final ValueChanged<Subtask>? onEditSubtask;
  final ValueChanged<Subtask>? onDeleteSubtask;
  final ValueChanged<Subtask>? onSubtaskChanged;

  const TaskCard({
    super.key,
    required this.task,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onDelete,
    this.onTogglePin,
    this.subtasks = const [],
    this.subtasksLoading = false,
    this.subtaskError,
    this.onRetrySubtasks,
    this.onAddSubtask,
    this.onEditSubtask,
    this.onDeleteSubtask,
    this.onSubtaskChanged,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _subtasksExpanded = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
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
                    onSelected: widget.onStatusChanged,
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
                  if (widget.subtasks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '${widget.subtasks.where((subtask) => subtask.isCompleted).length}/${widget.subtasks.length} completed',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: LinearProgressIndicator(
                            value:
                                widget.subtasks
                                    .where((subtask) => subtask.isCompleted)
                                    .length /
                                widget.subtasks.length,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(6),
                            color: AppTheme.primary,
                            backgroundColor: AppTheme.primary.withValues(
                              alpha: 0.12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => setState(
                            () => _subtasksExpanded = !_subtasksExpanded,
                          ),
                          icon: Icon(
                            _subtasksExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                          ),
                          label: Text(
                            widget.subtasks.isEmpty
                                ? 'Subtasks'
                                : '${widget.subtasks.length} subtask${widget.subtasks.length == 1 ? '' : 's'}',
                          ),
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(40, 36),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add subtask',
                        onPressed: widget.onAddSubtask,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (_subtasksExpanded) ...[
                    const Divider(height: 8),
                    if (widget.subtasksLoading)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (widget.subtaskError != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.subtaskError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Retry loading subtasks',
                            onPressed: widget.onRetrySubtasks,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      )
                    else if (widget.subtasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'No subtasks yet',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      )
                    else
                      ...widget.subtasks.map(_buildSubtask),
                  ],
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: task.isPinned ? 'Unpin task' : 'Pin task',
                  onPressed: widget.onTogglePin,
                  icon: Icon(
                    task.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    color: task.isPinned ? AppTheme.primary : Colors.grey,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit task',
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete task',
                  onPressed: widget.onDelete,
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

  Widget _buildSubtask(Subtask subtask) {
    final dueDate = subtask.dueDate;
    final overdue =
        !subtask.isCompleted &&
        dueDate != null &&
        DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
          23,
          59,
          59,
        ).isBefore(DateTime.now());
    final statusLabels = {
      SubtaskStatus.pending: 'Pending',
      SubtaskStatus.inProgress: 'In Progress',
      SubtaskStatus.completed: 'Completed',
    };

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtask.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: subtask.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: overdue ? const Color(0xFFB91C1C) : AppTheme.text,
                  ),
                ),
                if (subtask.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtask.description,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
                if (dueDate != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Due: ${DateFormat('dd/MM/yyyy HH:mm').format(dueDate)}${overdue ? ' · Overdue' : ''}',
                    style: TextStyle(
                      color: overdue ? const Color(0xFFB91C1C) : Colors.grey,
                      fontSize: 11,
                      fontWeight: overdue ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Change subtask status',
            onSelected: (status) =>
                widget.onSubtaskChanged?.call(subtask.copyWith(status: status)),
            itemBuilder: (context) => statusLabels.entries
                .map(
                  (entry) => PopupMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                statusLabels[subtask.status] ?? 'Pending',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Edit subtask',
            onPressed: () => widget.onEditSubtask?.call(subtask),
            icon: const Icon(Icons.edit_outlined, size: 17),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Delete subtask',
            onPressed: () => widget.onDeleteSubtask?.call(subtask),
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
