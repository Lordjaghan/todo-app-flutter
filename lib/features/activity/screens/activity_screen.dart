import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/activity.dart';
import '../../../data/repositories/activity_repository.dart';
import '../analytics/activity_analytics.dart';
import '../providers/activity_provider.dart';
import 'activity_calendar_view.dart';
import 'activity_reports_view.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  ActivityCategory? _categoryFilter;
  String _search = '';
  bool _includeArchived = false;
  bool _selectedDateOnly = false;
  ActivityStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(activityProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            tooltip: 'Choose date',
            onPressed: _chooseDay,
            icon: const Icon(Icons.calendar_month_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Quick actions',
            onSelected: _quickAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'habit', child: Text('Add habit')),
              PopupMenuItem(value: 'routine', child: Text('Add routine')),
              PopupMenuItem(value: 'session', child: Text('Log activity')),
              PopupMenuItem(value: 'timer', child: Text('Start timed session')),
              PopupMenuItem(value: 'goal', child: Text('Set a goal')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Habits'),
            Tab(text: 'Sessions'),
            Tab(text: 'Routines'),
            Tab(text: 'Calendar'),
            Tab(text: 'Reports'),
          ],
        ),
      ),
      body: activity.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _errorState(
          'Could not load activity.',
          () => ref.invalidate(activityProvider),
        ),
        data: (snapshot) => TabBarView(
          controller: _tabs,
          children: [
            _overview(snapshot),
            _habits(snapshot),
            _sessions(snapshot),
            _routines(snapshot),
            ActivityCalendarView(
              snapshot: snapshot,
              selectedDay: _selectedDay,
              onSelectDay: (day) => setState(() => _selectedDay = day),
            ),
            ActivityReportsView(
              snapshot: snapshot,
              anchor: _selectedDay,
              onSetGoal: _setGoal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview(ActivitySnapshot snapshot) {
    final report = ActivityAnalytics.buildReport(
      snapshot,
      range: ReportRange.daily,
      anchor: _selectedDay,
    );
    final activeHabits = snapshot.habits
        .where((habit) => !habit.archived)
        .toList();
    final sessions = _sessionsForSelectedDay(snapshot)
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _daySelector(),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric('Active minutes', '${report.activeMinutes}'),
            _metric('Habit check-ins', '${report.completedHabits}'),
            _metric(
              'Completion',
              report.completionPercent == null
                  ? '—'
                  : '${report.completionPercent}%',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _sectionHeader('Habits', 'Manage', () => _tabs.animateTo(1)),
        if (activeHabits.isEmpty)
          _emptyState('No habits yet', 'Add a habit to begin tracking.')
        else
          ...activeHabits.take(5).map((habit) => _habitTile(snapshot, habit)),
        const SizedBox(height: 18),
        _sectionHeader('Recent sessions', 'View all', () => _tabs.animateTo(2)),
        if (sessions.isEmpty)
          _emptyState(
            'No activity logged',
            'Your saved sessions will appear here.',
          )
        else
          ...sessions.take(4).map(_sessionTile),
      ],
    );
  }

  Widget _habits(ActivitySnapshot snapshot) {
    final habits = snapshot.habits
        .where((habit) => habit.archived == _includeArchived)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(DateFormat('EEEE, MMM d').format(_selectedDay)),
            ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _includeArchived = !_includeArchived),
              icon: Icon(
                _includeArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              label: Text(_includeArchived ? 'Active' : 'Archived'),
            ),
            IconButton(
              tooltip: 'Add habit',
              onPressed: () => _editHabit(),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (habits.isEmpty)
          _emptyState(
            _includeArchived ? 'No archived habits' : 'No habits yet',
            _includeArchived
                ? 'Archived habits keep their completion history.'
                : 'Create a daily or weekly target.',
          )
        else
          ...habits.map(
            (habit) => _habitTile(snapshot, habit, management: true),
          ),
      ],
    );
  }

  Widget _habitTile(
    ActivitySnapshot snapshot,
    Habit habit, {
    bool management = false,
  }) {
    final checkIns = snapshot.habitCheckIns.where(
      (item) =>
          item.habitId == habit.id &&
          item.dayKey == activityDayKey(_selectedDay) &&
          item.status == ActivityStatus.completed,
    );
    final completedToday = checkIns.length;
    final streak = ActivityAnalytics.streakForHabit(
      habit,
      snapshot.habitCheckIns,
      through: _selectedDay,
    );
    final met = habit.period == ActivityPeriod.daily
        ? completedToday >= habit.targetCount
        : _countThisWeek(snapshot, habit) >= habit.targetCount;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: Icon(met ? Icons.check_circle_rounded : Icons.circle_outlined),
        title: Text(habit.title),
        subtitle: Text(
          '${habit.period.name} · ${habit.period == ActivityPeriod.daily ? completedToday : _countThisWeek(snapshot, habit)}/${habit.targetCount} · ${streak.current} ${habit.period == ActivityPeriod.daily ? 'day' : 'week'} streak',
        ),
        trailing: management
            ? PopupMenuButton<String>(
                tooltip: 'Habit actions',
                onSelected: (value) {
                  if (value == 'edit') _editHabit(habit);
                  ref
                      .read(activityProvider.notifier)
                      .archiveHabit(habit, value == 'archive');
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: habit.archived ? 'restore' : 'archive',
                    child: Text(habit.archived ? 'Restore' : 'Archive'),
                  ),
                ],
              )
            : PopupMenuButton<ActivityStatus>(
                tooltip: 'Record habit',
                onSelected: (status) => _recordHabit(habit, status),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: ActivityStatus.completed,
                    child: Text('Complete'),
                  ),
                  PopupMenuItem(
                    value: ActivityStatus.skipped,
                    child: Text('Skip'),
                  ),
                ],
                icon: const Icon(Icons.add_task_rounded),
              ),
      ),
    );
  }

  Widget _sessions(ActivitySnapshot snapshot) {
    final sessions = snapshot.sessions.where((session) {
      final categoryMatches =
          _categoryFilter == null || session.category == _categoryFilter;
      final searchMatches =
          _search.isEmpty || session.title.toLowerCase().contains(_search);
      final dateMatches =
          !_selectedDateOnly || session.dayKey == activityDayKey(_selectedDay);
      final statusMatches =
          _statusFilter == null || session.status == _statusFilter;
      return categoryMatches && searchMatches && dateMatches && statusMatches;
    }).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search sessions',
          ),
          onChanged: (value) => setState(() => _search = value.toLowerCase()),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            _categoryChip(null, 'All'),
            _categoryChip(ActivityCategory.cardio, 'Cardio'),
            _categoryChip(ActivityCategory.reading, 'Reading'),
            _categoryChip(ActivityCategory.writing, 'Writing'),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All dates'),
              selected: !_selectedDateOnly,
              onSelected: (_) => setState(() => _selectedDateOnly = false),
            ),
            ChoiceChip(
              label: const Text('Selected date'),
              selected: _selectedDateOnly,
              onSelected: (_) => setState(() => _selectedDateOnly = true),
            ),
            ChoiceChip(
              label: const Text('All status'),
              selected: _statusFilter == null,
              onSelected: (_) => setState(() => _statusFilter = null),
            ),
            ChoiceChip(
              label: const Text('Completed'),
              selected: _statusFilter == ActivityStatus.completed,
              onSelected: (_) =>
                  setState(() => _statusFilter = ActivityStatus.completed),
            ),
            ChoiceChip(
              label: const Text('Skipped'),
              selected: _statusFilter == ActivityStatus.skipped,
              onSelected: (_) =>
                  setState(() => _statusFilter = ActivityStatus.skipped),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Text('Saved sessions')),
            IconButton(
              tooltip: 'Log activity',
              onPressed: _chooseSessionCategory,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (sessions.isEmpty)
          _emptyState('No matching activity', 'Log a session to see it here.')
        else
          ...sessions.map(_sessionTile),
      ],
    );
  }

  Widget _routines(ActivitySnapshot snapshot) {
    final routines = snapshot.routines.where((item) => !item.archived);
    final dayKey = activityDayKey(_selectedDay);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(DateFormat('EEEE, MMM d').format(_selectedDay)),
            ),
            IconButton(
              tooltip: 'Add routine',
              onPressed: _createRoutine,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (routines.isEmpty)
          _emptyState('No routines yet', 'Add an ordered reusable routine.')
        else
          ...routines.map((routine) {
            final steps =
                snapshot.routineSteps
                    .where((step) => step.routineId == routine.id)
                    .toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
            return Card(
              margin: const EdgeInsets.only(top: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(routine.period),
                    for (final step in steps)
                      _routineStepTile(snapshot, step, dayKey),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _routineStepTile(
    ActivitySnapshot snapshot,
    RoutineStep step,
    String dayKey,
  ) {
    final record = snapshot.routineStepCheckIns
        .where((item) => item.stepId == step.id && item.dayKey == dayKey)
        .firstOrNull;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        record?.status == ActivityStatus.completed
            ? Icons.check_circle_outline
            : Icons.circle_outlined,
      ),
      title: Text(step.title),
      trailing: PopupMenuButton<ActivityStatus>(
        tooltip: 'Update routine step',
        onSelected: (status) => _setRoutineStep(step, status),
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: ActivityStatus.completed,
            child: Text('Complete'),
          ),
          PopupMenuItem(value: ActivityStatus.skipped, child: Text('Skip')),
        ],
      ),
    );
  }

  Widget _daySelector() => Row(
    children: [
      IconButton(
        tooltip: 'Previous day',
        onPressed: () => _moveDay(-1),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Text(
          DateFormat('EEEE, MMM d').format(_selectedDay),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconButton(
        tooltip: 'Next day',
        onPressed: () => _moveDay(1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  Widget _categoryChip(ActivityCategory? category, String label) => ChoiceChip(
    label: Text(label),
    selected: _categoryFilter == category,
    onSelected: (_) => setState(() => _categoryFilter = category),
  );

  Widget _sessionTile(ActivitySession session) => Card(
    margin: const EdgeInsets.only(top: 8),
    child: ListTile(
      leading: Icon(_categoryIcon(session.category)),
      title: Text(session.title),
      subtitle: Text(
        '${session.durationMinutes} min · ${DateFormat('MMM d, h:mm a').format(session.startedAt)}${_sessionDetails(session)}${session.status == ActivityStatus.skipped ? ' · Skipped' : ''}',
      ),
      trailing: IconButton(
        tooltip: 'Delete session',
        onPressed: () =>
            ref.read(activityProvider.notifier).deleteSession(session.id),
        icon: const Icon(Icons.delete_outline),
      ),
    ),
  );

  Widget _metric(String label, String value) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );

  Widget _sectionHeader(String title, String action, VoidCallback onTap) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      TextButton(onPressed: onTap, child: Text(action)),
    ],
  );

  Widget _emptyState(String title, String detail) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        const Icon(Icons.event_note_outlined, size: 30),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(detail, textAlign: TextAlign.center),
      ],
    ),
  );

  Widget _errorState(String message, VoidCallback onRetry) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        const SizedBox(height: 8),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );

  List<ActivitySession> _sessionsForSelectedDay(ActivitySnapshot snapshot) =>
      snapshot.sessions
          .where((session) => session.dayKey == activityDayKey(_selectedDay))
          .toList();

  int _countThisWeek(ActivitySnapshot snapshot, Habit habit) {
    final weekStart = _selectedDay.subtract(
      Duration(days: _selectedDay.weekday - DateTime.monday),
    );
    final weekEnd = weekStart.add(const Duration(days: 7));
    return snapshot.habitCheckIns.where((item) {
      final day = DateTime.parse(item.dayKey);
      return item.habitId == habit.id &&
          item.status == ActivityStatus.completed &&
          !day.isBefore(weekStart) &&
          day.isBefore(weekEnd);
    }).length;
  }

  String _sessionDetails(ActivitySession session) {
    final values = <String>[];
    if (session.distanceKm != null) values.add('${session.distanceKm} km');
    if (session.calories != null) values.add('${session.calories} kcal');
    if (session.pages != null) values.add('${session.pages} pages');
    if (session.words != null) values.add('${session.words} words');
    return values.isEmpty ? '' : ' · ${values.join(' · ')}';
  }

  String _categoryName(ActivityCategory category) => switch (category) {
    ActivityCategory.cardio => 'Cardio',
    ActivityCategory.reading => 'Reading',
    ActivityCategory.writing => 'Writing',
  };

  IconData _categoryIcon(ActivityCategory category) => switch (category) {
    ActivityCategory.cardio => Icons.directions_run_rounded,
    ActivityCategory.reading => Icons.menu_book_rounded,
    ActivityCategory.writing => Icons.edit_note_rounded,
  };

  void _moveDay(int offset) =>
      setState(() => _selectedDay = _selectedDay.add(Duration(days: offset)));

  Future<void> _chooseDay() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (result != null) setState(() => _selectedDay = result);
  }

  Future<void> _quickAction(String action) async {
    switch (action) {
      case 'habit':
        await _editHabit();
        break;
      case 'routine':
        await _createRoutine();
        break;
      case 'session':
        await _chooseSessionCategory();
        break;
      case 'timer':
        await _startTimedSession();
        break;
      case 'goal':
        await _setGoal();
        break;
    }
  }

  Future<void> _recordHabit(Habit habit, ActivityStatus status) async {
    _HabitCheckInDraft? draft;
    if (status == ActivityStatus.completed) {
      draft = await showDialog<_HabitCheckInDraft>(
        context: context,
        builder: (context) => _HabitCheckInDialog(habitTitle: habit.title),
      );
      if (draft == null) return;
    }
    try {
      await ref
          .read(activityProvider.notifier)
          .recordHabit(
            habit: habit,
            status: status,
            day: _selectedDay,
            value: draft?.value,
            durationMinutes: draft?.durationMinutes,
          );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editHabit([Habit? existing]) async {
    final draft = await showDialog<_HabitDraft>(
      context: context,
      builder: (context) => _HabitDialog(
        existing: existing,
        supportsReminders: ref
            .read(activityReminderSchedulerProvider)
            .supportsActivityReminders,
      ),
    );
    if (draft != null) {
      try {
        final reminderScheduled = await ref
            .read(activityProvider.notifier)
            .saveHabit(
              id: existing?.id,
              title: draft.title,
              description: draft.description,
              period: draft.period,
              targetCount: draft.targetCount,
              reminderTime: draft.reminderTime,
            );
        if (draft.reminderTime != null && !reminderScheduled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Habit saved, but its reminder could not be scheduled on this device.',
              ),
            ),
          );
        }
      } catch (error) {
        _showError(error);
      }
    }
  }

  Future<void> _chooseSessionCategory() async {
    final selected = await showModalBottomSheet<ActivityCategory>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final category in ActivityCategory.values)
              ListTile(
                leading: Icon(_categoryIcon(category)),
                title: Text(_categoryName(category)),
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await _logSession(selected);
  }

  Future<void> _logSession(ActivityCategory category) async {
    final draft = await showDialog<_SessionDraft>(
      context: context,
      builder: (context) =>
          _SessionDialog(category: category, selectedDay: _selectedDay),
    );
    if (draft != null) {
      try {
        await ref
            .read(activityProvider.notifier)
            .logSession(
              category: category,
              title: draft.title,
              startedAt: draft.startedAt,
              durationMinutes: draft.durationMinutes,
              distanceKm: draft.distanceKm,
              calories: draft.calories,
              pages: draft.pages,
              words: draft.words,
              status: draft.status,
            );
      } catch (error) {
        _showError(error);
      }
    }
  }

  Future<void> _startTimedSession() async {
    final category = await showModalBottomSheet<ActivityCategory>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final category in ActivityCategory.values)
              ListTile(
                leading: Icon(_categoryIcon(category)),
                title: Text(_categoryName(category)),
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
    );
    if (category == null || !mounted) return;
    final draft = await showDialog<_TimedSessionDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SessionTimerDialog(category: category),
    );
    if (draft != null) {
      try {
        await ref
            .read(activityProvider.notifier)
            .logSession(
              category: category,
              title: draft.title,
              startedAt: draft.startedAt,
              durationMinutes: draft.durationMinutes,
            );
      } catch (error) {
        _showError(error);
      }
    }
  }

  Future<void> _setRoutineStep(RoutineStep step, ActivityStatus status) async {
    int? duration;
    if (status == ActivityStatus.completed) {
      final result = await showDialog<_RoutineDurationResult>(
        context: context,
        builder: (context) => _RoutineDurationDialog(stepTitle: step.title),
      );
      if (result == null) return;
      duration = result.durationMinutes;
    }
    try {
      await ref
          .read(activityProvider.notifier)
          .setRoutineStepStatus(
            step: step,
            day: _selectedDay,
            status: status,
            durationMinutes: duration,
          );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _createRoutine() async {
    final draft = await showDialog<_RoutineDraft>(
      context: context,
      builder: (context) => const _RoutineDialog(),
    );
    if (draft != null) {
      try {
        await ref
            .read(activityProvider.notifier)
            .createRoutine(
              title: draft.title,
              period: draft.period,
              stepTitles: draft.stepTitles,
            );
      } catch (error) {
        _showError(error);
      }
    }
  }

  Future<void> _setGoal() async {
    final draft = await showDialog<_GoalDraft>(
      context: context,
      builder: (context) => const _GoalDialog(),
    );
    if (draft != null) {
      try {
        await ref
            .read(activityProvider.notifier)
            .saveGoal(
              category: draft.category,
              period: draft.period,
              target: draft.target,
              unit: draft.unit,
            );
      } catch (error) {
        _showError(error);
      }
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is FormatException
        ? error.message
        : 'Could not save activity. Please try again.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HabitCheckInDraft {
  const _HabitCheckInDraft({this.value, this.durationMinutes});

  final double? value;
  final int? durationMinutes;
}

class _HabitCheckInDialog extends StatefulWidget {
  const _HabitCheckInDialog({required this.habitTitle});

  final String habitTitle;

  @override
  State<_HabitCheckInDialog> createState() => _HabitCheckInDialogState();
}

class _HabitCheckInDialogState extends State<_HabitCheckInDialog> {
  final _formKey = GlobalKey<FormState>();
  final _value = TextEditingController();
  final _duration = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Complete ${widget.habitTitle}?'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Measured value (optional)',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final parsed = double.tryParse(value);
              return parsed == null || parsed < 0
                  ? 'Enter a non-negative number.'
                  : null;
            },
          ),
          TextFormField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Duration in minutes (optional)',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final parsed = int.tryParse(value);
              return parsed == null || parsed < 0
                  ? 'Enter a non-negative whole number.'
                  : null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _HabitCheckInDraft(
              value: double.tryParse(_value.text),
              durationMinutes: int.tryParse(_duration.text),
            ),
          );
        },
        child: const Text('Complete'),
      ),
    ],
  );
}

class _SessionDraft {
  const _SessionDraft({
    required this.title,
    required this.startedAt,
    required this.durationMinutes,
    required this.status,
    this.distanceKm,
    this.calories,
    this.pages,
    this.words,
  });

  final String title;
  final DateTime startedAt;
  final int durationMinutes;
  final ActivityStatus status;
  final double? distanceKm;
  final int? calories;
  final int? pages;
  final int? words;
}

class _SessionDialog extends StatefulWidget {
  const _SessionDialog({required this.category, required this.selectedDay});

  final ActivityCategory category;
  final DateTime selectedDay;

  @override
  State<_SessionDialog> createState() => _SessionDialogState();
}

class _SessionDialogState extends State<_SessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _duration = TextEditingController(text: '30');
  final _primary = TextEditingController();
  final _secondary = TextEditingController();
  late TimeOfDay _startTime;
  ActivityStatus _status = ActivityStatus.completed;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startTime = TimeOfDay.fromDateTime(
      DateUtils.isSameDay(now, widget.selectedDay)
          ? now
          : DateTime(
              widget.selectedDay.year,
              widget.selectedDay.month,
              widget.selectedDay.day,
              12,
            ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    _primary.dispose();
    _secondary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Log ${widget.category.name}'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a title.'
                  : null,
            ),
            TextFormField(
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes)',
              ),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                return parsed == null || parsed < 1
                    ? 'Enter a duration greater than zero.'
                    : null;
              },
            ),
            TextButton.icon(
              onPressed: _chooseTime,
              icon: const Icon(Icons.schedule),
              label: Text('Started ${_startTime.format(context)}'),
            ),
            if (widget.category == ActivityCategory.cardio) ...[
              TextFormField(
                controller: _primary,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Distance (km, optional)',
                ),
                validator: _nonNegativeDouble,
              ),
              TextFormField(
                controller: _secondary,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Calories (optional)',
                ),
                validator: _nonNegativeInteger,
              ),
            ],
            if (widget.category == ActivityCategory.reading)
              TextFormField(
                controller: _primary,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Pages read'),
                validator: _nonNegativeInteger,
              ),
            if (widget.category == ActivityCategory.writing)
              TextFormField(
                controller: _primary,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Words written'),
                validator: _nonNegativeInteger,
              ),
            DropdownButtonFormField<ActivityStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(
                  value: ActivityStatus.completed,
                  child: Text('Completed'),
                ),
                DropdownMenuItem(
                  value: ActivityStatus.skipped,
                  child: Text('Skipped'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  String? _nonNegativeInteger(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value);
    return parsed == null || parsed < 0 ? 'Enter a non-negative number.' : null;
  }

  String? _nonNegativeDouble(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value);
    return parsed == null || parsed < 0 ? 'Enter a non-negative number.' : null;
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (selected != null) setState(() => _startTime = selected);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _SessionDraft(
        title: _title.text,
        startedAt: DateTime(
          widget.selectedDay.year,
          widget.selectedDay.month,
          widget.selectedDay.day,
          _startTime.hour,
          _startTime.minute,
        ),
        durationMinutes: int.parse(_duration.text),
        status: _status,
        distanceKm: widget.category == ActivityCategory.cardio
            ? double.tryParse(_primary.text)
            : null,
        calories: widget.category == ActivityCategory.cardio
            ? int.tryParse(_secondary.text)
            : null,
        pages: widget.category == ActivityCategory.reading
            ? int.tryParse(_primary.text)
            : null,
        words: widget.category == ActivityCategory.writing
            ? int.tryParse(_primary.text)
            : null,
      ),
    );
  }
}

class _HabitDraft {
  const _HabitDraft({
    required this.title,
    required this.description,
    required this.targetCount,
    required this.period,
    required this.reminderTime,
  });

  final String title;
  final String description;
  final int targetCount;
  final ActivityPeriod period;
  final String? reminderTime;
}

class _HabitDialog extends StatefulWidget {
  const _HabitDialog({required this.existing, required this.supportsReminders});

  final Habit? existing;
  final bool supportsReminders;

  @override
  State<_HabitDialog> createState() => _HabitDialogState();
}

class _HabitDialogState extends State<_HabitDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _target;
  late ActivityPeriod _period;
  TimeOfDay? _reminder;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _description = TextEditingController(
      text: widget.existing?.description ?? '',
    );
    _target = TextEditingController(
      text: '${widget.existing?.targetCount ?? 1}',
    );
    _period = widget.existing?.period ?? ActivityPeriod.daily;
    final reminderTime = widget.existing?.reminderTime;
    if (reminderTime != null) {
      final parts = reminderTime.split(':');
      _reminder = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'New habit' : 'Edit habit'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          TextField(
            controller: _target,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Target check-ins'),
          ),
          DropdownButtonFormField<ActivityPeriod>(
            initialValue: _period,
            decoration: const InputDecoration(labelText: 'Target period'),
            items: const [
              DropdownMenuItem(
                value: ActivityPeriod.daily,
                child: Text('Daily'),
              ),
              DropdownMenuItem(
                value: ActivityPeriod.weekly,
                child: Text('Weekly'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _period = value);
            },
          ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _chooseReminder,
                  icon: const Icon(Icons.notifications_outlined),
                  label: Text(
                    _reminder == null
                        ? 'Set reminder time'
                        : _reminder!.format(context),
                  ),
                ),
              ),
              if (_reminder != null)
                IconButton(
                  tooltip: 'Clear reminder',
                  onPressed: () => setState(() => _reminder = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (!widget.supportsReminders)
            const Text('Reminders are scheduled on Android and iOS.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  Future<void> _chooseReminder() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _reminder ?? TimeOfDay.now(),
    );
    if (selected != null) setState(() => _reminder = selected);
  }

  void _save() {
    Navigator.pop(
      context,
      _HabitDraft(
        title: _title.text,
        description: _description.text,
        targetCount: int.tryParse(_target.text) ?? 0,
        period: _period,
        reminderTime: _reminder == null
            ? null
            : '${_reminder!.hour.toString().padLeft(2, '0')}:${_reminder!.minute.toString().padLeft(2, '0')}',
      ),
    );
  }
}

class _RoutineDraft {
  const _RoutineDraft({
    required this.title,
    required this.period,
    required this.stepTitles,
  });

  final String title;
  final String period;
  final List<String> stepTitles;
}

class _RoutineDialog extends StatefulWidget {
  const _RoutineDialog();

  @override
  State<_RoutineDialog> createState() => _RoutineDialogState();
}

class _RoutineDialogState extends State<_RoutineDialog> {
  final _title = TextEditingController();
  final _steps = TextEditingController();
  String _period = 'morning';

  @override
  void dispose() {
    _title.dispose();
    _steps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New routine'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Routine name'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _period,
          decoration: const InputDecoration(labelText: 'Routine type'),
          items: const [
            DropdownMenuItem(value: 'morning', child: Text('Morning')),
            DropdownMenuItem(value: 'evening', child: Text('Evening')),
            DropdownMenuItem(value: 'custom', child: Text('Custom')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _period = value);
          },
        ),
        TextField(
          controller: _steps,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Steps, one per line'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _RoutineDraft(
            title: _title.text,
            period: _period,
            stepTitles: _steps.text.split('\n'),
          ),
        ),
        child: const Text('Create'),
      ),
    ],
  );
}

class _RoutineDurationResult {
  const _RoutineDurationResult(this.durationMinutes);

  final int? durationMinutes;
}

class _RoutineDurationDialog extends StatefulWidget {
  const _RoutineDurationDialog({required this.stepTitle});

  final String stepTitle;

  @override
  State<_RoutineDurationDialog> createState() => _RoutineDurationDialogState();
}

class _RoutineDurationDialogState extends State<_RoutineDurationDialog> {
  final _duration = TextEditingController();

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Complete ${widget.stepTitle}?'),
    content: TextField(
      controller: _duration,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Duration (minutes, optional)',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _RoutineDurationResult(int.tryParse(_duration.text)),
        ),
        child: const Text('Done'),
      ),
    ],
  );
}

class _GoalDraft {
  const _GoalDraft({
    required this.category,
    required this.period,
    required this.target,
    required this.unit,
  });

  final String category;
  final ActivityPeriod period;
  final int target;
  final String unit;
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog();

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  final _target = TextEditingController(text: '30');
  final _unit = TextEditingController(text: 'minutes');
  String _category = 'cardio';
  ActivityPeriod _period = ActivityPeriod.daily;

  @override
  void dispose() {
    _target.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Activity goal'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: const [
            DropdownMenuItem(value: 'cardio', child: Text('Cardio')),
            DropdownMenuItem(value: 'reading', child: Text('Reading')),
            DropdownMenuItem(value: 'writing', child: Text('Writing')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _category = value);
          },
        ),
        DropdownButtonFormField<ActivityPeriod>(
          initialValue: _period,
          decoration: const InputDecoration(labelText: 'Period'),
          items: const [
            DropdownMenuItem(value: ActivityPeriod.daily, child: Text('Daily')),
            DropdownMenuItem(
              value: ActivityPeriod.weekly,
              child: Text('Weekly'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _period = value);
          },
        ),
        TextField(
          controller: _target,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Target amount'),
        ),
        TextField(
          controller: _unit,
          decoration: const InputDecoration(labelText: 'Unit'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _GoalDraft(
            category: _category,
            period: _period,
            target: int.tryParse(_target.text) ?? 0,
            unit: _unit.text.trim().isEmpty ? 'units' : _unit.text.trim(),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}

class _TimedSessionDraft {
  const _TimedSessionDraft({
    required this.title,
    required this.startedAt,
    required this.durationMinutes,
  });

  final String title;
  final DateTime startedAt;
  final int durationMinutes;
}

class _SessionTimerDialog extends StatefulWidget {
  const _SessionTimerDialog({required this.category});

  final ActivityCategory category;

  @override
  State<_SessionTimerDialog> createState() => _SessionTimerDialogState();
}

class _SessionTimerDialogState extends State<_SessionTimerDialog> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  final TextEditingController _title = TextEditingController();
  Timer? _ticker;
  late final DateTime _startedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _stopwatch.elapsed;
    final time =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
        '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return AlertDialog(
      title: Text('Timed ${widget.category.name} session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: 'Session title',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 18),
          Text(time, style: Theme.of(context).textTheme.displaySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _finish, child: const Text('Finish and save')),
      ],
    );
  }

  void _finish() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter a session title.');
      return;
    }
    Navigator.pop(
      context,
      _TimedSessionDraft(
        title: _title.text.trim(),
        startedAt: _startedAt,
        durationMinutes: (_stopwatch.elapsed.inSeconds / 60).ceil().clamp(
          1,
          100000,
        ),
      ),
    );
  }
}
