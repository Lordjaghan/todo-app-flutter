import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/task_provider.dart';

class AddTaskScreen extends ConsumerStatefulWidget {
  const AddTaskScreen({super.key});

  @override
  ConsumerState<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends ConsumerState<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedCategory = 'Personal';
  String _selectedPriority = 'Medium';
  DateTime _selectedStartDate = DateUtils.dateOnly(DateTime.now());
  DateTime? _selectedDueDate;
  bool _reminderEnabled = false;
  DateTime? _selectedReminderDate;
  bool _isSaving = false;
  String? _saveError;

  final List<String> _categories = [
    'Personal',
    'Work',
    'Study',
    'Shopping',
    'Health',
  ];

  final List<String> _priorities = [
    'Low',
    'Medium',
    'High',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final now = DateTime.now();

    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select start date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedStartDate = DateUtils.dateOnly(selected);
        if (_selectedDueDate != null &&
            _selectedDueDate!.isBefore(_selectedStartDate)) {
          _selectedDueDate = null;
        }
      });
    }
  }

  Future<void> _selectDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? _selectedStartDate,
      firstDate: _selectedStartDate,
      lastDate: DateTime(_selectedStartDate.year + 5),
      helpText: 'Select due date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedDueDate = DateUtils.dateOnly(selected);
      });
    }
  }

  Future<void> _selectReminderDateTime() async {
    final baseDate =
        _selectedReminderDate ?? DateTime.now().add(const Duration(minutes: 30));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: baseDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(DateTime.now().year + 5),
      helpText: 'Select reminder date',
    );

    if (!mounted || pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(baseDate),
      helpText: 'Select reminder time',
    );

    if (!mounted || pickedTime == null) return;

    setState(() {
      _selectedReminderDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _saveTask() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }

    if (_reminderEnabled && _selectedReminderDate == null) {
      setState(() {
        _saveError = 'Please select a reminder date and time.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      await ref.read(taskProvider.notifier).addTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        priority: _selectedPriority,
        startDate: _selectedStartDate,
        dueDate: _selectedDueDate,
        reminderEnabled: _reminderEnabled,
        reminderDate: _reminderEnabled ? _selectedReminderDate : null,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = 'Could not save task. Please try again.';
      });
      return;
    }

    if (!mounted) return;

    Navigator.pop(context);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatDateTime(DateTime date) {
    final time = TimeOfDay.fromDateTime(date);
    return '${_formatDate(date)} • ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add Task',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
      ),

      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              20,
              10,
              20,
              30,
            ),
            children: [
              // Header
              const Text(
                'Create a new task',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Add the details of what you need to get done.',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 28),

              // Task title
              const Text(
                'Task title',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 9),

              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Complete Flutter project',
                  prefixIcon: Icon(
                    Icons.task_alt_rounded,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a task title';
                  }

                  if (value.trim().length < 3) {
                    return 'Task title is too short';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 22),

              // Description
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 9),

              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Add some details...',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 65),
                    child: Icon(
                      Icons.notes_rounded,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // Category
              const Text(
                'Category',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 12),

              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: _categories.map((category) {
                  final isSelected =
                      _selectedCategory == category;

                  return ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _selectedCategory = category;
                      });
                    },
                    selectedColor:
                        AppTheme.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppTheme.primary
                          : Colors.grey.shade700,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? AppTheme.primary
                          : const Color(0xFFE5E7EB),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 25),

              // Priority
              const Text(
                'Priority',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: _priorities.map((priority) {
                  final isSelected =
                      _selectedPriority == priority;

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: priority != 'High' ? 8 : 0,
                      ),
                      child: _PriorityButton(
                        priority: priority,
                        selected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedPriority = priority;
                          });
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 25),

              // Start date
              const Text(
                'Start date',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 10),

              InkWell(
                onTap: _selectStartDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 17,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(
                            alpha: 0.10,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          _formatDate(_selectedStartDate),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.text,
                          ),
                        ),
                      ),

                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Reminder toggle
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Enable reminder',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(
                      value: _reminderEnabled,
                      activeThumbColor: AppTheme.primary,
                      onChanged: (value) {
                        setState(() {
                          _reminderEnabled = value;
                          if (!value) {
                            _selectedReminderDate = null;
                          } else {
                            _selectedReminderDate ??= DateTime.now().add(
                              const Duration(minutes: 30),
                            );
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),

              if (_reminderEnabled) ...[
                const SizedBox(height: 20),
                const Text(
                  'Reminder date & time',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _selectReminderDateTime,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 17,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.access_time_rounded,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedReminderDate == null
                                ? 'Choose reminder time'
                                : _formatDateTime(_selectedReminderDate!),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _selectedReminderDate == null
                                  ? Colors.grey
                                  : AppTheme.text,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 15,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Due date
              const Text(
                'Due date',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 10),

              InkWell(
                onTap: _selectDueDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 17,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDueDate == null
                              ? 'Select a due date'
                              : _formatDate(_selectedDueDate!),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _selectedDueDate == null
                                ? Colors.grey
                                : AppTheme.text,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),



              const SizedBox(height: 35),

              if (_saveError != null) ...[
                Text(
                  _saveError!,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
              ],

              // Save button
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _saveTask,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_task_rounded),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Create Task',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Cancel
              SizedBox(
                height: 50,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
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

class _PriorityButton extends StatelessWidget {
  final String priority;
  final bool selected;
  final VoidCallback onTap;

  const _PriorityButton({
    required this.priority,
    required this.selected,
    required this.onTap,
  });

  Color get priorityColor {
    switch (priority) {
      case 'High':
        return const Color(0xFFEF4444);

      case 'Low':
        return const Color(0xFF16A34A);

      default:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = priorityColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 48,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected
                ? color
                : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            priority,
            style: TextStyle(
              color: selected
                  ? color
                  : Colors.grey.shade700,
              fontWeight: selected
                  ? FontWeight.w700
                  : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}