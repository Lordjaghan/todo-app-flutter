import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/subtask.dart';
import '../../../data/models/task.dart';

Future<Subtask?> showSubtaskEditor(
  BuildContext context, {
  required Task parentTask,
  Subtask? subtask,
}) {
  return showModalBottomSheet<Subtask>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        _SubtaskEditorSheet(parentTask: parentTask, subtask: subtask),
  );
}

class _SubtaskEditorSheet extends StatefulWidget {
  const _SubtaskEditorSheet({required this.parentTask, this.subtask});

  final Task parentTask;
  final Subtask? subtask;

  @override
  State<_SubtaskEditorSheet> createState() => _SubtaskEditorSheetState();
}

class _SubtaskEditorSheetState extends State<_SubtaskEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  late String _status;
  DateTime? _dueDate;
  DateTime? _reminderDate;
  bool _reminderEnabled = false;
  String? _dateError;

  static const _statuses = [
    SubtaskStatus.pending,
    SubtaskStatus.inProgress,
    SubtaskStatus.completed,
  ];

  @override
  void initState() {
    super.initState();
    final subtask = widget.subtask;
    _titleController.text = subtask?.title ?? '';
    _descriptionController.text = subtask?.description ?? '';
    _status = subtask?.status ?? SubtaskStatus.pending;
    _dueDate = subtask?.dueDate;
    _reminderDate = subtask?.reminderDate;
    _reminderEnabled = subtask?.reminderEnabled ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime({required bool reminder}) async {
    final now = DateTime.now();
    final current = reminder
        ? (_reminderDate ?? now.add(const Duration(minutes: 30)))
        : (_dueDate ?? widget.parentTask.dueDate ?? now);
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateUtils.dateOnly(current),
      firstDate: reminder ? DateUtils.dateOnly(now) : DateTime(1900),
      lastDate: DateTime(now.year + 10),
      helpText: reminder ? 'Select reminder date' : 'Select subtask due date',
    );
    if (!mounted || selectedDate == null) return null;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: reminder ? 'Select reminder time' : 'Select due time',
    );
    if (!mounted || selectedTime == null) return null;

    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
  }

  Future<void> _selectDueDate() async {
    final selected = await _pickDateTime(reminder: false);
    if (selected == null) return;
    setState(() {
      _dueDate = selected;
      _dateError = null;
    });
  }

  Future<void> _selectReminderDate() async {
    final selected = await _pickDateTime(reminder: true);
    if (selected == null) return;
    setState(() {
      _reminderDate = selected;
      _dateError = null;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    if (_dueDate != null && _dueDate!.isBefore(widget.parentTask.startDate)) {
      setState(
        () => _dateError = 'Due time cannot be before the parent start date.',
      );
      return;
    }
    if (_dueDate != null && widget.parentTask.dueDate != null) {
      final parentDueEnd = DateTime(
        widget.parentTask.dueDate!.year,
        widget.parentTask.dueDate!.month,
        widget.parentTask.dueDate!.day,
        23,
        59,
      );
      if (_dueDate!.isAfter(parentDueEnd)) {
        setState(
          () => _dateError = 'Due time cannot be after the parent due date.',
        );
        return;
      }
    }
    if (_reminderEnabled && _reminderDate == null) {
      setState(() => _dateError = 'Select a reminder date and time.');
      return;
    }
    if (_reminderEnabled && !_reminderDate!.isAfter(now)) {
      setState(() => _dateError = 'Choose a reminder time in the future.');
      return;
    }
    if (_reminderEnabled &&
        _dueDate != null &&
        _reminderDate!.isAfter(_dueDate!)) {
      setState(
        () => _dateError = 'Reminder time cannot be after the due time.',
      );
      return;
    }

    final existing = widget.subtask;
    Navigator.pop(
      context,
      Subtask(
        id: existing?.id ?? const Uuid().v4(),
        parentTaskId: widget.parentTask.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        status: _status,
        dueDate: _dueDate,
        reminderDate: _reminderEnabled ? _reminderDate : null,
        reminderEnabled: _reminderEnabled,
        reminderType: existing?.reminderType ?? 'notification',
        notificationId: existing?.notificationId,
        sortOrder: existing?.sortOrder ?? 0,
      ),
    );
  }

  String _formatDateTime(DateTime date) =>
      DateFormat('dd/MM/yyyy HH:mm').format(date);

  @override
  Widget build(BuildContext context) {
    final statusLabels = {
      SubtaskStatus.pending: 'Pending',
      SubtaskStatus.inProgress: 'In Progress',
      SubtaskStatus.completed: 'Completed',
    };

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.subtask == null ? 'Add subtask' : 'Edit subtask',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Subtask name',
                  prefixIcon: Icon(Icons.checklist_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a subtask name.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: _statuses
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(statusLabels[status]!),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _selectDueDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _dueDate == null
                      ? 'Set due date and time'
                      : 'Due: ${_formatDateTime(_dueDate!)}',
                ),
              ),
              if (_dueDate != null)
                TextButton(
                  onPressed: () => setState(() => _dueDate = null),
                  child: const Text('Clear due date'),
                ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reminder'),
                value: _reminderEnabled,
                onChanged: (value) => setState(() {
                  _reminderEnabled = value;
                  _dateError = null;
                }),
              ),
              if (_reminderEnabled)
                OutlinedButton.icon(
                  onPressed: _selectReminderDate,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(
                    _reminderDate == null
                        ? 'Set reminder date and time'
                        : 'Reminder: ${_formatDateTime(_reminderDate!)}',
                  ),
                ),
              if (_dateError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _dateError!,
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    widget.subtask == null ? 'Add subtask' : 'Save subtask',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
