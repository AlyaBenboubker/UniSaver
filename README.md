# UniSaver

UniSaver is a native SwiftUI academic operating system for macOS and iPadOS. This first lot establishes durable SwiftData persistence and a usable workflow for courses, chapters, dated sessions, and Today.

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
- SwiftData persistence for academic years, semesters, courses, chapters, and class sessions.
- Preview-only sample data for Microeconomics, Mathematics, Computing Foundations, Organizational Behavior, and German.

## Tests

Unit tests cover validation rules, progress cycle, progress calculation, SwiftData persistence, chronological sorting, archive preference, and preview data isolation.

## Limits

Documents, rich notes, planner tasks, Study Studio, AI, recordings, and sync are intentionally not implemented in this lot.
