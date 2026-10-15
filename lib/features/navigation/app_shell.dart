import 'package:flutter/material.dart';

import '../activity/screens/activity_screen.dart';
import '../tasks/screens/home_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.checklist_rounded),
      selectedIcon: Icon(Icons.checklist_rounded),
      label: 'To-Do',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_rounded),
      selectedIcon: Icon(Icons.insights_rounded),
      label: 'Activity',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return Scaffold(
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectDestination,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.checklist_rounded),
                      selectedIcon: Icon(Icons.checklist_rounded),
                      label: Text('To-Do'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.insights_rounded),
                      selectedIcon: Icon(Icons.insights_rounded),
                      label: Text('Activity'),
                    ),
                  ],
                ),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: const [HomeScreen(), ActivityScreen()],
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectDestination,
                  destinations: _destinations,
                ),
        );
      },
    );
  }

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
  }
}
