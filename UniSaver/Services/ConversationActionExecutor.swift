import Foundation
import SwiftData

struct ConversationCreationReceipt: Codable, Hashable {
    var taskIDs: [UUID]
    var createdAt: Date
}

/// One executor for Today, the global popup and native tool proposals. Only validated, approved drafts enter here.
@MainActor
enum ConversationActionExecutor {
    static func apply(_ proposal: ConversationAnalysisProposal, state: inout TodayConversationState,
                      note: StudyNote, context: ModelContext) throws -> String {
        if proposal.actions.contains(where: { $0.kind == .importQuestionBank }) {
            guard proposal.actions.count == 1, let action = proposal.actions.first, action.canApply else {
                throw AIRevisionError.providerError("Review question-bank imports separately from task and schedule changes.")
            }
            if (state.appliedProposalIDs ?? []).contains(proposal.id) { return "This proposal was already imported." }
            let parsed: [ParsedQuizQuestion]
            if let json = action.questionBankDraftJSON {
                parsed = try JSONDecoder().decode([ParsedQuizQuestion].self, from: Data(json.utf8))
            } else { parsed = QuizBulkParser.parse(action.sourceText) }
            guard action.selectedCourseID != nil, action.selectedChapterID != nil else {
                throw AIRevisionError.providerError("Choose a course and chapter before importing.")
            }
            let id = try QuestionBankImportService.save(parsed, title: action.title, mode: .practice,
                courseID: action.selectedCourseID, chapterID: action.selectedChapterID,
                approvedAnswerChanges: Set(action.approvedAnswerChangeKeys ?? []), context: context)
            let quiz = try context.fetch(FetchDescriptor<Quiz>()).first { $0.id == id }
            let result = "Imported question bank: \(quiz?.questions.count ?? parsed.count) saved questions. Existing records and learning history were preserved."
            let previousState = state, previousBody = note.body
            state.appliedProposalIDs = Array(((state.appliedProposalIDs ?? []) + [proposal.id]).suffix(200))
            state.messages.append(TodayConversationMessage(role: .system, text: result))
            TodayConversationStore.save(state, into: note)
            do { try context.save() } catch { state = previousState; note.body = previousBody; throw error }
            return result
        }
        if proposal.actions.contains(where: { $0.isStructuredPlan == true }) {
            return try applyStructured(proposal, state: &state, note: note, context: context)
        }
        guard !(state.appliedProposalIDs ?? []).contains(proposal.id) else { return "This proposal was already applied." }
        let courses = try context.fetch(FetchDescriptor<Course>())
        var tasks = try context.fetch(FetchDescriptor<AcademicTask>())
        var blocks = try context.fetch(FetchDescriptor<StudyBlock>())
        let classSessions = try context.fetch(FetchDescriptor<ClassSession>())
        let exams = try context.fetch(FetchDescriptor<Exam>())
        let originalState = state, originalBody = note.body
        var insertedTasks: [AcademicTask] = [], insertedBlocks: [StudyBlock] = []
        var changed: [(AcademicTask, Date, AcademicTaskStatus, String, Date)] = []
        var skipped = 0
        var executionTasks: [AcademicTask] = []
        do {
            for action in proposal.actions where action.canApply {
                let course = courses.first { $0.id == action.selectedCourseID }
                switch action.kind {
                case .createTask, .flagCalendarConflict:
                    guard let course, !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let date = action.dueDate, date.timeIntervalSince1970.isFinite else {
                        throw AIRevisionError.providerError("Course or deadline missing. Review the proposed task.")
                    }
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: proposal.timeZoneIdentifier) ?? .current
                    if let duplicate = tasks.first(where: { $0.course?.id == course.id && normalized($0.title) == normalized(action.title) && calendar.isDate($0.dueDate, inSameDayAs: date) }) { skipped += 1; executionTasks.append(duplicate); continue }
                    let minutes = action.estimatedMinutes ?? 0
                    guard (0...1440).contains(minutes) else { throw AIRevisionError.providerError("Invalid task duration") }
                    let task = AcademicTask(title: action.title, taskDescription: merge("Source: \(action.sourceText)", action: action),
                        dueDate: date, estimatedDuration: TimeInterval(minutes * 60), course: course)
                    context.insert(task); tasks.append(task); insertedTasks.append(task); executionTasks.append(task)
                case .updateTask, .updateProgress, .addSubtasks:
                    guard let task = tasks.first(where: { $0.id == action.existingTaskID }) else { throw AIRevisionError.providerError("The selected task no longer exists.") }
                    changed.append((task, task.dueDate, task.status, task.taskDescription, task.updatedAt))
                    if let date = action.dueDate { task.dueDate = date }
                    if action.kind == .updateProgress {
                        if let before = action.beforeValue, before != task.status.rawValue { throw AIRevisionError.providerError("Progress has changed since this proposal. Review the task again.") }
                        guard let raw = action.afterValue, let status = AcademicTaskStatus(rawValue: raw), status != .cancelled else {
                            throw AIRevisionError.providerError("Review a valid progress state first.")
                        }
                        task.status = status
                    }
                    task.taskDescription = merge(task.taskDescription, action: action)
                    task.updatedAt = .now
                case .importQuestionBank:
                    throw AIRevisionError.providerError("Open the question-bank import preview first.")
                case .rescheduleWorkSessions:
                    throw AIRevisionError.providerError("Moving an existing session is not supported by this proposal. Review it in Planner.")
                case .proposeWorkSessions:
                    let linkedTask = tasks.first { $0.id == action.existingTaskID }
                    for session in action.sessions where session.isSelected {
                        guard session.endDate > session.startDate, session.endDate.timeIntervalSince(session.startDate) <= 4 * 3600 else { throw AIRevisionError.providerError("Invalid study interval") }
                        if blocks.contains(where: { $0.status != .cancelled && $0.startDate < session.endDate && session.startDate < $0.endDate }) {
                            throw AIRevisionError.providerError("The proposed session overlaps an existing study block. Review it in Planner.")
                        }
                        if classSessions.contains(where: { $0.startTime < session.endDate && session.startDate < $0.endTime }) ||
                           exams.contains(where: { ($0.startTime ?? $0.date) < session.endDate && session.startDate < ($0.endTime ?? $0.date.addingTimeInterval(3600)) }) {
                            throw AIRevisionError.providerError("This interval may conflict with a class or exam. Review it in Planner.")
                        }
                        let block = StudyBlock(title: session.title, startDate: session.startDate, endDate: session.endDate, course: course ?? linkedTask?.course, task: linkedTask)
                        context.insert(block); blocks.append(block); insertedBlocks.append(block)
                    }
                }
            }
            state.lastExecutionTaskIDs = executionTasks.map(\.id)
            state.appliedProposalIDs = Array(((state.appliedProposalIDs ?? []) + [proposal.id]).suffix(200))
            if !insertedTasks.isEmpty { state.creationReceipt = ConversationCreationReceipt(taskIDs: insertedTasks.map(\.id), createdAt: .now) }
            let titles = insertedTasks.map(\.title).joined(separator: "; ")
            let result = "Saved: \(insertedTasks.count) task(s)\(titles.isEmpty ? "" : " — " + titles), \(changed.count) update(s), \(insertedBlocks.count) study session(s). \(skipped) duplicate(s) skipped."
            let receiptData: [[String: Any]] = executionTasks.map { ["status": "saved", "task_id": $0.id.uuidString, "title": $0.title, "course_id": $0.course?.id.uuidString ?? ""] }
            if let data = try? JSONSerialization.data(withJSONObject: receiptData, options: .sortedKeys) {
                state.toolResults = Array(((state.toolResults ?? []) + ["Validated execution: " + String(decoding: data, as: UTF8.self)]).suffix(12))
            }
            state.messages.append(TodayConversationMessage(role: .system, text: result))
            TodayConversationStore.save(state, into: note)
            try context.save()
            return result
        } catch {
            for task in insertedTasks { context.delete(task) }
            for block in insertedBlocks { context.delete(block) }
            for (task, date, status, description, updated) in changed.reversed() {
                task.dueDate = date; task.status = status; task.taskDescription = description; task.updatedAt = updated
            }
            state = originalState; note.body = originalBody
            throw error
        }
    }

    static func undoCreation(state: inout TodayConversationState, note: StudyNote, context: ModelContext) throws {
        guard let receipt = state.creationReceipt else { return }
        let tasks = try context.fetch(FetchDescriptor<AcademicTask>()).filter { receipt.taskIDs.contains($0.id) }
        guard tasks.allSatisfy({ $0.status == .todo && $0.updatedAt <= receipt.createdAt && $0.session == nil }),
              try context.fetch(FetchDescriptor<StudyBlock>()).allSatisfy({ !receipt.taskIDs.contains($0.task?.id ?? UUID()) }) else {
            throw AIRevisionError.providerError("This task has changed since creation. Review it in Tasks before deleting it.")
        }
        // Save deletion first. Receipt remains available on a failed save.
        for task in tasks { context.delete(task) }
        do { try context.save() } catch { context.rollback(); throw error }
        state.creationReceipt = nil
        state.messages.append(TodayConversationMessage(role: .system, text: "Task creation undone."))
        TodayConversationStore.save(state, into: note)
        try context.save()
    }

    static func permitsImmediateCreation(_ message: String) -> Bool {
        let text = normalized(message)
        // Conservative explicit imperative only. Advice and ambiguous requests stay in review.
        return ["add a task ", "create a task ", "ajoute une tache ", "cree une tache "].contains { text.hasPrefix($0) }
    }

    static func permitsImmediateCreation(_ message: String, proposal: ConversationAnalysisProposal, courses: [Course], selectedCourseID: UUID?) -> Bool {
        guard permitsImmediateCreation(message), proposal.actions.count == 1, let action = proposal.actions.first,
              action.kind == .createTask, action.canApply, let due = action.dueDate,
              let course = courses.first(where: { $0.id == action.selectedCourseID }) else { return false }
        let text = normalized(message)
        guard text.contains(normalized(action.title)),
              text.contains(normalized(course.name)) || selectedCourseID == course.id else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: proposal.timeZoneIdentifier) ?? .current
        let expected: Date?
        if text.contains("tomorrow") || text.contains("demain") { expected = calendar.date(byAdding: .day, value: 1, to: proposal.referenceDate) }
        else if text.contains("today") || text.contains("aujourd'hui") { expected = proposal.referenceDate }
        else {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
            expected = text.contains(formatter.string(from: due)) ? due : nil
        }
        guard let expected, calendar.isDate(expected, inSameDayAs: due) else { return false }
        let minutes = action.estimatedMinutes ?? 0
        return minutes == 0 || text.contains("\(minutes) min")
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func merge(_ existing: String, action: ConversationActionDraft) -> String {
        var text = existing
        let known = Set(existing.components(separatedBy: .newlines).map { normalized($0.replacingOccurrences(of: "- [ ] ", with: "").replacingOccurrences(of: "- [x] ", with: "")) })
        for step in action.subtasks where step.isSelected && !known.contains(normalized(step.title)) {
            text += "\n- [ ] \(step.title)"
        }
        return text
    }
}


extension ConversationActionExecutor {
    /// Reviewed plans use an isolated atomic transaction, including their durable conversation receipt.
    static func applyStructured(_ proposal: ConversationAnalysisProposal, state: inout TodayConversationState,
                                note: StudyNote, context: ModelContext,
                                save: (ModelContext) throws -> Void = { try $0.save() }) throws -> String {
        guard proposal.actions.allSatisfy({ $0.isStructuredPlan == true }) else {
            throw AIRevisionError.providerError("Mixed plan actions must be reviewed separately.")
        }
        let transaction = ModelContext(context.container)
        transaction.autosaveEnabled = false
        let noteID = note.id
        guard let savedNote = try transaction.fetch(FetchDescriptor<StudyNote>(predicate: #Predicate { $0.id == noteID })).first else {
            throw AIRevisionError.providerError("Save the conversation before applying this plan. Your proposal is kept.")
        }
        let persisted = TodayConversationStore.decode(savedNote)
        guard !(persisted.appliedProposalIDs ?? []).contains(proposal.id) else {
            state = persisted
            return "This proposal was already applied. No records were duplicated."
        }
        guard !(persisted.supersededProposalIDs ?? []).contains(proposal.id) else {
            throw AIRevisionError.providerError("A newer review replaced this proposal. Open the latest plan before saving.")
        }
        guard let receiptID = UUID(uuidString: proposal.id) else { throw AIRevisionError.providerError("Invalid plan receipt.") }
        let selected = proposal.actions.filter(\.isSelected)
        guard !selected.isEmpty, selected.allSatisfy(\.canApply) else {
            throw AIRevisionError.providerError("Resolve the selected associations and missing details before saving.")
        }
        let courses = try transaction.fetch(FetchDescriptor<Course>())
        var tasks = try transaction.fetch(FetchDescriptor<AcademicTask>())
        var execution: [AcademicTask] = []
        var created = 0, changed = 0, duplicates = 0
        var next = state
        do {
            for action in selected {
                let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 500, !title.contains(where: { $0.isNewline }) else {
                    throw AIRevisionError.providerError("Every parent title must be nonempty single-line text.")
                }
                let course = courses.first { $0.id == action.selectedCourseID }
                guard action.selectedCourseID == nil || course != nil else { throw AIRevisionError.providerError("The selected course no longer exists.") }
                guard action.estimatedMinutes == nil || action.estimatedMinutes == 0 else { throw AIRevisionError.providerError("This plan does not support generated duration estimates.") }
                if let date = action.dueDate, !date.timeIntervalSince1970.isFinite { throw AIRevisionError.providerError("Invalid date.") }
                let approved = action.subtasks.filter(\.isSelected)
                let task: AcademicTask
                switch action.kind {
                case .createTask:
                    let date = action.dueDate ?? .distantFuture
                    if let duplicate = tasks.first(where: {
                        normalized($0.title) == normalized(title) && $0.course?.id == course?.id && $0.dueDate == date
                    }) {
                        execution.append(duplicate); duplicates += 1; continue
                    }
                    task = AcademicTask(title: title, taskDescription: planDescription(action), dueDate: date,
                        estimatedDuration: 0, course: course)
                    transaction.insert(task); tasks.append(task); created += 1
                    if !approved.isEmpty { try TaskStructureService.appendApprovedSteps(approved, proposalID: receiptID, to: task) }
                case .addSubtasks, .updateTask:
                    guard let existing = tasks.first(where: { $0.id == action.existingTaskID }), let snapshot = action.planSnapshot else {
                        throw AIRevisionError.providerError("The selected existing task no longer exists or needs a fresh review.")
                    }
                    guard TaskStepReviewSnapshot(existing) == snapshot else {
                        throw AIRevisionError.providerError("The saved plan changed during review. Ask the agent to update it again; your proposal is retained.")
                    }
                    let local = try context.fetch(FetchDescriptor<AcademicTask>()).first { $0.id == existing.id }
                    guard local.map(TaskStepReviewSnapshot.init) == snapshot else {
                        throw AIRevisionError.providerError("The task has unsaved or changed edits. Save them and review a refreshed proposal.")
                    }
                    guard !(try TaskStructureService.approvalReceipts(in: existing)).contains(where: { $0.proposalID == receiptID }) else {
                        execution.append(existing); duplicates += 1; continue
                    }
                    task = existing
                    if action.replacesSubtasks == true {
                        guard !approved.isEmpty else { throw AIRevisionError.providerError("Keep at least one reviewed step in a revised plan.") }
                        try TaskStructureService.replaceReviewedSteps(approved, proposalID: receiptID, in: task)
                        task.title = title
                    } else {
                        try TaskStructureService.appendApprovedSteps(approved, proposalID: receiptID, to: task)
                    }
                    if let date = action.dueDate { task.dueDate = date }
                    task.course = course
                    task.taskDescription += "\n" + planDescription(action)
                    task.updatedAt = .now
                    changed += 1
                default: throw AIRevisionError.providerError("Only reviewed task creation and checklist changes are supported in this plan.")
                }
                execution.append(task)
            }
            var seenIDs = Set<UUID>()
            let ids = execution.map(\.id).filter { seenIDs.insert($0).inserted }
            next.lastExecutionTaskIDs = ids
            next.appliedProposalIDs = Array(Set((persisted.appliedProposalIDs ?? []) + (state.appliedProposalIDs ?? []) + [proposal.id]))
            var applied = proposal
            applied.executionTaskIDs = ids
            next.pendingProposals[proposal.id] = applied
            next.creationReceipt = nil // Undo for legacy single-task creation must not delete a reviewed plan.
            let result = "Saved: \(created) parent task(s), \(changed) existing plan update(s). \(duplicates) duplicate(s) skipped. Open the resulting plan to start its first incomplete step."
            next.messages.append(TodayConversationMessage(role: .system, text: result))
            next.toolResults = Array(((next.toolResults ?? []) + ["Validated saved plan IDs: " + execution.map { $0.id.uuidString }.joined(separator: ", ")]).suffix(12))
            TodayConversationStore.save(next, into: savedNote)
            try save(transaction)
            note.body = savedNote.body; note.updatedAt = savedNote.updatedAt
            for saved in execution {
                if let local = try? context.fetch(FetchDescriptor<AcademicTask>()).first(where: { $0.id == saved.id }) {
                    local.title = saved.title; local.taskDescription = saved.taskDescription
                    local.dueDate = saved.dueDate; local.updatedAt = saved.updatedAt
                    local.course = saved.course.flatMap { context.model(for: $0.persistentModelID) as? Course }
                }
            }
            state = next
            return result
        } catch { transaction.rollback(); throw error }
    }

    private static func planDescription(_ action: ConversationActionDraft) -> String {
        func paragraph(_ label: String, _ value: String?) -> String {
            guard let value, !value.isEmpty else { return "" }
            return value.components(separatedBy: .newlines).map { label + ": " + $0 }.joined(separator: "\n")
        }
        return [paragraph("Reviewed outcome", action.planOutcome),
            paragraph("Reviewed completion criterion", action.completionCriterion),
            paragraph("Evidence", action.evidence.title), paragraph("Source content", action.sourceExcerpt),
            paragraph("Scope constraint", action.planConstraints?.joined(separator: "\n")),
            paragraph("Missing detail", action.planMissingDetails?.joined(separator: "\n")),
            paragraph("Suggested dependencies", action.dependencies?.joined(separator: "; "))]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
