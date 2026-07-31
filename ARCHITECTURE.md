# Architecture

UniSaver is organized by feature with a small shared core:

- `App`: application entry point and root navigation.
- `Models`: SwiftData persistent models.
- `Core/Persistence`: `ModelContainer` setup for app and preview stores.
- `Core/Navigation`: app sections.
- `Core/DesignSystem`: colors, cards, and cross-platform visual helpers.
- `Core/Components`: reusable empty states, progress meters, and Quick Add routing.
- `Features`: Today, Classes, Courses, Chapters, Sessions, and placeholders for later sections.
- `Services`: business validation and structural progress calculations.
- `PreviewContent`: isolated in-memory demo data.

## Navigation

The app uses `NavigationSplitView` as the primary container. The sidebar contains Today, Classes, Study, Planner, Progress, and Library. Today and Classes are functional in this lot. Later sections expose honest empty states with no active decorative controls.

## Persistence

SwiftData is configured in `PersistenceController`. The production container uses a named persistent configuration. Previews use an in-memory configuration seeded by `PreviewDataFactory`, so demo data does not pollute real user data.

## Business Logic

Validation and progress rules live in `AcademicValidationService`, separate from SwiftUI views. Views call the service before saving sessions and use it for structural progress display.

## Platform Approach

The UI uses native SwiftUI controls, system typography, semantic colors, `NavigationSplitView`, sheets, forms, lists, and materials. It avoids hover-only behavior and supports pointer, touch, keyboard, dark mode, Dynamic Type, and Reduce Motion structurally.
