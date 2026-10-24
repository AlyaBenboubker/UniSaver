# UniSaver agent repair — 13 October 2026

The repaired app is `UniSaver.xcodeproj`, bundle `alyaben.UniSaver`.

## Diagnosis

Today and the global popup previously called `ConversationProposalEngine.analyze` and `TodayConversationAgent.localReply`. Neither path contacted the configured AI provider or supplied conversation history. Connecting a key therefore did not improve these replies. Study/task assistance had a separate real request path, but required a stale `isTested` flag. Provider parsers handled text only; two view-owned action executors differed in deduplication, progress handling and save behavior.

The actual secure-config smoke test reached OpenAI **gpt-4o-mini**, through **POST https://api.openai.com/v1/chat/completions**. No provider/model override was made. Claude and Gemini retain their configured models and now have native tool-message translations; they have not been tested live here. Keys stay in the existing Keychain client. Provider error bodies and private prompts are not logged.

## Changes

- Both existing conversation entry points use `AIRevisionAssistantClient` → existing provider adapter → `ConversationProviderService`. There is no second agent or replacement interface.
- Native schemas cover course/task searches, task/checklist reads, selected-resource retrieval, availability, task creation, subtask proposals, progress review and proposed new study sessions. Five model rounds and twelve calls bound the loop. Results and validation errors return to the model; cancellation stops execution.
- Context includes local date/timezone, page/actual selection, stable IDs, unfinished tasks and deadlines, progress, upcoming stored classes/exams/study blocks, recent conversation and previous validated results. It is bounded; searches retrieve additional matching records.
- Today and the global popup reread one shared local conversation before sending/committing, preventing stale state from overwriting the other surface. Older messages become bounded exact excerpts, not fabricated summaries. Firebase Auth identity changes clear conversation context/shared selections and cancel pending requests; stale action reviews cannot cross accounts.
- The existing panel has an explicit document-sharing menu (maximum four) and Undo for the latest unchanged task creation. PDF/TXT/MD/CSV are actually extracted. Retrieval ranks all supported pages/sections against the request and reports excerpt coverage with page/section references. Scanned PDFs and unsupported formats report an error. Limits are explicit: 500 PDF pages and 1 MB for text files. No OCR, external-link fetching or screen access is claimed.
- One `ConversationActionExecutor` replaces both duplicated executors. It validates IDs, dates, durations, stale progress and stored calendar conflicts, persists receipts only with a successful save, prevents duplicate task creation and preserves checklist edits. Completion requires the existing proposal review. Existing-session moves are rejected rather than silently creating additional sessions.
- A complete explicit singular creation request can execute through that same service, return saved record IDs to the model, and offer Undo. A conservative title/course/date authorization check keeps other requests in review. Advice never authorizes automatic changes. Unknown duration remains zero/unknown; model guesses do not become stored facts.
- Provider failure is shown as an error, retains the draft and appends no fake assistant reply. No local canned fallback is used by either send path.

## Verification

Focused tests cover A/B context and conversational continuity, C selected brief retrieval/subtask proposals, D unshared resource rejection, E actual attempt inclusion, F local-date creation/idempotence/Undo, G referenced-task progress confirmation, and H provider failure/message retention. These are controlled protocol/executor tests, not proof that every natural-language response from a live model is correct. Further checks cover legacy decoding, bounded history/account reset, native wire IDs/results, late-page retrieval and execution-result feedback before a final reply.

The live synthetic fixture smoke checks advice for a real fixture deadline and forty-minute task, then a native task-creation call with the correct course and tomorrow in Europe/Madrid. It exposed two issues during repair: an invented duration and an unnecessary clarification. Duration validation and native tool selection for complete explicit requests address those cases. No real student records were mutated by the smoke test.

Final focused run: **25 tests passed** in `ConversationProviderTests`, `TaskWorkspaceTests` and `TaskStepProposalTests`. The live native loop actually created the synthetic task in an in-memory store, returned saved IDs to OpenAI, and received a final success response. The correct course, local tomorrow, unknown duration and Undo receipt were verified. The final standalone macOS build succeeded (`xcodebuild ... build`). UI automation remains limited: the existing correct-bundle app process could not be terminated by XCTest. It was not force-quit. Whole-app accessibility/iPad and all A–H live pedagogical answers remain unverified.

## Primary API references

- [OpenAI function calling](https://developers.openai.com/api/docs/guides/function-calling)
- [Claude tools](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools)
- [Gemini function calling](https://ai.google.dev/gemini-api/docs/function-calling)
