import Foundation
import SwiftData

struct TaskStepReviewSnapshot: Codable, Hashable {
    let title: String
    let description: String
    let courseID: UUID?
    let chapterID: UUID?
    let sessionID: UUID?
    let dueDate: Date
    let status: AcademicTaskStatus
    let priority: AcademicTaskPriority
    let duration: TimeInterval
    let updatedAt: Date

    init(_ task: AcademicTask) {
        title = task.title; description = task.taskDescription
        courseID = task.course?.id
        chapterID = task.chapter?.id; sessionID = task.session?.id
        dueDate = task.dueDate; status = task.status; priority = task.priority
        duration = task.estimatedDuration; updatedAt = task.updatedAt
    }
}

struct TaskStepApprovalReceipt: Codable {
    let proposalID: UUID
    let steps: [ConversationSubtaskDraft]
}

enum TaskStepApprovalError: LocalizedError {
    case missingTask, changedTask, alreadyApplied, invalidSteps, corruptReceipt, unsavedTaskEdits
    var errorDescription: String? {
        switch self {
        case .missingTask: "The selected task no longer exists. Your reviewed steps are kept."
        case .changedTask: "The task changed during review. Refresh the task context and review your steps before saving."
        case .alreadyApplied: "This proposal has already been saved. No duplicate steps were added."
        case .invalidSteps: "Keep at least one step. Titles must be nonempty, unique, single-line text (up to 500 characters)."
        case .unsavedTaskEdits: "Save your current task edits before refreshing the review. Working notes are preserved."
        case .corruptReceipt: "Saved step metadata could not be read. No changes were made."
        }
    }
}

extension TaskStructureService {
    static let approvalMarker = "UniSaverApprovedStepsV1:"

    static func visibleDescription(_ description: String) -> String {
        description.components(separatedBy: .newlines).filter { !$0.hasPrefix(approvalMarker) }.joined(separator: "\n")
    }

    static func preservingApprovalMetadata(_ edited: String, from original: String) -> String {
        let receipts = original.components(separatedBy: .newlines).filter { $0.hasPrefix(approvalMarker) }
        return ([visibleDescription(edited)] + receipts).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func approvalReceipts(in task: AcademicTask) throws -> [TaskStepApprovalReceipt] {
        try task.taskDescription.components(separatedBy: .newlines).filter { $0.hasPrefix(approvalMarker) }.map { line in
            do { return try JSONDecoder().decode(TaskStepApprovalReceipt.self, from: Data(line.dropFirst(approvalMarker.count).utf8)) }
            catch { throw TaskStepApprovalError.corruptReceipt }
        }
    }

    static func approvedDetail(for step: TaskSubtaskItem, in task: AcademicTask) -> ConversationSubtaskDraft? {
        (try? approvalReceipts(in: task))?.reversed().flatMap(\.steps).first { $0.title == step.title }
    }

    /// Appends to the existing checklist format; the receipt and all steps share one task write.
    static func appendApprovedSteps(_ steps: [ConversationSubtaskDraft], proposalID: UUID,
                                    to task: AcademicTask) throws {
        guard !(try approvalReceipts(in: task)).contains(where: { $0.proposalID == proposalID }) else {
            throw TaskStepApprovalError.alreadyApplied
        }
        let existing = Set(subtasks(from: task).map { normalizedStepTitle($0.title) })
        var titles = existing
        var approved = steps
        guard !approved.isEmpty, approved.count <= 20 else { throw TaskStepApprovalError.invalidSteps }
        for index in approved.indices {
            let title = approved[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 500, !title.contains(where: { $0.isNewline }),
                  titles.insert(normalizedStepTitle(title)).inserted else { throw TaskStepApprovalError.invalidSteps }
            approved[index].title = title
            approved[index].estimatedMinutes = nil
        }
        let receipt = TaskStepApprovalReceipt(proposalID: proposalID, steps: approved)
        let data = try JSONEncoder().encode(receipt)
        let checklist = approved.map { "- [\($0.isCompleted == true ? "x" : " ")] \($0.title)" }.joined(separator: "\n")
        task.taskDescription += (task.taskDescription.isEmpty ? "" : "\n") + checklist + "\n" + approvalMarker + String(decoding: data, as: UTF8.self)
        task.updatedAt = .now
    }

    static func replaceReviewedSteps(_ steps: [ConversationSubtaskDraft], proposalID: UUID, in task: AcademicTask) throws {
        // Preserve the brief, manual notes and every durable receipt. Only reviewed checklist lines change.
        let before = task.taskDescription
        task.taskDescription = before.components(separatedBy: .newlines).filter {
            let line = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return !line.hasPrefix("- [ ]") && !line.hasPrefix("- [x]")
        }.joined(separator: "\n")
        do { try appendApprovedSteps(steps, proposalID: proposalID, to: task) }
        catch { task.taskDescription = before; throw error }
    }

    private static func normalizedStepTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

@MainActor
enum TaskStepApprovalService {
    /// A short-lived context isolates failure/rollback from working notes and other unsaved UI edits.
    /// No suspension occurs between checking the receipt and committing it.
    static func apply(proposalID: UUID, steps: [ConversationSubtaskDraft], snapshot: TaskStepReviewSnapshot,
                      selectedTask: AcademicTask, context: ModelContext,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let transaction = ModelContext(context.container)
        transaction.autosaveEnabled = false
        let taskID = selectedTask.id
        let descriptor = FetchDescriptor<AcademicTask>(predicate: #Predicate { $0.id == taskID })
        guard let stored = try transaction.fetch(descriptor).first, !selectedTask.isDeleted else {
            throw TaskStepApprovalError.missingTask
        }
        guard !(try TaskStructureService.approvalReceipts(in: stored)).contains(where: { $0.proposalID == proposalID }) else {
            throw TaskStepApprovalError.alreadyApplied
        }
        guard TaskStepReviewSnapshot(stored) == snapshot, TaskStepReviewSnapshot(selectedTask) == snapshot else {
            throw TaskStepApprovalError.changedTask
        }
        do {
            try TaskStructureService.appendApprovedSteps(steps, proposalID: proposalID, to: stored)
            try save(transaction)
        } catch { transaction.rollback(); throw error }
        // Update the existing observable object so Today, To-do and task detail refresh immediately.
        selectedTask.taskDescription = stored.taskDescription
        selectedTask.updatedAt = stored.updatedAt
    }

    static func refresh(_ selectedTask: AcademicTask, context: ModelContext) throws -> TaskStepReviewSnapshot {
        guard !context.changedModelsArray.contains(where: { $0.persistentModelID == selectedTask.persistentModelID }) else {
            throw TaskStepApprovalError.unsavedTaskEdits
        }
        let read = ModelContext(context.container)
        let id = selectedTask.id
        guard let stored = try read.fetch(FetchDescriptor<AcademicTask>(predicate: #Predicate { $0.id == id })).first,
              !selectedTask.isDeleted else { throw TaskStepApprovalError.missingTask }
        selectedTask.title = stored.title; selectedTask.taskDescription = stored.taskDescription
        selectedTask.dueDate = stored.dueDate; selectedTask.status = stored.status
        selectedTask.priority = stored.priority; selectedTask.estimatedDuration = stored.estimatedDuration
        selectedTask.course = stored.course.flatMap { context.model(for: $0.persistentModelID) as? Course }
        selectedTask.chapter = stored.chapter.flatMap { context.model(for: $0.persistentModelID) as? Chapter }
        selectedTask.session = stored.session.flatMap { context.model(for: $0.persistentModelID) as? ClassSession }
        selectedTask.updatedAt = stored.updatedAt
        return TaskStepReviewSnapshot(stored)
    }
}
