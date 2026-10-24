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

## Hackathon P0 update — 2026-10-12

The effective module inventory, local task workspace extension and current limitations are documented in [architecturedoc.md](architecturedoc.md). The original Lot 0 sections above are historical; see [HACKATHON_P0.md](HACKATHON_P0.md) for validation and the student protocol.


## Focus Workspace (2026-10-13)

Task work opens a window-filling destination over the current page through `AppNavigationState.focusTask`. Returning restores the originating page. The shared `TaskWorkSessionHostView` / `TaskWorkSessionSheet` remains the only session implementation. The optional timer, execution ledger, step approval pipeline, SwiftData resources, notes and contextual conversation retain their existing services and records.

At wide widths, Steps (250 pt), the existing document reader in reader-only mode, and Working notes / Agent (360 pt) sit alongside each other. Narrow widths expose Steps in a sheet and Resource / Notes / Agent tabs. The notes editor stays mounted when switching tabs. Timer and session actions remain outside the scrolling panes. Continue later persists the draft and returns without ending the session; Finish session opens the existing review, with task completion a separate choice. Saved means a successful local ledger save, not confirmed cloud sync.

Add resource groups the existing attachment/import actions, external links, and pasted instructions (stored in the existing workspace draft as an explicitly added source). Agent requests retain extraction checks and do not fetch links or read unsupported images. Active step selection is an optional backwards-compatible field in the existing draft. No new task/session/XP implementation is introduced. Panel resizing and selected-text sharing remain deferred. This layout change is not evidence of improved learning outcomes.
