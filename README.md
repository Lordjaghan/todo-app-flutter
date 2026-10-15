# To-Do App

A local-first Flutter productivity app with task/subtask management and a separate Activity dashboard for habits, sessions, routines, calendar, and reports.

## Run Locally

```sh
flutter pub get
flutter run -d linux
```

Use `flutter devices` to choose another available target.

## Verify

```sh
flutter test
flutter analyze
```

## Project Guide

See [PROJECT_REPORT.md](PROJECT_REPORT.md) for the architecture, data model, current capabilities and limitations, and a detailed process for planning, implementing, and testing new features in this codebase.

## Entry Points

- [lib/main.dart](lib/main.dart): initialization, theme, and app startup.
- [lib/features/navigation/app_shell.dart](lib/features/navigation/app_shell.dart): responsive To-Do and Activity navigation.
- [lib/data/datasources/task_database.dart](lib/data/datasources/task_database.dart): SQLite schema and migrations.
- [lib/features/tasks/providers/task_provider.dart](lib/features/tasks/providers/task_provider.dart): task state and task workflows.
- [lib/features/activity/providers/activity_provider.dart](lib/features/activity/providers/activity_provider.dart): activity state and workflows.
