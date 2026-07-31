# Contributing

## Principles

- Keep the app native SwiftUI and SwiftData unless a lot explicitly introduces another Apple framework.
- Prefer small feature files over large mixed views.
- Keep business rules in services or model helpers, not embedded in controls.
- Do not add external dependencies without a clear need.
- Preserve existing user work and avoid unrelated refactors.

## Validation

Before finishing a change:

- Build the `UniSaver` scheme.
- Run unit tests.
- Check macOS and iPadOS behavior when simulators are available.
- Verify dark mode, Dynamic Type, Reduce Motion, and VoiceOver structure for touched views.
- Do not commit generated build artifacts, logs, `.xcresult`, DerivedData, or personal Xcode state.

## Preview Data

Use `PreviewDataFactory` with an in-memory SwiftData container. Do not seed demo data into the production store automatically.
