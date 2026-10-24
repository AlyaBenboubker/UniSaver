import Foundation
import PDFKit

/// Local extension of the existing execution ledger; no new SwiftData schema.
struct TaskWorkspaceDraft: Codable, Hashable {
    var taskID: UUID
    var pastedInstructions: String?
    var activeStepID: String?
    var accountID: String?
    var sessionID = UUID()
    var startedAt = Date()
    var initialEstimatedSeconds: TimeInterval = 0
    var notes = ""
    var remainingWork = ""
    var resourceIDs: [UUID] = []
    var links: [String] = []
    var messages: [TodayConversationMessage] = []
    var questionDraft = ""
    var shareNotes = false
    var helpRequests = 0
    var planCorrections = 0
    var lastSavedAt = Date()
}

enum TaskWorkspaceService {
    static func assignment(for task: AcademicTask, notes: [StudyNote]) -> AssignmentPlanProject? {
        notes.filter { AssignmentPlanStore.isAssignmentPlan($0) }.map { AssignmentPlanStore.decode($0) }
            .first { $0.milestones.contains { $0.createdTaskID == task.id } }
    }

    static func draft(for task: AcademicTask, ledger: TaskExecutionLedger, notes: [StudyNote]) -> TaskWorkspaceDraft {
        if let existing = ledger.workspaces?.first(where: { $0.taskID == task.id }) { return existing }
        var draft = TaskWorkspaceDraft(taskID: task.id, initialEstimatedSeconds: task.estimatedDuration)
        if let sourceID = assignment(for: task, notes: notes)?.sourceResourceID { draft.resourceIDs = [sourceID] }
        return draft
    }

    static func upsert(_ draft: TaskWorkspaceDraft, into ledger: inout TaskExecutionLedger) {
        var drafts = ledger.workspaces ?? []
        drafts.removeAll { $0.taskID == draft.taskID }
        drafts.append(draft)
        ledger.workspaces = drafts
    }

    static func append(_ record: TaskExecutionRecord, into ledger: inout TaskExecutionLedger) {
        guard !ledger.records.contains(where: { $0.id == record.id }) else { return }
        ledger.records.append(record)
    }

    static func sources(resources: [AcademicResource], fileStore: AcademicFileStore = AcademicFileStore(), query: String = "") throws -> [AIRevisionSource] {
        try resources.prefix(4).map { resource in
            let url = try fileStore.url(for: resource.storedRelativePath)
            let text: String
            if resource.resourceKind == .pdf {
                guard let document = PDFDocument(url: url) else { throw AcademicFileStoreError.sourceUnavailable }
                guard document.pageCount <= 500 else { throw AIRevisionError.providerError("Document exceeds 500 pages. Share a specific excerpt or smaller document.") }
                let passages = (0..<document.pageCount).compactMap { index -> (Int, String)? in
                    let content = (document.page(at: index)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return content.isEmpty ? nil : (index, "[p.\(index + 1)] \(content)")
                }
                guard !passages.isEmpty else { throw AIRevisionError.providerError("No readable PDF text. Share a passage; scanned pages require OCR, which is not available here.") }
                text = retrievedText(passages, query: query)
            } else if ["txt", "md", "csv"].contains(resource.fileExtension.lowercased()) {
                guard resource.fileSize <= 1_000_000 else { throw AIRevisionError.providerError("Text file too large; select a smaller excerpt.") }
                let content = try String(contentsOf: url, encoding: .utf8)
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIRevisionError.providerError("This file contains no readable text.") }
                if QuestionBankAgentSource.authorizesImport(query), let bank = QuestionBankAgentSource.extract(content) {
                    // An original bank must be imported in full, not from ranked snippets.
                    text = bank.bank
                } else {
                    let sections = content.components(separatedBy: "\n\n").enumerated().map { ($0.offset, "[section \($0.offset + 1)] \($0.element)") }
                    text = retrievedText(sections, query: query)
                }
            } else {
                throw AIRevisionError.providerError("\(resource.title): text is unavailable. Paste an excerpt; images and external applications are not read by the agent.")
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIRevisionError.providerError("\(resource.title): no readable text. Paste an excerpt in your shared notes.")
            }
            return AIRevisionSource(id: resource.id.uuidString, title: resource.title, kind: .resource,
                                    detail: resource.originalFileName, text: text, sourceReference: resource.originalFileName)
        }
    }

    /// Searches every supported page/section, sends ranked excerpts with stable references and explicit coverage.
    static func retrievedText(_ sections: [(Int, String)], query: String) -> String {
        let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 2 }
        let ranked = sections.sorted { a, b in
            let sa = terms.filter { a.1.lowercased().contains($0) }.count
            let sb = terms.filter { b.1.lowercased().contains($0) }.count
            return sa == sb ? a.0 < b.0 : sa > sb
        }
        var budget = 12000
        var chosen: [(Int, String)] = []
        for section in ranked.prefix(6) where budget > 0 {
            let excerpt = String(section.1.prefix(min(4000, budget)))
            chosen.append((section.0, excerpt + (excerpt.count < section.1.count ? "\n[Excerpt; remainder of this section not sent.]" : "")))
            budget -= excerpt.count
        }
        return chosen.sorted { $0.0 < $1.0 }.map { $0.1 }.joined(separator: "\n\n") + "\n[Retrieved \(chosen.count) of \(sections.count) readable pages/sections for this request; other sections not sent.]"
    }

    static func context(task: AcademicTask, draft: TaskWorkspaceDraft, assignment: AssignmentPlanProject?) -> String {
        let steps = TaskStructureService.subtasks(from: task)
        let current = steps.first { $0.id == draft.activeStepID }?.title ?? steps.first { !$0.isCompleted }?.title ?? task.title
        let requirements = assignment?.allRequirements.map {
            "\($0.detail) [\($0.sourceReference)] — excerpt: \($0.supportingText)"
        }.joined(separator: "\n") ?? "No reviewed assignment rubric attached."
        return """
        Current date: \(Date().formatted()); timezone: \(TimeZone.current.identifier)
        Selected task ID: \(task.id.uuidString); course ID: \(task.course?.id.uuidString ?? "none")
        Selected task: \(task.title)
        Deadline: \(TaskStructureService.deadlineLabel(for: task)); status: \(task.status.rawValue)
        Current step: \(current)
        Task description and finish condition: \(task.taskDescription.prefix(4000))
        Completed steps: \(steps.filter(\.isCompleted).map(\.title).joined(separator: "; "))
        Reviewed requirements (student corrections take precedence): \(requirements.prefix(6000))
        Original brief excerpt: \((assignment?.extractedText ?? "").prefix(6000))
        Explicitly pasted instructions: \((draft.pastedInstructions ?? "").prefix(6000))
        Remaining work: \(draft.remainingWork.prefix(2000))
        Student draft: \(draft.shareNotes ? String(draft.notes.prefix(6000)) : "Not shared")
        External links are references only; their contents have not been fetched.
        """
    }
}
