# Product scope — 13 October 2026

The current hackathon slice prioritizes one local task workflow. See `architecturedoc.md` for the inventory of existing modules and `HACKATHON_P0.md` for validation.

## Delivered P0 mechanisms

- Review real PDF/selectable text or pasted assignment instructions with source excerpts; correct requirements before approval.
- Generic editable preparation, production, review and distinct submission actions; useful dependencies and optional estimates. No fabricated deadline or rubric. Missing deadlines permit manual work, while automatic scheduling requires a date.
- Reuse AcademicTask, StudyBlock, existing checklist, resource imports and PDF reader.
- Start/resume work from Today/To-do or a class assignment milestone.
- Task resources, file/link attachment, locally saved working notes, optional timer and contextual provider-backed assistance using the configured AI service.
- Explicit note-sharing toggle; bounded selected context, local multi-turn history and clear unsupported external content.
- Session review versus whole-task completion, remaining work, optional local supporting files/links/notes, retrievable reviews.
- Persist session starts, initial estimate and basic help/plan-correction counts; idempotent review IDs and existing XP rules.
- DEBUG-only validation fixture uses a unique temporary store; production is not seeded.

## Deferred / limited

P1 task-linked Quiz/Study practice and P2 recommendations are not delivered in this slice. Existing Study remains available independently. Contextual study chat remains text-based; task breakdowns now have structured proposals and explicit approval through the existing task checklist service. The global agent retains its typed planning reviews. No new action router or universal Undo was added. OCR, image understanding, live screen access, code execution, deterministic maths checking and Moodle submission confirmation are absent. Auth/sync configuration is preserved; new task drafts are local-only. Narrow-window layout has adaptive source/notes sections but whole-app iPad/accessibility behavior is not yet verified.

The complete student hypothesis remains unvalidated. A successful build or persistence test does not prove a student can complete the journey independently, nor that AI feedback is reliable.


## Blocks 1–2: shipped task breakdown and approval

- One selected existing task and pasted assignment text; real requests use the existing configured provider/Keychain transport.
- Structured, editable/reorderable/removable titles and completion criteria, suggested/explicit labels, exact source excerpts where supplied. Editing a requirement demotes it to a suggestion.
- Save approved steps appends to the existing checklist and preserves prior subtasks, completion states and working notes. No completion or XP is awarded for generating, saving or opening the plan.
- One atomic local save contains checklist and durable proposal receipt. Double application is blocked before mutation, including after reopening the store. Duplicate titles are rejected instead of silently adding indistinguishable steps.
- Deleted parents and stale task snapshots block saving. Refresh displays current context for review and refuses to overwrite unsaved task edits. Storage errors retain the draft and expose the real error; retry cannot leave a partial set.
- Immediate Today/To-do/task detail refresh; Open first incomplete step returns to the existing work session with saved criterion/source/evidence. Review saved steps reopens the last approved plan read-only.

### Verification record

macOS build passed. Focused suites: `TaskStepProposalTests` (5), `TaskStepApprovalTests` (9), `TaskWorkspaceTests` (9); **final rerun: all 23 passed**. Live: real OpenAI generation from demo assignment briefs; generated-proposal cancel with no steps added; edit → approve/double click → first incomplete step → Today refresh → quit/relaunch → To-do → saved steps/notes. Eight saved steps appeared once, the edited title and working note survived, and XP stayed at its baseline during the approval journey. Existing checklist preservation, failed-save retry, changed/deleted parent rejection, and reapplication after disk reopen were tested with isolated stores rather than destructive runtime experiments. The final saved-plan review screen was not checked live; automation stopped to avoid interrupting active app use. Remaining manual check: open the saved task → Review saved steps → verify no Save/Regenerate action → Open first incomplete step.

### Limitations and cuts to protect the goal

Unapproved drafts are temporary and are discarded on close/relaunch. The last saved plan can be reviewed but not re-applied; modifying saved checklist items uses the existing task editor. Human review is still required: source matching establishes provenance, not semantic correctness. Duplicate prevention covers the synchronous in-app approval path, not concurrent processes. iPad runtime and forced live storage failures were not tested. No new authentication, cloud sync, screen sharing, PDF extraction, scheduling, gamification or study formats shipped in these blocks.

### 90-second demo

0–15s: Today → Start task → Break into steps. Paste a brief from the selected task.
15–40s: Propose steps; show the real loading state and suggested/source labels (network time varies).
40–55s: Edit a title/criterion, remove or reorder a step, then Save approved steps.
55–70s: Open first incomplete step; show criterion, unchanged notes, unchecked checklist and in-progress status. Close to see To-do progress.
70–90s: Quit/relaunch → To-do → Start; show persisted steps/notes, then Review saved steps with no Save action. Use a previously saved task if provider latency exceeds the demo window.


## Focus Workspace (2026-10-13)

Task work opens a window-filling destination over the current page through `AppNavigationState.focusTask`. Returning restores the originating page. The shared `TaskWorkSessionHostView` / `TaskWorkSessionSheet` remains the only session implementation. The optional timer, execution ledger, step approval pipeline, SwiftData resources, notes and contextual conversation retain their existing services and records.

At wide widths, Steps (250 pt), the existing document reader in reader-only mode, and Working notes / Agent (360 pt) sit alongside each other. Narrow widths expose Steps in a sheet and Resource / Notes / Agent tabs. The notes editor stays mounted when switching tabs. Timer and session actions remain outside the scrolling panes. Continue later persists the draft and returns without ending the session; Finish session opens the existing review, with task completion a separate choice. Saved means a successful local ledger save, not confirmed cloud sync.

Add resource groups the existing attachment/import actions, external links, and pasted instructions (stored in the existing workspace draft as an explicitly added source). Agent requests retain extraction checks and do not fetch links or read unsupported images. Active step selection is an optional backwards-compatible field in the existing draft. No new task/session/XP implementation is introduced. Panel resizing and selected-text sharing remain deferred. This layout change is not evidence of improved learning outcomes.
