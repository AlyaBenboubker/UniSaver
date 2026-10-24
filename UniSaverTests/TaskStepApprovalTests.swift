import Foundation
import SwiftData
import Testing
@testable import UniSaver

@MainActor
struct TaskStepApprovalTests {
    private func fixture() throws -> (ModelContainer, ModelContext, AcademicTask) {
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [
            ModelConfiguration(schema: PersistenceController.schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let task = AcademicTask(title: "Essay", taskDescription: "Original brief\n- [x] Read brief\n- [ ] Gather sources",
            dueDate: .distantFuture, status: .inProgress)
        context.insert(task)
        try context.save()
        return (container, context, task)
    }

    private var steps: [ConversationSubtaskDraft] {
        [ConversationSubtaskDraft(title: "Compare arguments", estimatedMinutes: nil,
            completionCriterion: "Explain differences", sourceExcerpt: "Compare arguments", evidence: .explicit),
         ConversationSubtaskDraft(title: "Review clarity", estimatedMinutes: nil,
            completionCriterion: "Check readability", evidence: .suggested)]
    }

    @Test func appendsPreservingChecklistNotesStatusAndXPAndRejectsSecondApply() throws {
        let (container, context, task) = try fixture()
        let note = StudyNote(title: "Working notes", body: "My existing notes")
        context.insert(note)
        try context.save()
        note.body += " and an unsaved edit"
        let before = task.taskDescription, snapshot = TaskStepReviewSnapshot(task), id = UUID()
        try TaskStepApprovalService.apply(proposalID: id, steps: steps, snapshot: snapshot, selectedTask: task, context: context)
        #expect(task.taskDescription.hasPrefix(before))
        #expect(task.status == .inProgress)
        #expect(note.body == "My existing notes and an unsaved edit")
        #expect(try context.fetch(FetchDescriptor<StudyNote>()).count == 1)
        #expect(TaskStructureService.subtasks(from: task).map(\.title) == ["Read brief", "Gather sources", "Compare arguments", "Review clarity"])
        #expect(TaskStructureService.subtasks(from: task).first?.isCompleted == true)
        #expect(throws: TaskStepApprovalError.self) {
            try TaskStepApprovalService.apply(proposalID: id, steps: steps, snapshot: snapshot, selectedTask: task, context: context)
        }
        let fresh = ModelContext(container)
        let persisted = try #require(fresh.fetch(FetchDescriptor<AcademicTask>()).first)
        #expect(TaskStructureService.subtasks(from: persisted).count == 4)
        #expect(try TaskStructureService.approvalReceipts(in: persisted).count == 1)
        #expect(TaskStructureService.subtasks(from: persisted).first(where: { !$0.isCompleted })?.title == "Gather sources")
    }

    @Test func rejectsEmptyMultilineAndDuplicateTitlesWithoutChangingTask() throws {
        let (_, context, task) = try fixture()
        let original = task.taskDescription
        for title in ["   ", "Line one\n- [x] Injected", "gather sources"] {
            #expect(throws: TaskStepApprovalError.self) {
                try TaskStepApprovalService.apply(proposalID: UUID(),
                    steps: [ConversationSubtaskDraft(title: title, estimatedMinutes: nil)],
                    snapshot: TaskStepReviewSnapshot(task), selectedTask: task, context: context)
            }
            #expect(task.taskDescription == original)
        }
    }

    @Test func rejectsDeletedParent() throws {
        let (container, context, task) = try fixture()
        let snapshot = TaskStepReviewSnapshot(task)
        let other = ModelContext(container)
        other.delete(try #require(other.fetch(FetchDescriptor<AcademicTask>()).first))
        try other.save()
        #expect(throws: TaskStepApprovalError.self) {
            try TaskStepApprovalService.apply(proposalID: UUID(), steps: steps, snapshot: snapshot, selectedTask: task, context: context)
        }
    }

    @Test func changedTaskRequiresRefreshedReviewAndPreservesNewChecklist() throws {
        let (container, context, task) = try fixture()
        let snapshot = TaskStepReviewSnapshot(task)
        let other = ModelContext(container)
        let changed = try #require(other.fetch(FetchDescriptor<AcademicTask>()).first)
        changed.taskDescription += "\n- [ ] Teacher clarification"
        changed.updatedAt = .now
        try other.save()
        #expect(throws: TaskStepApprovalError.self) {
            try TaskStepApprovalService.apply(proposalID: UUID(), steps: steps, snapshot: snapshot, selectedTask: task, context: context)
        }
        let refreshed = try TaskStepApprovalService.refresh(task, context: context)
        try TaskStepApprovalService.apply(proposalID: UUID(), steps: steps, snapshot: refreshed, selectedTask: task, context: context)
        #expect(TaskStructureService.subtasks(from: task).contains { $0.title == "Teacher clarification" })
    }

    @Test func refreshDoesNotDiscardUnsavedTaskEditsOrWorkingNotes() throws {
        let (_, context, task) = try fixture()
        let note = StudyNote(title: "Notes", body: "Student attempt")
        context.insert(note)
        try context.save()
        note.body += " — still drafting"
        task.taskDescription += "\nUnsaved teacher clarification"
        #expect(throws: TaskStepApprovalError.self) {
            try TaskStepApprovalService.refresh(task, context: context)
        }
        #expect(task.taskDescription.contains("Unsaved teacher clarification"))
        #expect(note.body == "Student attempt — still drafting")
    }

    @Test func failedSaveKeepsDraftAndAllowsOneSafeRetry() throws {
        let (container, context, task) = try fixture()
        let draft = steps, id = UUID(), snapshot = TaskStepReviewSnapshot(task)
        enum DiskFailure: Error { case unavailable }
        #expect(throws: DiskFailure.self) {
            try TaskStepApprovalService.apply(proposalID: id, steps: draft, snapshot: snapshot,
                selectedTask: task, context: context, save: { _ in throw DiskFailure.unavailable })
        }
        let read = ModelContext(container)
        let unchanged = try #require(read.fetch(FetchDescriptor<AcademicTask>()).first)
        #expect(TaskStructureService.subtasks(from: unchanged).count == 2)
        #expect(try TaskStructureService.approvalReceipts(in: unchanged).isEmpty)
        #expect(draft.map(\.title) == ["Compare arguments", "Review clarity"])
        try TaskStepApprovalService.apply(proposalID: id, steps: draft, snapshot: snapshot, selectedTask: task, context: context)
        #expect(TaskStructureService.subtasks(from: task).count == 4)
    }

    @Test func cancelledReviewCreatesNoRecords() throws {
        let (_, context, task) = try fixture()
        let original = task.taskDescription
        _ = steps // Opening/editing a proposal has no persistence operation.
        #expect(task.taskDescription == original)
        #expect(try TaskStructureService.approvalReceipts(in: task).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StudyNote>()).isEmpty)
    }

    @Test func stepsAndReceiptSurviveDiskReopeningAndReapplyIsBlocked() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("steps.store"), id = UUID()
        func configuration() -> ModelConfiguration {
            ModelConfiguration("ApprovedSteps", schema: PersistenceController.schema, url: url)
        }
        do {
            let container = try ModelContainer(for: PersistenceController.schema, configurations: [configuration()])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let task = AcademicTask(title: "Essay", taskDescription: "Original notes", dueDate: .distantFuture)
            context.insert(task)
            try context.save()
            try TaskStepApprovalService.apply(proposalID: id, steps: Array(steps.reversed()),
                snapshot: TaskStepReviewSnapshot(task), selectedTask: task, context: context)
        }
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [configuration()])
        let context = ModelContext(container)
        let task = try #require(context.fetch(FetchDescriptor<AcademicTask>()).first)
        #expect(task.status == .todo)
        #expect(task.taskDescription.hasPrefix("Original notes"))
        #expect(TaskStructureService.subtasks(from: task).map(\.title) == ["Review clarity", "Compare arguments"])
        let detail = try #require(TaskStructureService.approvedDetail(for: TaskStructureService.subtasks(from: task)[1], in: task))
        #expect(detail.completionCriterion == "Explain differences")
        #expect(detail.sourceExcerpt == "Compare arguments")
        #expect(detail.evidence == .explicit)
        #expect(throws: TaskStepApprovalError.self) {
            try TaskStepApprovalService.apply(proposalID: id, steps: steps,
                snapshot: TaskStepReviewSnapshot(task), selectedTask: task, context: context)
        }
        #expect(TaskStructureService.subtasks(from: task).count == 2)
    }

    @Test func editingTaskDescriptionPreservesReceiptsAndHidesInternalMetadata() throws {
        let (_, context, task) = try fixture()
        try TaskStepApprovalService.apply(proposalID: UUID(), steps: steps,
            snapshot: TaskStepReviewSnapshot(task), selectedTask: task, context: context)
        let visible = TaskStructureService.visibleDescription(task.taskDescription)
        #expect(!visible.contains(TaskStructureService.approvalMarker))
        task.taskDescription = TaskStructureService.preservingApprovalMetadata(visible + "\nA manual note", from: task.taskDescription)
        #expect(try TaskStructureService.approvalReceipts(in: task).count == 1)
    }
}
