import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/task.dart';
import '../../../services/notification_services.dart';
import '../providers/task_provider.dart';
import '../widgets/task_card.dart';
import 'add_task_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedFilter = 'All';

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
          content: Text('Are you sure you want to delete "${task.title}"?'),
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
      await notifier.setTaskStatus(task, status);
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
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),

                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final task = filteredTasks[index];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),

                            child: TaskCard(
                              task: task,

                              onEdit: () {
                                _openEditTaskScreen(task);
                              },

                              onStatusChanged: (status) {
                                _changeTaskStatus(task, status);
                              },

                              onDelete: () {
                                _deleteTask(task);
                              },
                            ),
                          );
                        }, childCount: filteredTasks.length),
                      ),
                    ),
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
