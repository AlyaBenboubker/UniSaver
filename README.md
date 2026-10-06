# UniSaver

UniSaver is a native SwiftUI academic operating system for macOS and iPadOS. It brings courses, planning, study tools, academic content, recordings, and external learning services into one SwiftData-backed workspace.

## Requirements

- Xcode 26.6 project format as currently configured.
- macOS and iPadOS deployment target: 26.5.
- SwiftUI and SwiftData, no external dependencies.

## Run

Open `UniSaver.xcodeproj`, select the `UniSaver` scheme, then run on Mac or an iPad simulator. The app opens on Today. Use Classes or Quick Add to create courses, chapters, and sessions.

## Current Features

- `NavigationSplitView` with Today, Classes, Study, Planner, Progress, and Library.
- Today dashboard with greeting, date, next class, today's schedule, upcoming active classes, chapters to review, and quick actions.
- Classes workspace with search, filters, grid/list modes, preview pane, and interactive SwiftUI binder cards.
- Course workspace with Overview, Chapters, and Sessions.
- Create/edit/archive/delete courses, chapters, and sessions with confirmations.
- Planner for tasks, exams, study blocks, and external calendar activities.
- Library for resources, notes, folders, imports, recordings, and transcription.
- Study Studio with flashcards, quizzes, spaced repetition, exercises, and understanding practice.
- Optional Moodle synchronization and AI-assisted revision using credentials stored in Keychain.
- SwiftData persistence with versioned schemas and isolated preview data.
- Preview-only sample data for Microeconomics, Mathematics, Computing Foundations, Organizational Behavior, and German.

## Tests

Unit tests cover validation, persistence, migrations, imports, calendar parsing, study scheduling, recordings, transcription, Moodle mapping, progress, and navigation. UI tests cover the principal navigation and content-entry paths.

## Limits

External services require user-provided credentials and network access. Migration regressions should be tested against copies of historical stores, including their SQLite WAL and SHM sidecars, before changing the migration plan.
