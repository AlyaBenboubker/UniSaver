# Persistent revision tracking

## Existing architecture and implementation

- `Quiz`, `QuizQuestion`, `QuizAttempt`: existing question content and quiz summaries.
- `BankQuestionSnapshot`, `BankQuestionRun`, `BankPracticeSession`, `QuestionBankLedger`: resumed quiz sessions, per-question snapshots, answers and corrections. All quiz entry points now use this persistent practice flow.
- `StudyDeck`, `Flashcard`, `FlashcardReviewEvent`, `FlashcardReviewState`: retained scheduling and self-assessment events.
- Topics: `QuizQuestion.tags`, chapter learning objectives, and `AdaptiveConcept` / `AdaptiveExamProfile` for editable topic groupings and evidence.
- `UnderstandingPracticeAttempt`: retained original exercise, transfer answer, help and self-assessment. Its explicit Save Check submission now also archives both answers. AI provides guidance; grading is labelled self-assessed rather than AI grading.
- `AccountSyncService.conversationAccountID()` provides the Firebase UID, or the existing `local-signed-out` workspace identity. Signed-out history belongs to that shared local workspace and is never reassigned to a signed-in account.

`RevisionHistoryService` adds versioned JSON payloads in internal `StudyNote` records, using the existing SwiftData store and synchronous saves. No existing model/property, schema version, or relationship is removed or changed. These internal records are hidden from the regular note library. History snapshots deliberately have no relationships to mutable questions/courses, so deletion cannot cascade into history.

Bank progress uses an account-hashed title and stores the owning identity. New sessions get new UUIDs; repeated saves merge by session/question ID. Confirmed answers, grading keys and times survive stale saves. Review flags remain independently editable. Exam grading uses the session snapshot and remains pending until completion. Question versions hash the full deterministic snapshot, including choices, key, points and explanation. Changed versions are treated as unanswered by practice filters.

Flashcard self-assessment is recorded when a rating is submitted. Test-mode answers are recorded on Check Answer. Matching clicks record separate attempts. Scheduling undo retains answer history, and subsequent study uses a new history session. A model answer revealed for comparison is recorded separately from hints used before recall.

The active-answer clock uses monotonic time, app activation notifications, visibility and explicit pause state. Quiz navigation closes the old answer interval; flashcard comparison closes answering time; understanding checks time each focused answer field separately. Time already spent in an unfinished bank question is saved on navigation/autosave/exit. Abrupt process termination can lose an unsaved active interval, but not an already committed submission.

## History and account boundaries

Open **Progress → Revision History**. The list shows session date, activity, course, answer count and results. Session details show submitted answers, original corrections, version, topics, points, grading method, assistance and active time.

This release is **local to this Mac**. Existing Firebase sync synchronizes courses, tasks and completed task work sessions, not quiz/flashcard revision records. No server rules or Firebase data were changed. The UI states this limitation.

Earlier unowned bank ledgers, adaptive profiles, quiz attempts and flashcard events remain intact; they are not silently attributed to whichever account signs in next. New adaptive bank evidence reads only the current account's ledgers. Existing flashcard scheduling remains attached to the shared card models; the new answer history is account-scoped.

## Verification

`RevisionHistoryTests` verifies disk close/reopen, idempotent submission/stale saves, retry preservation, question-key changes and version differences, foreign-account filtering/write rejection, skipped versus unanswered, independent review flags, and active timing across pause/background/hidden intervals. The final focused run passed 20 unique tests. Existing `QuestionBankTests` covers repeated imports, snapshot preservation, disk resume, exam deferred grading and stale session merging; `RevisionTopicTests` covers topic behavior.

The broader existing test suite has failures outside the focused revision suites, including current-schema assertions and provider/conversation fixtures. Those are not treated as passing revision validation. Full interactive UI and two live Firebase sign-ins have not been exercised by these model-level checks.
