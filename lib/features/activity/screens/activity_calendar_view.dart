import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/activity_repository.dart';
import '../analytics/activity_analytics.dart';

class ActivityCalendarView extends StatefulWidget {
  const ActivityCalendarView({
    required this.snapshot,
    required this.selectedDay,
    required this.onSelectDay,
    super.key,
  });

  final ActivitySnapshot snapshot;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectDay;

  @override
  State<ActivityCalendarView> createState() => _ActivityCalendarViewState();
}

class _ActivityCalendarViewState extends State<ActivityCalendarView> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.selectedDay.year, widget.selectedDay.month);
  }

  @override
  void didUpdateWidget(covariant ActivityCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDay.year != widget.selectedDay.year ||
        oldWidget.selectedDay.month != widget.selectedDay.month) {
      _month = DateTime(widget.selectedDay.year, widget.selectedDay.month);
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingDays = DateTime(_month.year, _month.month, 1).weekday - 1;
    final selectedReport = ActivityAnalytics.buildReport(
      widget.snapshot,
      range: ReportRange.daily,
      anchor: widget.selectedDay,
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat('MMMM yyyy').format(_month),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final label in const [
              'Mon',
              'Tue',
              'Wed',
              'Thu',
              'Fri',
              'Sat',
              'Sun',
            ])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leadingDays + daysInMonth,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            childAspectRatio: 0.95,
          ),
          itemBuilder: (context, index) {
            if (index < leadingDays) return const SizedBox.shrink();
            final dayNumber = index - leadingDays + 1;
            final day = DateTime(_month.year, _month.month, dayNumber);
            final report = ActivityAnalytics.buildReport(
              widget.snapshot,
              range: ReportRange.daily,
              anchor: day,
            );
            final color = _dayColor(report, day);
            final isSelected = DateUtils.isSameDay(day, widget.selectedDay);
            final label = report.plannedActivities > 0
                ? '${report.completedActivities}/${report.plannedActivities} planned'
                : '${report.activeMinutes} active minutes';
            return Tooltip(
              message: '${DateFormat('EEE, MMM d').format(day)} · $label',
              child: InkWell(
                onTap: () => widget.onSelectDay(day),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).dividerColor
                                .withValues(alpha: 0.35),
                      width: isSelected ? 2 : 0.6,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text('$dayNumber'),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _legend(context, const Color(0xFFDDEFE7), 'Target met'),
            _legend(context, const Color(0xFFFFF0CE), 'In progress'),
            _legend(context, const Color(0xFFF9DFDB), 'Target missed'),
            _legend(context, const Color(0xFFE8EDF1), 'No plan'),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          DateFormat('EEEE, MMM d').format(widget.selectedDay),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${selectedReport.completedActivities} completed · '
          '${selectedReport.activeMinutes} active minutes',
        ),
      ],
    );
  }

  Color _dayColor(ActivityReport report, DateTime day) {
    if (report.plannedActivities == 0) {
      return report.hasRecords ? const Color(0xFFE4ECF2) : Colors.transparent;
    }
    if (report.completionPercent == 100) return const Color(0xFFDDEFE7);
    if (DateUtils.dateOnly(day).isBefore(DateUtils.dateOnly(DateTime.now()))) {
      return report.completedActivities > 0
          ? const Color(0xFFFFF0CE)
          : const Color(0xFFF9DFDB);
    }
    return report.completedActivities > 0
        ? const Color(0xFFFFF0CE)
        : Colors.transparent;
  }

  Widget _legend(BuildContext context, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
