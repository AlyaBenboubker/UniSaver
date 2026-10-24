import Foundation
import SwiftData
import Testing
@testable import UniSaver

struct TaskWorkspaceTests {
    @Test @MainActor func legacyLedgerStillDecodesWithoutWorkspaceFields() throws {
        let note = StudyNote(title: "Ledger", body: TaskExecutionLedgerStore.marker + "{\"schemaVersion\":1,\"records\":[]}")
        #expect(TaskExecutionLedgerStore.decode(note).records.isEmpty)
        #expect(TaskExecutionLedgerStore.decode(note).workspaces == nil)
    }

    @Test @MainActor func taskSessionSurvivesDiskStoreReopeningWithoutDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("study.store")
        let taskID = UUID()
        let resourceID = UUID()
        let sessionID = UUID()
        func configuration() -> ModelConfiguration {
            ModelConfiguration("WorkspaceRegression", schema: PersistenceController.schema, url: store)
        }
        do {
            let container = try ModelContainer(for: PersistenceController.schema, configurations: [configuration()])
            let context = ModelContext(container)
            let task = AcademicTask(id: taskID, title: "HW2 submission", dueDate: .distantFuture, status: .inProgress)
            TaskStructureService.appendSuggestedSteps(to: task)
            let item = try #require(TaskStructureService.subtasks(from: task).first)
            TaskStructureService.setSubtask(item, completed: true, in: task)
            context.insert(task)
            var ledger = TaskExecutionLedger()
            var draft = TaskWorkspaceDraft(taskID: taskID, sessionID: sessionID)
            draft.notes = "Attempt: 2x = 8, x = 4"
            draft.remainingWork = "Check the second exercise, then submit"
            draft.resourceIDs = [resourceID]
            draft.activeStepID = item.id
            draft.pastedInstructions = "Show your working; submit a PDF"
            draft.links = ["https://example.org/brief"]
            draft.messages = [TodayConversationMessage(role: .student, text: "Give me a hint")]
            draft.helpRequests = 1
            TaskWorkspaceService.upsert(draft, into: &ledger)
            TaskWorkspaceService.upsert(draft, into: &ledger)
            let record = TaskExecutionRecord(id: sessionID, taskID: taskID, startedAt: draft.startedAt, endedAt: .now,
                completedSubtaskTitles: [item.title], finishedTask: false, proofLevel: .supportingAttachment,
                note: draft.notes, attachments: [WorkEvidenceAttachment(kind: .note, displayName: "Work", note: "My result", uploadState: .localOnly)],
                remainingWork: draft.remainingWork, helpRequests: 1)
            TaskWorkspaceService.append(record, into: &ledger)
            TaskWorkspaceService.append(record, into: &ledger)
            let note = TaskExecutionLedgerStore.ledgerNote(in: [], context: context)
            TaskExecutionLedgerStore.save(ledger, into: note)
            try context.save()
        }
        let reopened = try ModelContainer(for: PersistenceController.schema, configurations: [configuration()])
        let context = ModelContext(reopened)
        let notes = try context.fetch(FetchDescriptor<StudyNote>())
        let note = try #require(notes.first { $0.body.hasPrefix(TaskExecutionLedgerStore.marker) })
        let ledger = TaskExecutionLedgerStore.decode(note)
        let draft = try #require(ledger.workspaces?.first)
        #expect(ledger.workspaces?.count == 1)
        #expect(ledger.records.count == 1)
        #expect(draft.notes == "Attempt: 2x = 8, x = 4")
        #expect(draft.resourceIDs == [resourceID])
        #expect(draft.messages.count == 1)
        #expect(draft.activeStepID != nil)
        #expect(draft.pastedInstructions == "Show your working; submit a PDF")
        #expect(ledger.records[0].remainingWork == draft.remainingWork)
        #expect(ledger.records[0].attachments[0].note == "My result")
        let task = try #require(context.fetch(FetchDescriptor<AcademicTask>()).first)
        #expect(task.status == .inProgress)
        #expect(TaskStructureService.subtasks(from: task).first?.isCompleted == true)
    }

    @Test @MainActor func staleQueryCannotCreateDuplicateSystemLedgers() throws {
        let config = ModelConfiguration(schema: PersistenceController.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [config])
        let context = ModelContext(container)
        let first = TaskExecutionLedgerStore.ledgerNote(in: [], context: context)
        let second = TaskExecutionLedgerStore.ledgerNote(in: [], context: context)
        #expect(first.id == second.id)
        let reward = GamificationLedgerStore.ledgerNote(in: [], context: context)
        #expect(reward.id == GamificationLedgerStore.ledgerNote(in: [], context: context).id)
        let conversation = TodayConversationStore.conversationNote(in: [], context: context)
        #expect(conversation.id == TodayConversationStore.conversationNote(in: [], context: context).id)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<StudyNote>()).count == 3)
    }

    @Test @MainActor func manualCorrectionsAndDraftSharingArePreserved() {
        let task = AcademicTask(title: "HW2", dueDate: .distantFuture)
        var draft = TaskWorkspaceDraft(taskID: task.id)
        draft.notes = "PRIVATE_ATTEMPT"
        draft.remainingWork = "Finish exercise 2"
        let hidden = TaskWorkspaceService.context(task: task, draft: draft, assignment: nil)
        #expect(!hidden.contains("PRIVATE_ATTEMPT"))
        draft.shareNotes = true
        #expect(TaskWorkspaceService.context(task: task, draft: draft, assignment: nil).contains("PRIVATE_ATTEMPT"))
        var ledger = TaskExecutionLedger()
        TaskWorkspaceService.upsert(draft, into: &ledger)
        draft.notes = "Corrected by the student"
        draft.planCorrections = 1
        TaskWorkspaceService.upsert(draft, into: &ledger)
        #expect(ledger.workspaces?.count == 1)
        #expect(ledger.workspaces?.first?.notes == "Corrected by the student")
    }

    @Test @MainActor func sourceLessBriefHasNoInventedDeadlineOrCriteria() {
        let result = AssignmentExtractor.extract(text: "HW2 submission\nSubmit your answers as a PDF.", sourceName: "Brief.txt", fallbackTitle: "HW2")
        #expect(result.deadline == nil)
        #expect(result.requirements.contains { $0.kind == "deliverable" })
        #expect(!result.requirements.contains { $0.kind == "grading" })
        let project = AssignmentPlanProject(title: result.title, courseName: "Math")
        let milestones = AssignmentPlannerEngine.buildMilestones(for: project)
        #expect(milestones.allSatisfy { $0.dueDate == nil })
        #expect(milestones.last?.title == "Submit the final work")
        #expect(milestones[1].dependencyIDs == [milestones[0].id])
        #expect(milestones[1].detail.contains("Generic"))
    }

    @Test @MainActor func onlySubmissionUsesSuppliedDeadlineAndSchedulingNeedsApproval() {
        var project = AssignmentPlanProject(title: "HW2", courseName: "Math")
        project.deadline = Date().addingTimeInterval(7 * 86400)
        let milestones = AssignmentPlannerEngine.buildMilestones(for: project)
        #expect(milestones.dropLast().allSatisfy { $0.dueDate == nil })
        #expect(milestones.last?.dueDate == project.deadline)
        let sessions = AssignmentPlannerEngine.buildSessions(milestones: milestones, project: project, classSessions: [], studyBlocks: []).sessions
        #expect(!sessions.isEmpty)
        #expect(sessions.allSatisfy { !$0.isApproved })
    }

    @Test @MainActor func taskEstimateCanBeAbsentButNeverNegativeOrInvalid() throws {
        try AcademicValidationService.validateTask(title: "Manual work", estimatedDuration: 0, course: nil, chapter: nil)
        #expect(throws: AcademicValidationError.invalidDuration) {
            try AcademicValidationService.validateTask(title: "Work", estimatedDuration: -1, course: nil, chapter: nil)
        }
        #expect(throws: AcademicValidationError.invalidDuration) {
            try AcademicValidationService.validateTask(title: "Work", estimatedDuration: .nan, course: nil, chapter: nil)
        }
    }

    @Test @MainActor func repeatedChecklistGenerationPreservesManualWork() {
        let task = AcademicTask(title: "HW2 submission", taskDescription: "Student correction\n- [x] Solve question A\n- [ ] Submit PDF", dueDate: .now)
        let before = task.taskDescription
        TaskStructureService.appendSuggestedSteps(to: task)
        TaskStructureService.appendSuggestedSteps(to: task)
        #expect(task.taskDescription == before)
    }

    @Test @MainActor func countdownDoesNotCompleteTaskOrAwardXPAndCompletionIsIdempotent() {
        let task = AcademicTask(title: "Work", dueDate: .now, status: .inProgress)
        let now = Date()
        let timer = ActiveTaskTimer(taskID: task.id, mode: .countdown, startedAt: now.addingTimeInterval(-60), accumulatedSeconds: 0, targetSeconds: 30)
        #expect(timer.remainingSeconds(now: now) == 0)
        #expect(task.status == .inProgress)
        var ledger = GamificationLedger()
        ledger.settings.systemStartedAt = now.addingTimeInterval(-100)
        GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: task.id.uuidString, courseID: nil, occurredAt: now, ledger: &ledger)
        let count = ledger.events.count
        GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: task.id.uuidString, courseID: nil, occurredAt: now, ledger: &ledger)
        #expect(ledger.events.count == count)
    }
}
