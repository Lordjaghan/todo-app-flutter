import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/activity.dart';
import '../../../data/repositories/activity_repository.dart';
import '../analytics/activity_analytics.dart';

class ActivityReportsView extends StatefulWidget {
  const ActivityReportsView({
    required this.snapshot,
    required this.anchor,
    required this.onSetGoal,
    super.key,
  });

  final ActivitySnapshot snapshot;
  final DateTime anchor;
  final VoidCallback onSetGoal;

  @override
  State<ActivityReportsView> createState() => _ActivityReportsViewState();
}

class _ActivityReportsViewState extends State<ActivityReportsView> {
  ReportRange _range = ReportRange.daily;
  ReportMeasure _measure = ReportMeasure.activeMinutes;

  @override
  Widget build(BuildContext context) {
    final report = ActivityAnalytics.buildReport(
      widget.snapshot,
      range: _range,
      anchor: widget.anchor,
    );
    final points = _measure == ReportMeasure.activeMinutes
        ? report.points
        : report.points
              .map(
                (point) => ActivityReportPoint(
                  label: point.label,
                  date: point.date,
                  values: {
                    for (final category in ActivityReportCategory.values)
                      category: category == ActivityReportCategory.habits
                          ? point.habitCompletions
                          : 0,
                  },
                  habitCompletions: point.habitCompletions,
                  plannedActivities: point.plannedActivities,
                ),
              )
              .toList();
    final rangeLabel = switch (_range) {
      ReportRange.daily => DateFormat('EEEE, MMM d').format(widget.anchor),
      ReportRange.weekly =>
        'Week of ${DateFormat('MMM d').format(_weekStart(widget.anchor))}',
      ReportRange.monthly => DateFormat('MMMM yyyy').format(widget.anchor),
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(rangeLabel, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<ReportRange>(
          segments: const [
            ButtonSegment(value: ReportRange.daily, label: Text('Daily')),
            ButtonSegment(value: ReportRange.weekly, label: Text('Weekly')),
            ButtonSegment(value: ReportRange.monthly, label: Text('Monthly')),
          ],
          selected: {_range},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _range = selection.first),
        ),
        if (_range == ReportRange.monthly) ...[
          const SizedBox(height: 10),
          SegmentedButton<ReportMeasure>(
            segments: const [
              ButtonSegment(
                value: ReportMeasure.activeMinutes,
                label: Text('Minutes'),
              ),
              ButtonSegment(
                value: ReportMeasure.completedHabits,
                label: Text('Habits'),
              ),
            ],
            selected: {_measure},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _measure = selection.first),
          ),
        ],
        const SizedBox(height: 16),
        Text(switch (_range) {
          ReportRange.daily => 'Activity by hour',
          ReportRange.weekly => 'Activity by day',
          ReportRange.monthly =>
            _measure == ReportMeasure.activeMinutes
                ? 'Active minutes by date'
                : 'Habit check-ins by date',
        }, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (report.hasRecords)
          _chart(points, _range, _measure)
        else
          _emptyState(context),
        if (report.hasRecords) ...[
          const SizedBox(height: 10),
          _legend(context, _measure),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric(context, 'Active minutes', '${report.activeMinutes}'),
            _metric(context, 'Habit check-ins', '${report.completedHabits}'),
            _metric(
              context,
              'Completed / planned',
              report.plannedActivities == 0
                  ? '${report.completedActivities} / —'
                  : '${report.completedActivities} / ${report.plannedActivities}',
            ),
            _metric(
              context,
              'Completion rate',
              report.completionPercent == null
                  ? '—'
                  : '${report.completionPercent}%',
            ),
            _metric(context, 'Current streak', '${report.currentStreak}'),
            _metric(context, 'Longest streak', '${report.longestStreak}'),
          ],
        ),
        if (_range == ReportRange.weekly) ...[
          const SizedBox(height: 14),
          Text(
            'Consistency: ${report.weeklyConsistency == null ? '—' : '${report.weeklyConsistency}%'}',
          ),
          Text(
            report.previousWeekChangePercent == null
                ? 'Previous-week comparison unavailable'
                : '${report.previousWeekChangePercent! >= 0 ? '+' : ''}${report.previousWeekChangePercent}% active time vs previous week',
          ),
        ],
        if (_range != ReportRange.daily && report.bestDay != null) ...[
          const SizedBox(height: 12),
          Text('Best day: ${DateFormat('MMM d').format(report.bestDay!)}'),
        ],
        if (ActivityAnalytics.mostConsistentHabit(
              widget.snapshot,
              through: widget.anchor,
            )
            case final consistentHabit?) ...[
          const SizedBox(height: 8),
          Text('Most consistent habit: $consistentHabit'),
        ],
        const SizedBox(height: 12),
        for (final goal in widget.snapshot.goals) _goalProgress(context, goal),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onSetGoal,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Set a goal'),
          ),
        ),
      ],
    );
  }

  Widget _chart(
    List<ActivityReportPoint> points,
    ReportRange range,
    ReportMeasure measure,
  ) {
    final categories = measure == ReportMeasure.completedHabits
        ? [ActivityReportCategory.habits]
        : ActivityReportCategory.values;
    final maxValue = points.fold<int>(
      0,
      (max, point) => point.activeMinutes > max ? point.activeMinutes : max,
    );
    final titleEvery = range == ReportRange.daily
        ? 4
        : range == ReportRange.monthly
        ? 5
        : 1;
    return SizedBox(
      height: 230,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          minY: 0,
          maxY: (maxValue == 0 ? 10 : maxValue).toDouble(),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(value.toInt().toString()),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 ||
                      index >= points.length ||
                      index % titleEvery != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      points[index].label,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final point = points[groupIndex];
                final value = measure == ReportMeasure.completedHabits
                    ? point.habitCompletions
                    : point.activeMinutes;
                return BarTooltipItem(
                  '${point.label}\n$value ${measure == ReportMeasure.completedHabits ? 'check-ins' : 'min'}',
                  TextStyle(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          barGroups: [
            for (var index = 0; index < points.length; index++)
              _group(index, points[index], categories, range),
          ],
        ),
      ),
    );
  }

  BarChartGroupData _group(
    int index,
    ActivityReportPoint point,
    List<ActivityReportCategory> categories,
    ReportRange range,
  ) {
    var height = 0.0;
    final stacks = <BarChartRodStackItem>[];
    for (final category in categories) {
      final value = point.values[category] ?? 0;
      if (value == 0) continue;
      final nextHeight = height + value;
      stacks.add(
        BarChartRodStackItem(
          height,
          nextHeight,
          _categoryColors[ActivityReportCategory.values.indexOf(category)],
        ),
      );
      height = nextHeight;
    }
    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: height,
          width: range == ReportRange.monthly
              ? 6
              : range == ReportRange.daily
              ? 9
              : 18,
          borderRadius: BorderRadius.circular(2),
          rodStackItems: stacks,
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, ReportMeasure measure) {
    final categories = measure == ReportMeasure.completedHabits
        ? [ActivityReportCategory.habits]
        : ActivityReportCategory.values;
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final category in categories)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color:
                      _categoryColors[ActivityReportCategory.values.indexOf(
                        category,
                      )],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(_categoryName(category)),
            ],
          ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 26),
    child: Column(
      children: [
        const Icon(Icons.bar_chart_rounded, size: 30),
        const SizedBox(height: 8),
        Text(
          'No activity in this period',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'Saved sessions and completions will appear here.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _metric(BuildContext context, String label, String value) => SizedBox(
    width: 148,
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

  Widget _goalProgress(BuildContext context, ActivityGoal goal) {
    final progress = ActivityAnalytics.goalProgress(
      widget.snapshot,
      goal,
      through: widget.anchor,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${goal.category} ${goal.period.name} goal'),
            subtitle: Text('$progress / ${goal.target} ${goal.unit}'),
          ),
          LinearProgressIndicator(
            value: (progress / goal.target).clamp(0, 1).toDouble(),
          ),
        ],
      ),
    );
  }

  DateTime _weekStart(DateTime date) {
    final day = DateUtils.dateOnly(date);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  String _categoryName(ActivityReportCategory category) => switch (category) {
    ActivityReportCategory.habits => 'Habits',
    ActivityReportCategory.cardio => 'Cardio',
    ActivityReportCategory.routines => 'Routines',
    ActivityReportCategory.reading => 'Reading',
    ActivityReportCategory.writing => 'Writing',
  };

  static const _categoryColors = [
    Color(0xFF3A8D73),
    Color(0xFF3C78A8),
    Color(0xFFE2A33A),
    Color(0xFF7569B6),
    Color(0xFFCE6D56),
  ];
}
