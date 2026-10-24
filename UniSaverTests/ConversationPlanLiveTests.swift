import Foundation
import SwiftData
import Testing
@testable import UniSaver

/// Uses synthetic briefs and isolated local stores. Never logs credentials or loads student records.
@MainActor
struct ConversationPlanLiveTests {
    @Test func configuredProviderPlansFocusWeeklyAndAssignmentAndPersistsApprovedActions() async throws {
        let provider: AIProvider
        do { provider = try AIRevisionAssistantClient().conversationProvider() }
        catch AIRevisionError.missingAPIKey { try report(["status": "skipped", "reason": "No configured key accessible"]); return }
        catch AIRevisionError.notConfigured { try report(["status": "skipped", "reason": "No personal-key provider configured"]); return }
        let accounting = Course(name: "Accounting II", code: "ACC"), law = Course(name: "Business Law", code: "LAW")
        let cases: [(String, String, [Course])] = [
            ("focus", ConversationPlanTests.focusBrief, []),
            ("weekly", "Week of 2026-10-12.\nAccounting II: Prepare Case 2 by 2026-10-14.\nBusiness Law: Read Case Study 2. No deadline supplied.\nNo classes on Monday is background information, not a task.", [accounting, law]),
            ("assignment", "Compare two approaches in a written summary.\nAttach annotated derivations.\nDo not add a presentation.\nNo deadline supplied.", [])]
        var results: [[String: Any]] = []
        for (name, source, courses) in cases {
            var state = TodayConversationState()
            state.messages = [.init(role: .student, text: ConversationPlanningRequest.taskCommand(for: source))]
            var service = ConversationProviderService(courses: courses, tasks: [], studyBlocks: [], page: "today",
                selectedCourseID: nil, selectedTaskID: nil, now: Date(), timeZone: TimeZone(identifier: "Europe/Madrid")!)
            let response = try await service.respond(state: state, provider: provider)
            var proposal = try #require(response.proposal)
            #expect(proposal.actions.allSatisfy { $0.isStructuredPlan == true && $0.estimatedMinutes == nil })
            if name == "focus" {
                #expect(proposal.actions.count == 1)
                #expect(proposal.actions[0].title == "Improve UniSaver Focus Workspace")
                #expect(proposal.actions[0].subtasks.count == 6)
                #expect(proposal.actions[0].planConstraints?.joined().lowercased().contains("no general redesign") == true)
            }
            if name == "weekly" { #expect(proposal.actions.count == 2) }
            if name != "weekly" { #expect(proposal.actions.allSatisfy { $0.dueDate == nil }) }
            if name == "focus", !proposal.actions[0].subtasks.isEmpty {
                proposal.actions[0].subtasks[0].title += " — reviewed"
                proposal.actions[0].subtasks[0].evidence = .suggested
            }
            state.pendingProposals[proposal.id] = proposal
            state.messages.append(.init(role: .agent, text: response.text, proposalID: proposal.id))
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            func configuration() -> ModelConfiguration {
                ModelConfiguration("LiveReviewedPlan", schema: PersistenceController.schema, url: directory.appendingPathComponent("plan.store"))
            }
            let container = try ModelContainer(for: PersistenceController.schema, configurations: [configuration()])
            let context = ModelContext(container); context.autosaveEnabled = false
            for course in courses { context.insert(course) }
            context.insert(StudyNote(title: "Working note", body: "Preserved synthetic working note"))
            let note = TodayConversationStore.conversationNote(in: [], context: context)
            TodayConversationStore.save(state, into: note); try context.save()
            let execution = try ConversationActionExecutor.apply(proposal, state: &state, note: note, context: context)
            _ = try ConversationActionExecutor.apply(proposal, state: &state, note: note, context: context)
            let saved = try context.fetch(FetchDescriptor<AcademicTask>())
            #expect(saved.count == proposal.actions.count)
            #expect(saved.allSatisfy { $0.status == .todo && $0.estimatedDuration == 0 })
            if name == "focus" {
                service.tasks = saved
                var followup = state
                followup.messages.append(.init(role: .student, text: "I've already done the first part."))
                let update = try await service.respond(state: followup, provider: provider)
                let revision = try #require(update.proposal)
                #expect(revision.actions.first?.existingTaskID == saved.first?.id)
                #expect(revision.actions.first?.replacesSubtasks == true)
                followup.pendingProposals[revision.id] = revision
                followup.messages.append(.init(role: .agent, text: update.text, proposalID: revision.id))
                TodayConversationStore.save(followup, into: note); try context.save()
                _ = try ConversationActionExecutor.apply(revision, state: &followup, note: note, context: context)
                #expect(saved.first?.status == .todo)
                #expect(TaskStructureService.subtasks(from: saved[0]).first?.isCompleted == true)
                #expect(TaskStructureService.subtasks(from: saved[0]).count == 6)
            }
            let reopened = try ModelContainer(for: PersistenceController.schema, configurations: [configuration()])
            let read = ModelContext(reopened)
            let persistedTasks = try read.fetch(FetchDescriptor<AcademicTask>())
            #expect(persistedTasks.count == proposal.actions.count)
            let notes = try read.fetch(FetchDescriptor<StudyNote>())
            #expect(notes.contains { $0.body == "Preserved synthetic working note" })
            #expect(!notes.contains { $0.body.hasPrefix(GamificationLedgerStore.marker) })
            results.append(["case": name, "parent_titles": proposal.actions.map(\.title),
                "step_titles": proposal.actions.flatMap(\.subtasks).map(\.title),
                "constraints": proposal.actions.flatMap { $0.planConstraints ?? [] }, "execution": execution,
                "persisted_parent_count": persistedTasks.count,
                "first_incomplete_step": persistedTasks.flatMap { TaskStructureService.subtasks(from: $0) }.first(where: { !$0.isCompleted })?.title ?? "Parent task itself",
                "source_length": source.count])
            try report(["status": "running", "provider": provider.id.rawValue, "model": provider.model, "cases": results])
        }
        try report(["status": "completed", "provider": provider.id.rawValue, "model": provider.model, "cases": results])
    }

    private func report(_ value: [String: Any]) throws {
        let url = URL(fileURLWithPath: "/tmp/UniSaver-conversation-plan-live.json")
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]).write(to: url, options: .atomic)
    }
}
