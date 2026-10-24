# Current implementation — 13 October 2026

Today and the global popup now use the configured provider, bounded history/context and native tools. One shared executor supports validated creation with Undo and reviewed progress/planning changes. Read [AGENT_BEHAVIOUR_REPAIR.md](../../AGENT_BEHAVIOUR_REPAIR.md) for current behavior and verification. Earlier notes below describe previous slices and are superseded where they conflict.

# Today Agent Scope

## Delivered

- Today uses a compact conversation surface plus an expanded conversation sheet.
- Conversation history and pending typed proposals are persisted locally in a system `StudyNote` marker.
- Messages are interpreted into typed, reviewable actions before any SwiftData write.
- Approved proposals reuse existing `AcademicTask` and `StudyBlock` records; the agent does not create a parallel task or planner system.
- Duplicate application is guarded by proposal identifiers and existing task matching.
- Focus Mission, supporting mission rows, weekly activity, XP, and active-day goal reuse the existing gamification ledger.
- Upcoming deadlines and the compact week strip are derived from existing tasks, exams, sessions, and flashcards.
- `Start task` now opens a focused task work session for the linked `AcademicTask` instead of treating the mission as complete.
- The work session supports structured checklist steps, direct progress saving, `Continue later`, `I’m blocked`, optional elapsed/countdown timers, and a compact session review.
- Task execution sessions are persisted locally in a separate system `StudyNote` ledger with recorded time, completed checklist items, blocker, note, and evidence level.
- The To-do workspace reuses `AcademicTask` and exposes Today, Upcoming, All, and Completed views with grouping by class, status, or assignment-like bucket.
- XP is still awarded only through the existing task/study completion rules; starting work or running a timer does not award XP.
- The session review now supports optional supporting work: imported files/images/PDFs, links and notes. These are stored as private local file references and metadata in the execution ledger.
- The Settings page exposes the UniSaver account entry point, restores a Firebase session when configured, launches Google sign-in, signs out, and can sync the first account data slice.
- `AccountSyncService` implements the Firebase-backed path for Google Auth, course/task/work-session upload, and private supporting-file upload when the official SDK packages and `GoogleService-Info.plist` are present.
- Firebase Firestore and Storage security rules plus a configuration guide are included in the repository.
- The app shell exposes a global UniSaver Agent button and Command-Shift-A shortcut. It reuses the same local conversation history and typed proposal flow as Today.

## Explicit Limits

- Attachments are not accepted in the Today composer yet; file import remains in the existing import flows.
- Provider-backed free-form chat is not enabled in this slice. The implemented agent is local and deterministic for planning proposals, so it does not send the full Library or private documents.
- Calendar and Moodle remain constrained by their existing read/write capabilities. Read-only sources are never modified from the Today agent.
- Conversation deletion removes local chat history and pending suggestions, but does not delete already approved tasks or study blocks.
- `AcademicTask` has no native blocked status or subtask relationship yet. Blockers and task execution history are stored in the execution ledger, while checklist steps are represented in the existing task description.
- Due dates are required by the existing `AcademicTask` model, so a truly date-less task still needs a future schema change.
- Google authentication and account sync still require external Firebase console configuration, official Swift package linkage, URL scheme setup, Keychain Sharing, and deployed rules before they can be tested as production auth.
- Supporting files are uploaded to private Firebase Storage only after a user is signed in and `Sync now` succeeds. A Moodle screenshot remains user-provided evidence, not direct Moodle confirmation.
- The first sync slice uploads Courses, AcademicTask records, completed task work-session records, and evidence attachments. Conversations, quizzes, flashcards, exercises, and XP events are intentionally not announced as synced yet.
- The global agent is in-app. A detached AppKit `NSPanel`, menu-bar item, live window sharing and screen capture permissions are not implemented in this slice.

## Validation Notes

- The macOS target builds successfully through Xcode.
- Command-line focused tests are currently blocked in this sandbox by SwiftData macro plugin-server failures under `xcodebuild test`; run the focused tests from Xcode or an unsandboxed shell to validate the parser suite.

## P0 task-workspace update — 2026-10-12

The focused task workspace now attaches existing resources, imports files, opens the PDF reader, autosaves notes and persists contextual conversation in the existing execution ledger. Its AI panel reuses the configured AIRevisionAssistantClient; provider-backed contextual help is available here, while the global Today planning agent remains deterministic. Note sharing is explicit. Long context is bounded and unsupported files/links/screens are not claimed as read. Session reviews retain remaining work and usage metadata and can be retrieved after relaunch. The assignment milestone screen can start the same work session. Missing task deadlines use an internal distant-future sentinel to preserve the existing schema and are displayed honestly.

These changes supersede the earlier limits about provider chat being entirely unavailable and every task requiring a fabricated real deadline. They do not add task-linked Quiz practice, global provider action routing, image/OCR understanding or synchronization of new local drafts. See [architecturedoc.md](../../architecturedoc.md) and [HACKATHON_P0.md](../../HACKATHON_P0.md) for validation.
