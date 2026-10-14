import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/subtask.dart';
import '../../../data/models/task.dart';
import '../../../services/notification_services.dart';
import '../providers/task_provider.dart';
import '../widgets/task_card.dart';
import '../widgets/subtask_editor_sheet.dart';
import 'add_task_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedFilter = 'All';
  String _selectedSort = 'Priority';

  final List<String> _sortOptions = ['Priority', 'Due date', 'Creation date'];

  final List<String> _filters = [
    'All',
    'Personal',
    'Work',
    'Study',
    'Shopping',
    'Health',
  ];

  void _openAddTaskScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddTaskScreen()),
    );
  }

  void _openEditTaskScreen(Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddTaskScreen(task: task)),
    );
  }

  Future<void> _refreshTasks() async {
    ref.invalidate(taskProvider);
    await ref.read(taskProvider.future);
  }

  Future<void> _deleteTask(Task task) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Delete task?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Are you sure you want to delete "${task.title}" and all of its subtasks and reminders?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await ref.read(taskProvider.notifier).removeTask(task.id);
    }
  }

  Future<void> _changeTaskStatus(Task task, TaskStatus status) async {
    if (status == task.status) return;
    final notifier = ref.read(taskProvider.notifier);
    if (status == TaskStatus.completed) {
      try {
        await notifier.setTaskStatus(task, status);
      } on IncompleteSubtasksException catch (error) {
        _showMessage(
          'Complete the remaining ${error.remainingCount} subtasks first.',
        );
      } catch (error) {
        _showTaskError(error);
      }
      return;
    }

    final shouldSetReminder = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set a reminder for ${status.label.toLowerCase()}?'),
        content: const Text(
          'You can set an exact date and time or continue without a reminder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (!mounted || shouldSetReminder == null) return;

    DateTime? reminderDate;
    if (shouldSetReminder) {
      final now = DateTime.now();
      final initialDate =
          task.reminderDate ?? now.add(const Duration(minutes: 30));
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
        ),
        firstDate: DateUtils.dateOnly(now),
        lastDate: DateTime(now.year + 5),
        helpText: 'Select reminder date',
      );
      if (!mounted || date == null) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
        helpText: 'Select reminder time',
      );
      if (!mounted || time == null) return;
      reminderDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (!reminderDate.isAfter(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose a reminder time in the future.'),
          ),
        );
        return;
      }
    }

    try {
      await notifier.setTaskStatus(
        task,
        status,
        reminderEnabled: shouldSetReminder,
        reminderDate: reminderDate,
      );
    } on ExactAlarmPermissionDeniedException {
      await notifier.setTaskStatus(task, status, reminderDate: reminderDate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saved without an alarm. The task card will show when it is due.',
            ),
          ),
        );
      }
    } on NotificationPermissionDeniedException {
      await notifier.setTaskStatus(task, status, reminderDate: reminderDate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved without a notification.')),
        );
      }
    } catch (error) {
      _showTaskError(error);
    }
  }

  Future<bool> _confirmReopenParent(Task task) async {
    final shouldReopen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen parent task?'),
        content: Text(
          '"${task.title}" is completed. Reopen it before saving this incomplete subtask?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reopen task'),
          ),
        ],
      ),
    );
    return shouldReopen == true;
  }

  Future<void> _addSubtask(Task task) async {
    final subtask = await showSubtaskEditor(context, parentTask: task);
    if (!mounted || subtask == null) return;
    final reopenParent =
        task.status == TaskStatus.completed && !subtask.isCompleted;
    if (reopenParent && !await _confirmReopenParent(task)) return;

    try {
      await ref
          .read(taskProvider.notifier)
          .addSubtask(
            parentTask: task,
            title: subtask.title,
            description: subtask.description,
            status: subtask.status,
            dueDate: subtask.dueDate,
            reminderEnabled: subtask.reminderEnabled,
            reminderDate: subtask.reminderDate,
            reminderType: subtask.reminderType,
            reopenCompletedParent: reopenParent,
          );
    } catch (error) {
      _showTaskError(error);
    }
  }

  Future<void> _editSubtask(Task task, Subtask subtask) async {
    final updated = await showSubtaskEditor(
      context,
      parentTask: task,
      subtask: subtask,
    );
    if (!mounted || updated == null) return;
    await _saveSubtaskChange(task, updated);
  }

  Future<void> _changeSubtaskStatus(Task task, Subtask subtask) async {
    await _saveSubtaskChange(task, subtask);
  }

  Future<void> _saveSubtaskChange(Task task, Subtask subtask) async {
    final reopenParent =
        task.status == TaskStatus.completed && !subtask.isCompleted;
    if (reopenParent && !await _confirmReopenParent(task)) return;
    try {
      await ref
          .read(taskProvider.notifier)
          .updateSubtask(subtask, reopenCompletedParent: reopenParent);
    } catch (error) {
      _showTaskError(error);
    }
  }

  Future<void> _deleteSubtask(Subtask subtask) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete subtask?'),
        content: Text('Delete "${subtask.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;
    try {
      await ref.read(taskProvider.notifier).removeSubtask(subtask);
    } catch (error) {
      _showTaskError(error);
    }
  }

  Future<void> _toggleTaskPin(Task task) async {
    try {
      await ref.read(taskProvider.notifier).setTaskPinned(task, !task.isPinned);
    } catch (error) {
      _showTaskError(error);
    }
  }

  Future<void> _reorderTasks(
    List<Task> displayedTasks,
    int oldIndex,
    int newIndex, {
    required bool updatePriority,
  }) async {
    if (newIndex < 0 || newIndex > displayedTasks.length - 1) return;
    final reordered = List<Task>.of(displayedTasks);
    final moved = reordered.removeAt(oldIndex);
    final targetIndex = newIndex.clamp(0, reordered.length);
    final destinationPriority = reordered.isEmpty
        ? moved.priority
        : reordered[targetIndex == reordered.length
                  ? targetIndex - 1
                  : targetIndex]
              .priority;
    reordered.insert(
      targetIndex,
      moved.copyWith(
        priority: updatePriority ? destinationPriority : moved.priority,
      ),
    );
    try {
      await ref.read(taskProvider.notifier).saveTaskOrder(reordered);
    } catch (error) {
      _showTaskError(error);
    }
  }

  List<Task> _sortTasks(List<Task> tasks) {
    final sorted = List<Task>.of(tasks);
    sorted.sort((first, second) {
      if (_selectedSort == 'Due date') {
        if (first.dueDate == null && second.dueDate != null) return 1;
        if (second.dueDate == null && first.dueDate != null) return -1;
        final byDueDate = (first.dueDate ?? first.createdAt).compareTo(
          second.dueDate ?? second.createdAt,
        );
        if (byDueDate != 0) return byDueDate;
      } else if (_selectedSort == 'Creation date') {
        final byCreatedAt = second.createdAt.compareTo(first.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
      } else {
        const priorityOrder = {'High': 0, 'Medium': 1, 'Low': 2};
        final byPriority = (priorityOrder[first.priority] ?? 1).compareTo(
          priorityOrder[second.priority] ?? 1,
        );
        if (byPriority != 0) return byPriority;
        final byManualOrder = first.sortOrder.compareTo(second.sortOrder);
        if (byManualOrder != 0) return byManualOrder;
      }
      return first.title.toLowerCase().compareTo(second.title.toLowerCase());
    });
    return sorted;
  }

  Widget _buildTaskCard(
    Task task, {
    int? dragIndex,
    bool showPriority = false,
  }) {
    final card = Consumer(
      builder: (context, ref, _) {
        final subtasksAsync = ref.watch(subtasksProvider(task.id));
        final subtasks = subtasksAsync.when(
          data: (value) => value,
          loading: () => const <Subtask>[],
          error: (_, _) => const <Subtask>[],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPriority)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 7),
                child: Text(
                  '${task.priority} priority',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            TaskCard(
              task: task,
              onEdit: () => _openEditTaskScreen(task),
              onStatusChanged: (status) => _changeTaskStatus(task, status),
              onDelete: () => _deleteTask(task),
              onTogglePin: () => _toggleTaskPin(task),
              subtasks: subtasks,
              subtasksLoading: subtasksAsync.isLoading,
              subtaskError: subtasksAsync.hasError
                  ? 'Could not load subtasks.'
                  : null,
              onRetrySubtasks: () => ref.invalidate(subtasksProvider(task.id)),
              onAddSubtask: () => _addSubtask(task),
              onEditSubtask: (subtask) => _editSubtask(task, subtask),
              onDeleteSubtask: _deleteSubtask,
              onSubtaskChanged: (subtask) =>
                  _changeSubtaskStatus(task, subtask),
            ),
          ],
        );
      },
    );
    final padded = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: card,
    );
    if (dragIndex == null) {
      return Padding(
        key: ValueKey(task.id),
        padding: EdgeInsets.zero,
        child: padded,
      );
    }
    return ReorderableDelayedDragStartListener(
      key: ValueKey(task.id),
      index: dragIndex,
      child: padded,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showTaskError(Object error) {
    if (error is ReminderDateRequiredException) {
      _showMessage('Select a reminder date and time.');
    } else if (error is ReminderTimeInPastException) {
      _showMessage('Choose a reminder time in the future.');
    } else if (error is NotificationPermissionDeniedException) {
      _showMessage('Notification permission was denied.');
    } else if (error is ExactAlarmPermissionDeniedException) {
      _showMessage('Exact alarm permission was denied.');
    } else if (error is ParentTaskReopenRequiredException) {
      _showMessage('Reopen the parent task before saving this subtask.');
    } else {
      _showMessage('Could not save the change. Please try again.');
    }
  }

  List<Task> _filteredTasks(List<Task> tasks) {
    if (_selectedFilter == 'All') {
      return tasks;
    }

    return tasks.where((task) => task.category == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(taskProvider);

    final today = DateTime.now();

    final formattedDate = DateFormat('EEEE, d MMMM').format(today);

    return Scaffold(
      backgroundColor: AppTheme.background,

      body: SafeArea(
        child: tasksAsync.when(
          loading: () {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          },

          error: (error, stackTrace) {
            return _ErrorState(
              onRetry: () {
                ref.invalidate(taskProvider);
              },
            );
          },

          data: (tasks) {
            final completedTasks = tasks
                .where((task) => task.status == TaskStatus.completed)
                .length;
            final onHoldTasks = tasks
                .where((task) => task.status == TaskStatus.onHold)
                .length;
            final inProgressTasks = tasks
                .where((task) => task.status == TaskStatus.inProgress)
                .length;

            final progress = tasks.isEmpty
                ? 0.0
                : completedTasks / tasks.length;

            final filteredTasks = _filteredTasks(tasks);
            final pinnedTasks = _sortTasks(
              filteredTasks.where((task) => task.isPinned).toList(),
            );
            final regularTasks = _sortTasks(
              filteredTasks.where((task) => !task.isPinned).toList(),
            );
            final canReorder =
                _selectedSort == 'Priority' && _selectedFilter == 'All';

            return RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _refreshTasks,

              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),

                slivers: [
                  // --------------------------------------------------
                  // HEADER
                  // --------------------------------------------------

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),

                    sliver: SliverToBoxAdapter(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                Text(
                                  formattedDate,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),

                                const SizedBox(height: 6),

                                const Text(
                                  'Good morning 👋',
                                  style: TextStyle(
                                    fontSize: 27,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.7,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                const Text(
                                  'Let\'s get things done.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Profile / settings button
                          Container(
                            width: 46,
                            height: 46,

                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),

                              border: Border.all(
                                color: const Color(0xFFEAEAF2),
                              ),
                            ),

                            child: const Icon(
                              Icons.person_outline_rounded,
                              color: AppTheme.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --------------------------------------------------
                  // PROGRESS CARD
                  // --------------------------------------------------
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),

                    sliver: SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.all(22),

                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,

                            colors: [Color(0xFF756CFF), Color(0xFF5B52E8)],
                          ),

                          borderRadius: BorderRadius.circular(24),

                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.20),

                              blurRadius: 25,

                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,

                                    children: [
                                      Text(
                                        'TODAY\'S PROGRESS',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                        ),
                                      ),

                                      SizedBox(height: 8),

                                      Text(
                                        'Keep going!',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                Container(
                                  width: 58,
                                  height: 58,

                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),

                                    shape: BoxShape.circle,
                                  ),

                                  child: Center(
                                    child: Text(
                                      '${(progress * 100).round()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 22),

                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),

                              child: LinearProgressIndicator(
                                value: progress,

                                minHeight: 8,

                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.20,
                                ),

                                color: Colors.white,
                              ),
                            ),

                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$completedTasks completed',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),

                                Text(
                                  '$inProgressTasks in progress',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // --------------------------------------------------
                  // STATISTICS
                  // --------------------------------------------------
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),

                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              icon: Icons.check_circle_outline_rounded,
                              title: 'Completed',
                              value: '$completedTasks',
                              iconColor: const Color(0xFF16A34A),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: _StatCard(
                              icon: Icons.pending_actions_rounded,
                              title: 'In Progress',
                              value: '$inProgressTasks',
                              iconColor: const Color(0xFFF59E0B),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: _StatCard(
                              icon: Icons.pause_circle_outline_rounded,
                              title: 'On Hold',
                              value: '$onHoldTasks',
                              iconColor: const Color(0xFFCA8A04),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --------------------------------------------------
                  // TASK HEADER
                  // --------------------------------------------------
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),

                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'My Tasks',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),

                          Text(
                            '${filteredTasks.length} tasks',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            tooltip: 'Sort tasks',
                            onSelected: (sort) {
                              setState(() => _selectedSort = sort);
                            },
                            itemBuilder: (context) => _sortOptions
                                .map(
                                  (sort) => PopupMenuItem<String>(
                                    value: sort,
                                    child: Text(sort),
                                  ),
                                )
                                .toList(),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.sort_rounded, size: 19),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedSort,
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --------------------------------------------------
                  // FILTERS
                  // --------------------------------------------------
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 58,

                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),

                        scrollDirection: Axis.horizontal,

                        itemCount: _filters.length,

                        separatorBuilder: (_, _) => const SizedBox(width: 8),

                        itemBuilder: (context, index) {
                          final filter = _filters[index];

                          final selected = _selectedFilter == filter;

                          return ChoiceChip(
                            label: Text(filter),

                            selected: selected,

                            onSelected: (_) {
                              setState(() {
                                _selectedFilter = filter;
                              });
                            },

                            selectedColor: AppTheme.primary.withValues(
                              alpha: 0.12,
                            ),

                            backgroundColor: Colors.white,

                            checkmarkColor: AppTheme.primary,

                            labelStyle: TextStyle(
                              color: selected
                                  ? AppTheme.primary
                                  : Colors.grey.shade700,

                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,

                              fontSize: 12,
                            ),

                            side: BorderSide(
                              color: selected
                                  ? AppTheme.primary
                                  : const Color(0xFFE5E7EB),
                            ),

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // --------------------------------------------------
                  // TASK LIST
                  // --------------------------------------------------
                  if (filteredTasks.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,

                      child: _EmptyTasks(
                        filter: _selectedFilter,
                        onAddTask: _openAddTaskScreen,
                      ),
                    )
                  else ...[
                    if (pinnedTasks.isNotEmpty) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.push_pin_rounded,
                                size: 16,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'Pinned',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                '${pinnedTasks.length}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        sliver: canReorder
                            ? SliverToBoxAdapter(
                                child: ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  itemCount: pinnedTasks.length,
                                  onReorderItem: (oldIndex, newIndex) =>
                                      _reorderTasks(
                                        pinnedTasks,
                                        oldIndex,
                                        newIndex,
                                        updatePriority: false,
                                      ),
                                  itemBuilder: (context, index) =>
                                      _buildTaskCard(
                                        pinnedTasks[index],
                                        dragIndex: index,
                                      ),
                                ),
                              )
                            : SliverList.builder(
                                itemCount: pinnedTasks.length,
                                itemBuilder: (context, index) =>
                                    _buildTaskCard(pinnedTasks[index]),
                              ),
                      ),
                    ],
                    if (regularTasks.isNotEmpty) ...[
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          pinnedTasks.isEmpty ? 16 : 22,
                          20,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            pinnedTasks.isEmpty ? 'Tasks' : 'Other tasks',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
                        sliver: canReorder
                            ? SliverToBoxAdapter(
                                child: ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  itemCount: regularTasks.length,
                                  onReorderItem: (oldIndex, newIndex) =>
                                      _reorderTasks(
                                        regularTasks,
                                        oldIndex,
                                        newIndex,
                                        updatePriority: true,
                                      ),
                                  itemBuilder: (context, index) {
                                    final task = regularTasks[index];
                                    final startsPriorityGroup =
                                        index == 0 ||
                                        regularTasks[index - 1].priority !=
                                            task.priority;
                                    return _buildTaskCard(
                                      task,
                                      dragIndex: index,
                                      showPriority: startsPriorityGroup,
                                    );
                                  },
                                ),
                              )
                            : SliverList.builder(
                                itemCount: regularTasks.length,
                                itemBuilder: (context, index) =>
                                    _buildTaskCard(regularTasks[index]),
                              ),
                      ),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),

      // --------------------------------------------------
      // ADD TASK BUTTON
      // --------------------------------------------------
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTaskScreen,

        backgroundColor: AppTheme.primary,

        foregroundColor: Colors.white,

        elevation: 5,

        icon: const Icon(Icons.add_rounded),

        label: const Text(
          'Add task',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ==========================================================
// STAT CARD
// ==========================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color iconColor;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: const Color(0xFFEAEAF2)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Container(
            width: 34,
            height: 34,

            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),

              borderRadius: BorderRadius.circular(10),
            ),

            child: Icon(icon, size: 18, color: iconColor),
          ),

          const SizedBox(height: 12),

          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 2),

          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================================
// EMPTY TASK STATE
// ==========================================================

class _EmptyTasks extends StatelessWidget {
  final String filter;
  final VoidCallback onAddTask;

  const _EmptyTasks({required this.filter, required this.onAddTask});

  @override
  Widget build(BuildContext context) {
    final isFiltered = filter != 'All';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 85,
              height: 85,

              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),

                shape: BoxShape.circle,
              ),

              child: const Icon(
                Icons.task_alt_rounded,
                size: 42,
                color: AppTheme.primary,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              isFiltered ? 'No $filter tasks' : 'No tasks yet',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 8),

            Text(
              isFiltered
                  ? 'There are no tasks in this category.'
                  : 'Create your first task and start getting things done.',
              textAlign: TextAlign.center,

              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 22),

            if (!isFiltered)
              FilledButton.icon(
                onPressed: onAddTask,

                icon: const Icon(Icons.add_rounded),

                label: const Text('Create task'),
              ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// ERROR STATE
// ==========================================================

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            const Icon(Icons.cloud_off_rounded, size: 55, color: Colors.grey),

            const SizedBox(height: 16),

            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 8),

            const Text(
              'We couldn\'t load your tasks.',
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 18),

            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
