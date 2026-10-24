# UniSaver architecture

Updated: 24 October 2026. This document describes the Apple application in this repository. The parent folder contains a separate web prototype and Git history; it is not part of this application repository.

## Venture

UniSaver helps students turn their course materials, tasks and practice into a single organised study workspace with saved evidence of their revision.

## Architectural principles

1. Reuse the existing course, chapter, task, quiz and flashcard models rather than create a second academic database.
2. Save student work locally before relying on optional online services.
3. Keep stored objective answer keys authoritative and preserve the question snapshot used for each attempt.
4. Require student review before applying AI proposals or saving generated questions.
5. Keep private credentials in Keychain and keep generated practice separate from teacher papers.

## Stack and why

SwiftUI provides the interface; AppKit supports macOS windows and Focus Mode. SwiftData stores academic records and JSON-backed internal notes. Foundation and PDFKit handle files and selectable PDF text. Speech and audio services support recordings and transcription where permitted. Firebase Authentication supplies email/password and Google identity; Firestore and Cloud Storage support a limited account sync. Firebase and Google Sign-In are Swift Package Manager dependencies, pinned in Package.resolved. Existing HTTP clients connect to configured OpenAI, Claude or Gemini providers; no additional AI backend was introduced.

## Main components and data flow

AcademicModels defines Course, Chapter, ClassSession, AcademicTask, AcademicResource, StudyNote, StudyDeck, Flashcard, Quiz, QuizQuestion and QuizAttempt. Course workspaces link chapters, tasks, notes and resources. AcademicFileStore copies imported files into application storage. ResourceImportService and StudyImportParsers extract or parse supported content. PDF extraction requires selectable text; there is no general OCR guarantee. MoodleClient and MoodleSyncService provide optional Moodle import with stored credentials.

TaskStudyToolsView and TaskWorkspaceService save working notes, resource selections and session drafts. TaskStepProposalService produces editable steps; TaskStepApprovalService appends approved steps to the existing checklist. Completion and XP remain separate from opening materials or requesting AI help.

Study presents Practice, Mock exams and History. ExamLabView reuses the quiz bank and existing study library. Practice chooses a bank, topic, count and supported types; submission saves an answer before feedback. Teacher mock mode uses an imported paper in its original order and preserves wording, types and marks. Timed attempts store an absolute deadline; expiry locks edits and still requires final submission. Written answers retain the response and model/rubric, without an official automatic grade.

QuestionBankService stores resumable sessions in internal StudyNote JSON. RevisionHistoryService archives answers with account identity, course/chapter/topic, question/version snapshot, session/time, grading method, marks, assistance and active answering time. Session/question identities prevent duplicate submissions; retries create new sessions. Flags are independent of correctness. Background and paused intervals are excluded from active answering time. Old snapshots retain their own answer keys when questions change.

ExamLabService keeps unresolved errors eligible for a later recall attempt even after immediate reinforcement succeeds. RevisionCoachingService calculates evidence and a next activity from recorded attempts. RevisionCoachingAI supplies optional contextual explanations. RevisionGenerationService validates generated drafts and saves a separate bank only after a preview and approval, with provider/model, source references and generation provenance. AI feedback on written answers is provisional. Suspected key errors are flagged rather than changing stored grades.

Topics currently use existing chapter links, tags and adaptive concepts. Tags are not a complete syllabus hierarchy or a validated learning-objective map.

## Data and security

SwiftData and imported files are local application data. The effective migration plan opens schema V10; older schema definitions remain for diagnosis. Revision extensions use additive optional JSON fields and do not replace old stores. Historical-store migration still needs representative backup testing before release.

Revision notes and generation provenance are scoped to the Firebase UID; signed-out use has a separate local identity. Older unowned history is preserved rather than assigned to another account. This is application-level filtering, not encrypted multi-user storage. Existing course records and card scheduling are shared within the local workspace, so the whole local workspace must not be described as account-isolated.

AccountSyncService targets users/{uid} in Firestore database unisaver, Enterprise, europe-west1, project gen-lang-client-0388206332. Its first slice uploads courses, tasks, completed task work sessions and supporting files and counts remote records; it does not merge remote records into another device’s SwiftData store. Revision history, generated provenance and new revision schedules remain local; cross-device revision sync is not implemented. Rules and deployment configuration are present, but their production deployment and cross-device operation were not verified in this publication session.

Provider and Moodle credentials use Keychain. The real GoogleService-Info.plist is deliberately excluded from Git; a placeholder example is provided. Bundle ID alyaben.UniSaver and signing settings are preserved. No student stores, supplied private question bank, screenshots, tokens or certificates should be committed.

AI requests can transmit selected question text, submitted answers, corrections and bounded excerpts from linked materials to the configured external provider. Task notes are shared through the existing explicit context controls. Revision coaching avoids the older unscoped AI request log. Unsupported files and links are not presented as content that was read. Local deterministic grading, history and scheduling do not require AI availability.

## Implemented and verified

Code inspection and focused macOS tests cover persistent answers, duplicate prevention, distinct retries, account-scoped revision access, frozen question versions, stable shuffled option identifiers, mock resume, grading and coaching evidence. The publication rerun completed 43 focused tests with the synthetic bank; the previous revision implementation run also completed 43 focused tests across RevisionHistoryTests, ExamLabTests, QuestionBankTests, RevisionTopicTests and RevisionCoachingTests. Those checks used isolated memory/disk stores, not production student records.

Earlier synthetic macOS UI checks covered Practice/Mock exams/History, explicit corrections, skipped and written answers, flags, resume after leaving a view, Focus Mode answer-state refresh, immediate retry, and starting the real recommended practice. These are recorded implementation-session observations, not a claim of a new full UI acceptance run on this date. See REVISION_HISTORY.md, EXAM_LAB.md and REVISION_COACHING.md for focused implementation notes.

## Implemented but not verified

The complete app test suite is not known to be green: earlier broader runs exposed unrelated schema/provider/date/gamification fixture failures. Live provider correctness, current credentials, production Firebase rules, Google sign-in, multi-device sync, iPad runtime, accessibility across the app and migrations from every historical store have not been established by the focused revision checks. Existing import and topic organisation are present but are not proof of reliable extraction of every table, formula or teacher document.

## Planned

The supplied exam-preparation brief is scope, not delivery evidence. A complete editable exam scope and learning-objective coverage map, source extraction quality reporting, observed-versus-inferred teacher format summary, broader subject-specific question generation and cloud revision sync remain planned or require further validation. The public Exam Lab reference does not establish access to its authenticated practice experience. See PRODUCT_SCOPE.md; its older dated delivery records describe earlier slices.

## Dependencies to avoid and why

Avoid a second account system or revision database: they would split identity and history. Avoid new AI SDKs when the configured provider transport already serves the flow. Avoid making AI or network access mandatory for objective grading and saved study. Avoid OCR, remote execution or automatic publishing dependencies until their privacy, cost and reliability have been evaluated.

## Tradeoffs consciously accepted

JSON in internal notes avoids a risky schema change but has weaker query support than dedicated tables. Local revision storage gives quick saves and offline operation but no cross-device continuity. Rule-based evidence is conservative and can offer less personalised language than unconstrained AI. Teacher wording and stored keys are preserved even when a question needs review. Immediate success is not counted as long-term recall.

## Open assumptions and current limitations

This is a development snapshot, not an audited production release. Written feedback requires human judgement. Existing shared local academic records need a wider account-isolation design. Readable source text does not guarantee correct extraction or learning. A full student journey and all accessibility cases remain to be evaluated. Configuration is required before first launch because UniSaverApp calls FirebaseApp.configure(). Tests requiring external providers should be run only intentionally; they may incur costs.

## Session log

This consolidates the development sessions recoverable from Git history, the project notes and the revision implementation records. It is not a log of private student study sessions. Dates below come from explicit records; where a session has no recorded date, it remains undated. Historical test results are attributed to their original session and are not new test runs. Test totals overlap and must not be added together. Undocumented work is not reconstructed as fact.

### 31 July 2026 — native academic foundation

**Implemented, recorded in Git:** initial application, academic foundation, native dashboard and course workspace. Evidence: commits `372a0a7`, `e127f07` and `059149e`. **Not verified in this documentation session:** the runtime and tests of those historical revisions. Decision: retain the native application and its existing academic model rather than introduce a second workspace.

### 1 August 2026 — Lot 3 content checkpoint

**Implemented, recorded in Git:** content workspace foundation (`978dc88`). [Known issues](KNOWN_ISSUES_LOT3.md) records unresolved import validation, linked-note navigation, recording access, course-card navigation and platform layout checks. **Not verified:** those issues are not assumed fixed merely because later code exists. Decision: preserve the checkpoint limitations instead of describe it as a validated release.

### 6 October 2026 — study, planning and service foundation

**Implemented, recorded in Git:** versioned SwiftData models; study imports and spaced repetition; provider-independent tutoring; Moodle integration; recordings and transcription; quizzes, flashcards and chapter content; library, planner, progress and Today; credential settings; navigation and isolated previews. Commits `90fb9ec` through `981438d` record these increments, followed by README/ignore maintenance (`aea0e99`). **Implemented but not reverified here:** the historical test commit is evidence that tests were added, not that all currently pass. Decision: reuse these models, provider clients and persistence services for subsequent work.

### 6 October 2026 — flashcard persistence repair

**Implemented, recorded in Git:** Flashcard.reviewState moved to a Data payload to avoid a SwiftData decode crash (`b5bc5ef`); the reason was documented in `7e27bbb`. **Not reverified here:** every historical store migration. Decision: keep the stored representation and diagnostic explanation; do not infer that all migration paths are safe.

### 12 October 2026 — task workspace P0

**Implemented:** local working notes, selected resources, optional timer, contextual help, resumable work and separate session review/task completion. Existing AcademicTask, StudyBlock, checklist, resource reader and reward rules were reused. **Historical verification:** [HACKATHON_P0.md](HACKATHON_P0.md) records 91 passing and 7 failing tests in the broader run, with no clean baseline proving the failures predated the work. Focused workspace checks covered legacy ledgers, consent, idempotence and disk reopening. The final XCTest UI launch was blocked by an already-running app; no forced termination or successful final UI run was claimed. **Planned/unverified:** the independent student journey and whole-app accessibility/platform checks.

### 13 October 2026 — agent behaviour repair

**Implemented:** source-aware provider requests, native typed actions and validation against fabricated duration or unnecessary clarification. **Historical verification:** [AGENT_BEHAVIOUR_REPAIR.md](AGENT_BEHAVIOUR_REPAIR.md) records a successful macOS build and 25 focused tests. An explicitly authorised live OpenAI request created a synthetic task in an in-memory store and returned the saved result to the provider. This does not verify all pedagogical answers or current provider availability. Decision: use actual saved results when confirming an action; do not claim success from a proposed action alone.

### 13 October 2026 — Focus Workspace

**Implemented:** a window-filling task destination with steps, existing document reader, notes and optional agent; narrow layouts use sheets/tabs. Continue later retains the draft and returns to the originating page. [PRODUCT_SCOPE.md](PRODUCT_SCOPE.md#focus-workspace-2026-10-13) and [ARCHITECTURE.md](ARCHITECTURE.md#focus-workspace-2026-10-13) describe the change. **Not verified by the layout change:** learning outcomes, every device size or accessibility mode. Decision: reuse the shared work-session implementation; panel resizing and selected-text sharing remain deferred. This task workspace is distinct from quiz Focus Mode below.

### Date not recorded — reviewed task breakdown and approval

**Implemented:** editable/reorderable proposed steps, explicit source excerpts, provenance demotion after edits, approval receipts, stale/deleted-parent rejection and atomic checklist append without automatic XP. **Historical verification:** [PRODUCT_SCOPE.md](PRODUCT_SCOPE.md#verification-record) records 23 focused tests and a live demo-brief flow through edit, approval, Today refresh and relaunch. Existing checklist preservation, save failures and reapplication used isolated stores. **Not verified live:** the final read-only saved-plan review screen. Decision: separate AI proposals from approved task changes and retain failed drafts.

### Date not recorded — reusable question bank and import

**Implemented:** reviewable teacher-text import, original prompts/options/keys/explanations, multiline parsing, numeric grading, frozen question snapshots and resumable bank sessions. Import-by-reference preserves a supplied bank locally rather than asking AI to regenerate it. **Historical verification:** implementation records describe focused parser/persistence checks and one separately authorised live provider preview that prepared an import without saving a Quiz. These records do not prove GUI import acceptance for every format. Private source text and diagnostic notes remain outside the publication. Decision: teacher material remains authoritative; changed keys require review. Later Exam Lab and synthetic-fixture checks supersede the older bank-only counts.

### Date not recorded — persistent revision history

**Implemented:** immediate answer saves, UID-scoped history, immutable question versions, assistance/grading metadata, active-time measurement and separate retry records, using additive internal-note JSON. **Historical verification:** [REVISION_HISTORY.md](REVISION_HISTORY.md#verification) records 20 unique focused tests, including disk reopen, duplicates, retries, changed keys, account boundaries and timer behaviour. **Not verified:** production cross-account sign-in journeys or revision cloud sync. Decision: preserve unowned legacy records and shared-card scheduling; do not silently assign old activity to the current user.

### Date not recorded — Exam Lab practice, teacher mocks and retry flow

**Implemented:** Practice/Mock exams/History navigation, explicit corrections, original option identifiers after shuffling, teacher paper order/marks, written review, resumable timed drafts, independent flags and later-review eligibility after immediate retries. **Historical verification:** [EXAM_LAB.md](EXAM_LAB.md#verification) records 30 unique focused tests plus synthetic macOS UI checks of all four question types, save/leave/resume, corrections and retries. UI checks exposed stale quiz Focus Mode rendering; shared observable state fixed the issue and refreshed selections/grading in the separate window. **Not verified:** live AI feedback or two real Firebase sign-ins. Decision: keep pending written marks separate from objective scores and preserve delayed recall as distinct evidence.

### Date not recorded — contextual revision coaching

**Implemented:** recorded-attempt summaries, conservative pattern detection, one launchable recommendation, gradually adjusted generated difficulty, optional specific-error explanations and reviewed similar-question generation with provenance. **Historical verification:** [REVISION_COACHING.md](REVISION_COACHING.md#availability-and-verification) records 43 unique passing tests and a disposable Biology UI flow: answer, save, review summary/evidence, start recommended Transport practice, leave and resume. Fixture providers tested failures, source validation, key flags and preview saves; no live external coaching request was used. Decision: deterministic evidence controls grades, schedules and recommendations; AI remains secondary and provisional. The broader attached exam-preparation brief remains planned where not implemented.

### Date not recorded — account integration and limited sync

**Implemented:** Firebase email/password and Google account flows, UID-owned cloud paths and a limited upload action. [FirebaseAccountSync.md](UniSaver/Docs/FirebaseAccountSync.md) describes configuration and required manual checks. Sync uploads the first academic slice and counts remote records; it does not merge another device's records into SwiftData. **Not verified in this session:** production authentication, deployed rules, attachment bucket operation or two-way sync. Revision records remain local. Decision: do not describe an upload/count operation as full cross-device synchronisation.

### 24 October 2026 — publication preparation

Inspected the nested Apple Git repository, source models, persistence, account sync, revision services, package lockfile, import tests and existing documentation. Replaced outdated architecture statements with the current local revision and Exam Lab boundaries. Preserved project identity, signing, user files and Git history. Excluded private configuration, private supplied fixtures, local databases, screenshots and worktrees; removed personal Xcode settings from the publication index while retaining the local file. Added a synthetic bank so repository tests do not require private course material. Verification: the final macOS build/test run passed 43 unique focused cases with the synthetic bank; one opt-in live-provider case was skipped. The initial fixture-dependent failure was corrected before that successful rerun. A pattern audit scanned 251 historical blobs without credential matches, ignored-private-file checks passed, and the staged whitespace check passed. Commit `babb377` saved the prepared state locally. GitHub publication status and current verification results are recorded in [PUBLICATION_STATUS.md](PUBLICATION_STATUS.md); no push is implied by this document.


### 24 October 2026 — session-log consolidation

**Implemented and verified:** consolidated the recoverable sessions above from Git and the existing project notes, retaining historical failures, verification limits and source links. Added explicit undated entries rather than invent implementation dates. Corrected the sync description to distinguish upload/counting from two-way record merging. **Documentation checks only:** reviewed the diff and local Markdown links; no app tests, live AI calls or Firebase operations were performed for this documentation update. GitHub publication remains blocked as described in [PUBLICATION_STATUS.md](PUBLICATION_STATUS.md).
