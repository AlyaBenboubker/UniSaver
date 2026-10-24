# Exam Lab practice experience

Study now opens a three-section hub: **Practice**, **Mock exams**, **History**. Existing flashcards and other study tools remain available through a link inside Practice. No additional app-level tabs or database schema changes were introduced.

## Practice and retries

Choose the course/chapter in the hub, then a bank, topic tags, count and available question types inside setup. Progress filters and optional option shuffling are secondary settings. Submit or skip each question explicitly. Corrections include the full original answer text, a concise explanation, and optional contextual AI explanations. The existing Focus Mode uses the same observable session state as the regular sheet, so selections, feedback, navigation and retries refresh in both windows.

Each retry has a new session UUID and retains the exact snapshot of the original question, including its rubric. An immediate retry is linked to the session whose correction was seen. It does not clear the unresolved mistake or postpone its later-review eligibility. A mistake resolves only after an unassisted correct answer in a separate attempt at least 24 hours after the last error. “Review later” also schedules successful questions; a subsequent attempt clears that explicit reminder.

Question order can vary in practice. Answer option display order is saved as original indices; selecting an option submits its original identifier rather than its shuffled position. Teacher option identifiers and text are never relabelled.

## Teacher mocks

Mock exams lists existing imported papers and excludes AI-generated practice. Selecting a paper uses every saved question in its original `position` order, with unchanged prompts, question types, choices and marks. New imports can supply `Points:` or `Marks:` (positive integers, matching the existing points model) and optional multiline `Rubric:`. Rubrics are stored separately from the original explanation. Teacher-paper imports retain repeated questions and do not merge different papers merely because they overlap. A structurally revised import gets a separate bank; the earlier paper remains intact.

Timed or untimed attempts are configured inside the mock. A timed attempt saves an absolute deadline; the countdown continues across pause/background time, view changes and app relaunch. Expiry locks editing without revealing corrections or silently submitting the paper. Students explicitly submit to see results.

Draft answers save synchronously, including written text. Students can navigate freely, edit saved answers, leave questions blank, skip, and flag them independently of correctness. Save and exit, Session setup, hub navigation and History all retain the attempt. History and the hub offer resume; completed sessions open results. Final submission records blank answers as skipped and freezes answers and question snapshots. Stale saves cannot undo completion or replace the submitted answers.

Non-numeric short answers in teacher mocks, and questions with imported rubrics, use written review rather than exact-string automatic grading. The original model answer/rubric appears only after submission. Written marks remain pending, separate from automatically scored marks. Contextual AI feedback is labelled **provisional, not an official grade**, saved as an annotation, and cannot award points or change correctness. The existing AI provider/settings are reused; no live AI request was needed for validation.

Results show automatically scored marks where meaningful, written marks pending review, mistakes by topic, and a next action. Review corrections, Retry mistakes, Retry now, and Review later preserve earlier records. Teacher mock results never become an AI-generated paper; generated reinforcement is saved separately under AI practice.

## Storage and compatibility

This extends the existing account-scoped `QuestionBankLedger`, `BankPracticeSession`, question snapshots and `RevisionHistoryService`. New JSON fields are optional and old payloads continue decoding. Paper metadata uses an internal `StudyNote` payload. Existing records and schema V10 remain intact. Internal metadata stays out of normal note/library displays.

Revision tracking remains **local to this Mac**, isolated by the existing Firebase account identity (or the existing signed-out workspace). Cloud revision sync was not added. Timer deadlines are wall-clock deadlines; active-answer durations still exclude background time and explicit pauses.

## Verification

Final targeted suites: `ExamLabTests`, `RevisionHistoryTests`, `QuestionBankTests`, `RevisionTopicTests` — **30 unique tests passed**. Coverage includes all four existing question types, original paper wording/order/marks, repeated teacher questions, separate papers, shuffled option identifiers, original Boolean option wording/order with canonical grading, immediate versus delayed recall, later reminders, skipped questions, independent flags, editable mock drafts, stale saves after final submission, pending written marks/provisional annotations, and closing/reopening a disk store with its timer, written draft and navigation position intact.

The real built UI was exercised using DEBUG `--exam-lab-validation`, which selects a disposable in-memory store and synthetic Biology examples. Verified: the three navigation sections; teacher/AI separation; timed setup; multiple-choice, multiple-select, true/false and written entry; skip/flag/navigation; saving and leaving a mock, switching Practice → History, resuming with the same answer/flag/position/countdown; explicit final submission; per-question corrections and rubric; pending written marks; immediate retry; and live selection/grading in the separate Focus Mode window. This UI check found and corrected a stale Focus Mode rendering issue by sharing observable reference state.

No production study records were edited during UI checks. Live AI generation/feedback and two live Firebase sign-ins were not exercised; existing identity-isolation tests remain part of the focused suite.
