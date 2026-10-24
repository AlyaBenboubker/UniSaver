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

AccountSyncService targets users/{uid} in Firestore database unisaver, Enterprise, europe-west1, project gen-lang-client-0388206332. Its first slice covers courses, tasks, completed task work sessions and supporting files. Revision history, generated provenance and new revision schedules remain local; cross-device revision sync is not implemented. Rules and deployment configuration are present, but their production deployment and cross-device operation were not verified in this publication session.

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

### 24 October 2026 — publication preparation

Inspected the nested Apple Git repository, source models, persistence, account sync, revision services, package lockfile, import tests and existing documentation. Replaced outdated architecture statements with the current local revision and Exam Lab boundaries. Preserved project identity, signing, user files and Git history. Excluded private configuration, private supplied fixtures, local databases, screenshots and worktrees; removed personal Xcode settings from the publication index while retaining the local file. Added a synthetic bank so repository tests do not require private course material. GitHub publication status and current verification results are recorded in PUBLICATION_STATUS.md; no push is implied by this document.
