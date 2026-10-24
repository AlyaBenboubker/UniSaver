import Foundation
import SwiftData
import Testing
@testable import UniSaver

private final class FixtureConversationProvider: AIProvider {
    let id: AIRevisionProviderID = .openAI
    let model = "fixture-only"
    var replies: [AgentProviderTurn]
    var requests: [[[String: Any]]] = []
    var receivedSystem = ""
    var failure: Error?
    init(_ replies: [AgentProviderTurn] = []) { self.replies = replies }
    func complete(systemPrompt: String, userPrompt: String) async throws -> String { throw AIRevisionError.emptyResponse }
    func agentTurn(system: String, messages: [[String: Any]], tools: [[String: Any]], requiredTool: String?) async throws -> AgentProviderTurn {
        receivedSystem = system; requests.append(messages)
        if let failure { throw failure }
        guard !replies.isEmpty else { throw AIRevisionError.emptyResponse }
        return replies.removeFirst()
    }
}

struct ConversationProviderTests {
    @Test @MainActor func studyBlocksSaveRetryAndSurviveStoreReopening() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StudyBlocks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("fixture.store")
        func configuration() -> ModelConfiguration {
            ModelConfiguration("StudyBlocksRegression", schema: PersistenceController.schema, url: url)
        }
        do {
            let container = try ModelContainer(for: PersistenceController.schema, configurations: [configuration()])
            let context = ModelContext(container)
            let course = Course(name: "Fixture course", code: "FIX")
            let task = AcademicTask(title: "Fixture task", dueDate: .distantFuture, course: course)
            context.insert(course); context.insert(task)
            let note = TodayConversationStore.conversationNote(in: [], context: context)
            var state = TodayConversationState()
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            var action = ConversationActionDraft(id: UUID().uuidString, kind: .proposeWorkSessions,
                title: task.title, sourceText: "fixture", evidence: .needsConfirmation,
                selectedCourseID: course.id, courseCandidates: [], dueDate: nil, estimatedMinutes: nil,
                existingTaskID: task.id, existingTaskTitle: task.title, fingerprint: "fixture")
            action.sessions = [ConversationWorkSessionDraft(title: task.title, startDate: start,
                endDate: start.addingTimeInterval(1800), reason: "fixture")]
            var proposal = ConversationAnalysisProposal(id: UUID().uuidString, createdAt: start,
                referenceDate: start, timeZoneIdentifier: "Europe/Madrid", originalMessage: "fixture",
                summary: "fixture", actions: [action], warnings: [])
            _ = try ConversationActionExecutor.apply(proposal, state: &state, note: note, context: context)
            #expect(try context.fetch(FetchDescriptor<StudyBlock>()).count == 1)
            _ = try ConversationActionExecutor.apply(proposal, state: &state, note: note, context: context)
            #expect(try context.fetch(FetchDescriptor<StudyBlock>()).count == 1)
            proposal.id = UUID().uuidString
            proposal.actions[0].sessions = (1...2).map { offset in
                let date = start.addingTimeInterval(Double(offset) * 3600)
                return ConversationWorkSessionDraft(title: task.title, startDate: date,
                    endDate: date.addingTimeInterval(1800), reason: "fixture")
            }
            _ = try ConversationActionExecutor.apply(proposal, state: &state, note: note, context: context)
            #expect(try context.fetch(FetchDescriptor<StudyBlock>()).count == 3)
        }
        let reopened = try ModelContainer(for: PersistenceController.schema, configurations: [configuration()])
        let blocks = try ModelContext(reopened).fetch(FetchDescriptor<StudyBlock>())
        #expect(blocks.count == 3)
        #expect(blocks.allSatisfy { $0.task?.title == "Fixture task" && $0.course?.code == "FIX" })
    }
    @Test @MainActor func studySchedulingRejectsInvalidArgumentsWithoutMutation() async throws {
        let (_, task, service) = fixture()
        let cases: [[String: Any]] = [
            ["task_id": task.id.uuidString, "start": "not-a-date", "end": "2026-10-14T12:00:00+02:00", "reason": "test"],
            ["task_id": task.id.uuidString, "start": "2026-10-14T09:00:00+02:00", "end": "2026-10-14T14:00:00+02:00", "reason": "test"],
            ["task_id": UUID().uuidString, "start": "2026-10-14T09:00:00+02:00", "end": "2026-10-14T10:00:00+02:00", "reason": "test"]
        ]
        for arguments in cases {
            let provider = FixtureConversationProvider([try call("propose_schedule", arguments),
                AgentProviderTurn(text: "Please review the invalid input.", calls: [])])
            var state = TodayConversationState()
            state.messages = [TodayConversationMessage(role: .student, text: "Schedule a study block please.")]
            let result = try await service.respond(state: state, provider: provider)
            #expect(result.proposal == nil)
            #expect(!result.toolResults.isEmpty)
            #expect(task.status == .todo)
        }
    }
    @MainActor private func fixture() -> (Course, AcademicTask, ConversationProviderService) {
        let course = Course(name: "Accounting", code: "ACC")
        let due = ISO8601DateFormatter().date(from: "2026-10-14T00:00:00+02:00")!
        let task = AcademicTask(title: "Accounting Case 2", taskDescription: "- [ ] Reconcile the cash flow\n- [ ] Check the totals", dueDate: due, estimatedDuration: 2400, course: course)
        return (course, task, ConversationProviderService(courses: [course], tasks: [task], studyBlocks: [], page: "today",
            selectedCourseID: course.id, selectedTaskID: task.id, now: due.addingTimeInterval(-86400), timeZone: TimeZone(identifier: "Europe/Madrid")!))
    }
    private func call(_ name: String, _ args: [String: Any]) throws -> AgentProviderTurn {
        AgentProviderTurn(text: "", calls: [AgentToolCall(id: UUID().uuidString, name: name,
            arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))])
    }

    @Test @MainActor func nextWorkAndFortyMinutesReceiveRealContextAndHistory() async throws {
        let (_, task, service) = fixture()
        let provider = FixtureConversationProvider([AgentProviderTurn(text: "Spend 30 minutes reconciling cash flow, then 10 checking totals; Case 2 is due tomorrow.", calls: [])])
        var state = TodayConversationState()
        state.messages = [TodayConversationMessage(role: .student, text: "What should I work on next?"),
            TodayConversationMessage(role: .agent, text: "Do you mean Accounting Case 2?"),
            TodayConversationMessage(role: .student, text: "Yes. I have 40 minutes.")]
        let result = try await service.respond(state: state, provider: provider)
        let sent = String(describing: provider.requests)
        #expect(sent.contains(task.id.uuidString))
        #expect(sent.contains("Europe/Madrid")); #expect(sent.contains("2026-10-14"))
        #expect(sent.contains("Reconcile the cash flow")); #expect(sent.contains("Yes. I have 40 minutes."))
        #expect(sent.contains("Do you mean Accounting")); #expect(result.proposal == nil)
        #expect(provider.requests.count == 1)
    }

    @Test @MainActor func selectedBriefRetrievalAndToolResultsReturnToProvider() async throws {
        let (_, task, initial) = fixture()
        var service = initial
        service.selectedSources = [AIRevisionSource(id: "brief", title: "Case 2", kind: .resource, detail: "brief.txt",
            text: "[p.1] Context\n\n[p.7] Deliver a cash flow statement with three reconciled totals.", sourceReference: "brief.txt")]
        let provider = FixtureConversationProvider([
            try call("read_selected_resource", ["resource_id": "brief", "query": "cash flow totals"]),
            try call("propose_subtasks", ["task_id": task.id.uuidString, "steps": ["Draft the cash flow statement", "Reconcile the three totals"]]),
            AgentProviderTurn(text: "Review these two steps, grounded in brief.txt p.7.", calls: [])])
        var state = TodayConversationState(); state.messages = [TodayConversationMessage(role: .student, text: "Break this assignment into steps.")]
        let result = try await service.respond(state: state, provider: provider)
        #expect(result.proposal?.actions.first?.subtasks.count == 2)
        #expect(result.toolResults.joined().contains("[p.7]"))
        #expect(String(describing: provider.requests.last).contains("pending_review"))
        #expect(task.taskDescription.contains("Reconcile the cash flow")) // proposals do not mutate
    }

    @Test @MainActor func unsharedPassageIsDeniedAndActualAttemptIsIncluded() async throws {
        let (_, _, service) = fixture()
        let provider = FixtureConversationProvider([try call("read_selected_resource", ["resource_id": "private", "query": "Explain this part"]),
            AgentProviderTurn(text: "Which passage would you like to share?", calls: [])])
        var state = TodayConversationState(); state.messages = [TodayConversationMessage(role: .student, text: "Explain this part. Check my answer: assets 30 minus liabilities 12 gives equity 18.")]
        let result = try await service.respond(state: state, provider: provider)
        #expect(result.toolResults.first?.contains("not explicitly shared") == true)
        #expect(String(describing: provider.requests.first).contains("equity 18"))
        #expect(result.proposal == nil)
        #expect(provider.receivedSystem.contains("inspect the actual attempt"))
    }

    @Test @MainActor func localDateCreationPersistsDeduplicatesAndUndoes() async throws {
        let (course, task, service) = fixture()
        let provider = FixtureConversationProvider([try call("create_task", ["title": "Prepare Accounting Case 2", "course_id": course.id.uuidString, "due_date": "2026-10-14", "estimated_minutes": 0]), AgentProviderTurn(text: "Task prepared.", calls: [])])
        var state = TodayConversationState(); state.messages = [TodayConversationMessage(role: .student, text: "Add a task to prepare Accounting Case 2 tomorrow.")]
        let result = try await service.respond(state: state, provider: provider)
        let proposal = try #require(result.proposal)
        #expect(proposal.actions.first?.dueDate == service.parseLocalDay("2026-10-14"))
        #expect(ConversationActionExecutor.permitsImmediateCreation(state.messages[0].text))
        #expect(!ConversationActionExecutor.permitsImmediateCreation("What should I work on next?"))
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.insert(course); context.insert(task)
        let note = TodayConversationStore.conversationNote(in: [], context: context)
        _ = try ConversationActionExecutor.apply(proposal, state: &state, note: note, context: context)
        _ = try ConversationActionExecutor.apply(proposal, state: &state, note: note, context: context)
        var retry = proposal; retry.id = UUID().uuidString
        _ = try ConversationActionExecutor.apply(retry, state: &state, note: note, context: context)
        #expect(try context.fetch(FetchDescriptor<AcademicTask>()).count == 2)
        #expect(TodayConversationStore.decode(note).appliedProposalIDs?.contains(proposal.id) == true)
        try ConversationActionExecutor.undoCreation(state: &state, note: note, context: context)
        #expect(try context.fetch(FetchDescriptor<AcademicTask>()).count == 1)
    }

    @Test @MainActor func creationExecutorResultReturnsThroughNativeLoopBeforeFinalReply() async throws {
        let (course, task, service) = fixture()
        let provider = FixtureConversationProvider([try call("create_task", ["title": "Prepare Accounting Case 2", "course_id": course.id.uuidString, "due_date": "2026-10-14", "estimated_minutes": 0]), AgentProviderTurn(text: "The task has been created. Undo is available.", calls: [])])
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.insert(course); context.insert(task)
        let note = TodayConversationStore.conversationNote(in: [], context: context)
        var state = TodayConversationState(); state.messages = [TodayConversationMessage(role: .student, text: "Add a task to prepare Accounting Case 2 tomorrow.")]
        let requestState = state
        let result = try await service.respond(state: requestState, provider: provider, performCreation: { proposal in
            let saved = try ConversationActionExecutor.apply(proposal, state: &state, note: note, context: context)
            return try AgentNativeWire.encoded(["status": "saved", "result": saved, "task_ids": state.lastExecutionTaskIDs!.map(\.uuidString)])
        })
        #expect(result.proposal == nil)
        #expect(try context.fetch(FetchDescriptor<AcademicTask>()).count == 2)
        #expect(String(describing: provider.requests.last).contains("saved"))
        #expect(state.creationReceipt?.taskIDs.count == 1)
    }

    @Test @MainActor func finishedReferenceRequiresReviewThenAppliesCorrectProgress() async throws {
        let (course, task, service) = fixture()
        let provider = FixtureConversationProvider([try call("update_progress", ["task_id": task.id.uuidString, "status": "completed"]), AgentProviderTurn(text: "Confirm completion of Case 2.", calls: [])])
        var state = TodayConversationState(); state.messages = [TodayConversationMessage(role: .agent, text: "Work on Accounting Case 2."), TodayConversationMessage(role: .student, text: "I already finished that.")]
        let result = try await service.respond(state: state, provider: provider)
        #expect(task.status == .todo)
        #expect(result.proposal?.actions.first?.existingTaskID == task.id)
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.insert(course); context.insert(task)
        let note = TodayConversationStore.conversationNote(in: [], context: context)
        _ = try ConversationActionExecutor.apply(try #require(result.proposal), state: &state, note: note, context: context)
        #expect(task.status == .completed)
    }

    @Test @MainActor func providerFailureHasNoFakeReplyAndLeavesMessageIntact() async throws {
        let (_, _, service) = fixture(); let provider = FixtureConversationProvider()
        provider.failure = AIRevisionError.providerError("HTTP 503")
        var state = TodayConversationState(); state.messages = [TodayConversationMessage(role: .student, text: "Help me prepare the test.")]
        do { _ = try await service.respond(state: state, provider: provider); Issue.record("Expected provider error") }
        catch { #expect(error.localizedDescription == "HTTP 503") }
        #expect(state.messages.count == 1); #expect(state.messages[0].text == "Help me prepare the test.")
    }

    @Test @MainActor func boundedHistoryAndAccountSwitchDropPrivateContext() throws {
        var state = TodayConversationState(); state.accountID = "A"
        state.messages = (0..<50).map { TodayConversationMessage(role: .student, text: "Correction \($0): Accounting Thursday") }
        state.toolResults = ["task_id: confirmed-record"]
        state.compact()
        #expect(state.messages.count == 16); #expect(state.contextMemory?.contains("Correction 33") == true)
        state.prepareForAccount("B")
        #expect(state.messages.isEmpty); #expect(state.contextMemory == nil); #expect(state.toolResults == nil)
        let legacy = StudyNote(title: "Legacy", body: TodayConversationStore.marker + "{\"schemaVersion\":1,\"messages\":[],\"pendingProposals\":{}}")
        #expect(TodayConversationStore.decode(legacy).accountID == nil)
    }

    @Test func nativeWireParsingKeepsToolIDsAndResults() throws {
        let data = Data("{\"choices\":[{\"message\":{\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"function\":{\"name\":\"find_courses\",\"arguments\":\"{\\\"query\\\":\\\"Accounting\\\"}\"}}]}}]}".utf8)
        let turn = try AgentProviderTurn.openAI(data)
        #expect(turn.calls.first?.id == "c1")
        let messages: [[String: Any]] = [["role": "assistant", "tool_calls": turn.calls.map(\.wireValue)], ["role": "tool", "tool_call_id": "c1", "content": "{\"id\":\"course-1\"}"]]
        #expect(String(describing: try AgentNativeWire.claudeMessages(messages)).contains("tool_use_id"))
        #expect(String(describing: try AgentNativeWire.geminiMessages(messages)).contains("functionResponse"))
    }

    @Test func documentRetrievalCanFindLatePageWithoutSendingWholeDocument() {
        let pages = (0..<100).map { ($0, "[p.\($0 + 1)] " + ($0 == 90 ? "Accounting cash flow required deliverable" : "General background")) }
        let text = TaskWorkspaceService.retrievedText(pages, query: "cash flow deliverable")
        #expect(text.contains("[p.91]")); #expect(text.contains("6 of 100")); #expect(text.count < 12000)
    }

    private func smokeReport(_ metadata: [String: Any]) throws {
        // Synthetic fixtures only; never keys or real student records.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UniSaver-agent-smoke-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted]).write(to: url)
    }

    @Test @MainActor func liveProviderSmokeIfSecureConfigurationExists() async throws {
        let provider: AIProvider
        do { provider = try AIRevisionAssistantClient().conversationProvider() }
        catch AIRevisionError.missingAPIKey { try smokeReport(["status": "skipped", "reason": "No key accessible in signed test host"]); return }
        catch AIRevisionError.notConfigured { try smokeReport(["status": "skipped", "reason": "Unavailable funding mode"]); return }
        let (course, task, service) = fixture()
        var state = TodayConversationState(); state.messages = [TodayConversationMessage(role: .student, text: "I have 40 minutes. What should I work on next? Explain the reason briefly.")]
        let result = try await service.respond(state: state, provider: provider)
        #expect(!result.text.isEmpty)
        #expect(result.proposal == nil) // advice does not authorize mutation
        state.messages.append(TodayConversationMessage(role: .agent, text: result.text))
        state.messages.append(TodayConversationMessage(role: .student, text: "Add a task to prepare Accounting Case 2 tomorrow."))
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.insert(course); context.insert(task)
        let note = TodayConversationStore.conversationNote(in: [], context: context)
        let requestState = state
        var executedProposal: ConversationAnalysisProposal?
        let creation = try await service.respond(state: requestState, provider: provider, performCreation: { proposal in
            executedProposal = proposal
            let saved = try ConversationActionExecutor.apply(proposal, state: &state, note: note, context: context)
            return try AgentNativeWire.encoded(["status": "saved", "result": saved,
                "task_ids": state.lastExecutionTaskIDs!.map(\.uuidString), "undo_available": true])
        }, refreshTasks: { try context.fetch(FetchDescriptor<AcademicTask>()) })
        try smokeReport(["status": "completed", "provider": result.provider, "model": result.model,
            "advice": result.text, "creation_reply": creation.text,
            "creation_action_count": executedProposal?.actions.count ?? 0,
            "creation_course_matches": executedProposal?.actions.first?.selectedCourseID == service.selectedCourseID,
            "creation_date_matches": executedProposal?.actions.first?.dueDate == service.parseLocalDay("2026-10-14"),
            "creation_estimated_minutes": executedProposal?.actions.first?.estimatedMinutes ?? -1,
            "creation_authorized": executedProposal.map { ConversationActionExecutor.permitsImmediateCreation(requestState.messages.last!.text, proposal: $0, courses: service.courses, selectedCourseID: service.selectedCourseID) } ?? false])
        #expect(creation.proposal == nil)
        #expect(try context.fetch(FetchDescriptor<AcademicTask>()).count == 2)
        #expect(state.creationReceipt?.taskIDs.count == 1)
        #expect(executedProposal?.actions.first?.estimatedMinutes == 0)
        #expect(executedProposal?.actions.first?.kind == .createTask)
        #expect(executedProposal?.actions.first?.selectedCourseID == service.selectedCourseID)
        #expect(executedProposal?.actions.first?.dueDate == service.parseLocalDay("2026-10-14"))
    }
}
