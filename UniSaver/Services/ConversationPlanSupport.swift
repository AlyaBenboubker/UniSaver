import Foundation

/// The student's command is kept separate from the quoted/pasted content passed to the provider.
struct ConversationPlanningRequest {
    enum Intent: String { case conversation, unspecified, summarise, explain, createTasks, addSubtasks, updatePlan }
    let intent: Intent
    let request: String
    let source: String
    var permitsPlan: Bool { [.createTasks, .addSubtasks, .updatePlan].contains(intent) }

    static func classify(_ text: String, hasPlan: Bool) -> Self {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = clean.components(separatedBy: .newlines)
        func intent(_ command: String) -> Intent? {
            let lower = command.lowercased()
            if ["summarise", "summarize", "résume", "resume this"].contains(where: lower.hasPrefix) { return .summarise }
            if ["explain", "explique"].contains(where: lower.hasPrefix) { return .explain }
            if ["turn this into tasks", "turn into tasks", "create tasks", "add this please", "organise this as tasks", "organize this as tasks", "transforme", "make a plan from", "make tasks from"].contains(where: lower.hasPrefix) { return .createTasks }
            if ["add subtasks", "add steps", "add this to my", "break this", "break into steps"].contains(where: lower.hasPrefix) { return .addSubtasks }
            if ["update my plan", "update this plan", "make the steps smaller", "only keep the essential", "move this step", "move the", "i've already done", "i have already done", "mark the first", "make these steps"].contains(where: lower.hasPrefix) { return .updatePlan }
            return nil
        }
        let first = lines.first ?? clean
        if let separator = first.firstIndex(of: ":"), let chosen = intent(String(first[..<separator])) {
            let command = String(first[..<separator])
            let content = ([String(first[first.index(after: separator)...])] + Array(lines.dropFirst())).joined(separator: "\n")
            return Self(intent: chosen, request: command, source: content.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let chosen = intent(first), first.count < 400 {
            var source = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if source.lowercased().hasPrefix("source text:") { source = String(source.dropFirst("source text:".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            return Self(intent: chosen, request: first, source: source)
        }
        if lines.count > 1, let last = lines.last, last.count < 200, let chosen = intent(last) {
            return Self(intent: chosen, request: last, source: lines.dropLast().joined(separator: "\n"))
        }
        if hasPlan, ["smaller", "essential", "before", "already done", "existing project"].contains(where: clean.lowercased().contains), clean.count < 400 {
            return Self(intent: .updatePlan, request: clean, source: "")
        }
        let pasted = lines.count > 2 || clean.count > 500
        return Self(intent: pasted ? .unspecified : .conversation, request: pasted ? "" : clean, source: pasted ? clean : "")
    }

    static func taskCommand(for text: String) -> String {
        "Turn this into tasks.\n\nSource text:\n" + text
    }
}

/// Wire data is decoded into the existing action drafts; the provider never receives persistence access.
enum ConversationPlanDecoder {
    struct Requirement: Codable { var text: String; var sourceExcerpt: String }
    struct Plan: Codable {
        var title: String
        var outcome: String
        var constraints: [Requirement]
        var missingInformation: [String]
        var parents: [Parent]
    }
    struct Parent: Codable {
        var title: String
        var operation: String // create, append, revise
        var courseID: String?
        var existingTaskID: String?
        var completionCriterion: String
        var sourceExcerpt: String?
        var evidence: String
        var dueDate: String?
        var dateExcerpt: String?
        var dependencies: [String]
        var steps: [Step]
    }
    struct Step: Codable {
        var title: String
        var completionCriterion: String
        var sourceExcerpt: String?
        var evidence: String
        var dependencies: [String]
        var completed: Bool?
    }

    @MainActor static func actions(from json: String, source: String, request: ConversationPlanningRequest,
                                  previous: ConversationAnalysisProposal?, courses: [Course], tasks: [AcademicTask],
                                  parseDate: (String) -> Date?, selectedTaskID: UUID? = nil) throws -> [ConversationActionDraft] {
        guard request.permitsPlan else { throw AIRevisionError.providerError("This request does not authorize a task proposal.") }
        guard json.utf8.count <= 100000 else { throw AIRevisionError.providerError("The plan response is too large. Try a smaller brief.") }
        try validateShape(json)
        let plan: Plan
        do { plan = try JSONDecoder().decode(Plan.self, from: Data(json.utf8)) }
        catch { throw AIRevisionError.providerError("Invalid structured plan. Your source text is kept; retry the request.") }
        guard !plan.title.isEmpty, !plan.outcome.isEmpty, (1...12).contains(plan.parents.count), plan.constraints.count <= 20,
              plan.missingInformation.count <= 20 else { throw AIRevisionError.providerError("Invalid plan size or outcome.") }
        let previousSource = previous?.originalMessage ?? ""
        let savedSource = tasks.filter { task in plan.parents.contains { $0.existingTaskID == task.id.uuidString } }
            .map { task in
                TaskStructureService.visibleDescription(task.taskDescription) + "\n" + ((try? TaskStructureService.approvalReceipts(in: task))?.flatMap(\.steps).compactMap(\.sourceExcerpt).joined(separator: "\n") ?? "")
            }.joined(separator: "\n")
        let evidenceContent = [source, previousSource, savedSource].joined(separator: "\n")
        for constraint in plan.constraints {
            guard !constraint.text.isEmpty, !constraint.sourceExcerpt.isEmpty, evidenceContent.contains(constraint.sourceExcerpt) else {
                throw AIRevisionError.providerError("A scope constraint has no matching source excerpt.")
            }
        }
        var seenParents = Set<String>()
        return try plan.parents.enumerated().map { index, parent in
            let title = try validTitle(parent.title)
            guard seenParents.insert(parent.existingTaskID ?? title.lowercased()).inserted,
                  ["create", "append", "revise"].contains(parent.operation), parent.steps.count <= 20 else {
                throw AIRevisionError.providerError("Duplicate parent or invalid plan operation.")
            }
            guard parent.operation != "revise" || request.intent == .updatePlan else {
                throw AIRevisionError.providerError("Only an explicit request to update a plan can propose replacing its checklist.")
            }
            let task: AcademicTask?
            if let id = parent.existingTaskID, !id.isEmpty {
                guard let match = tasks.first(where: { $0.id.uuidString == id }) else { throw AIRevisionError.providerError("Unknown existing task. Resolve the association first.") }
                task = match
            } else { task = nil }
            guard parent.operation == "create" ? task == nil : task != nil else {
                throw AIRevisionError.providerError("An existing task must be identified before updating a plan.")
            }
            let course: Course?
            if let id = parent.courseID, !id.isEmpty {
                guard let known = courses.first(where: { $0.id.uuidString == id }) else { throw AIRevisionError.providerError("Unknown course association.") }
                course = known
            } else { course = task?.course }
            let evidence = try validateEvidence(parent.evidence, excerpt: parent.sourceExcerpt, content: evidenceContent)
            guard !parent.completionCriterion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIRevisionError.providerError("A parent completion criterion is missing.") }
            var due: Date?
            if let day = parent.dueDate, !day.isEmpty {
                guard let excerpt = parent.dateExcerpt, evidenceContent.contains(excerpt),
                      dateIsGrounded(day, excerpt: excerpt), let parsed = parseDate(day) else {
                    throw AIRevisionError.providerError("A proposed date is not supported by the pasted source. Leave unknown dates empty.")
                }
                due = parsed
            }
            var seenSteps = Set<String>()
            let steps = try parent.steps.map { item -> ConversationSubtaskDraft in
                let title = try validTitle(item.title)
                guard seenSteps.insert(title.lowercased()).inserted, !item.completionCriterion.isEmpty else {
                    throw AIRevisionError.providerError("Step titles must be unique and have completion criteria.")
                }
                let evidence = try validateEvidence(item.evidence, excerpt: item.sourceExcerpt, content: evidenceContent)
                let knownCompleted = task.map { TaskStructureService.subtasks(from: $0).contains { $0.title == title && $0.isCompleted } } ?? false
                let requestedCompletion = ["already done", "already completed", "mark", "finished", "completed", "déjà fait"].contains(where: request.request.lowercased().contains)
                let firstPartRequested = ["first part", "first step"].contains(where: request.request.lowercased().contains)
                if item.completed == true, !knownCompleted, firstPartRequested {
                    let first = task.flatMap { TaskStructureService.subtasks(from: $0).first { !$0.isCompleted }?.title } ??
                        previous?.actions.first?.subtasks.first { $0.isCompleted != true }?.title
                    guard title == first else { throw AIRevisionError.providerError("Only the first incomplete step was reported done. Review that step without inventing other completion.") }
                }
                guard item.completed != true || knownCompleted || requestedCompletion else {
                    throw AIRevisionError.providerError("Completion cannot be inferred from assignment content.")
                }
                return ConversationSubtaskDraft(title: title, estimatedMinutes: nil, completionCriterion: item.completionCriterion,
                    sourceExcerpt: item.sourceExcerpt, dependencies: item.dependencies,
                    isCompleted: knownCompleted || item.completed == true, evidence: evidence)
            }
            let matchingCourses = courses.filter { candidate in
                candidate.name.caseInsensitiveCompare(course?.name ?? "") == .orderedSame ||
                (!candidate.name.isEmpty && (parent.sourceExcerpt ?? source).localizedCaseInsensitiveContains(candidate.name))
            }
            let ambiguousCourse = matchingCourses.count > 1
            let ambiguousTask = task.map { selected in
                let duplicateNames = tasks.filter { $0.title.caseInsensitiveCompare(selected.title) == .orderedSame }.count > 1
                let anchored = selectedTaskID == selected.id || (previous?.executionTaskIDs ?? []).contains(selected.id) ||
                    previous?.actions.contains(where: { $0.existingTaskID == selected.id }) == true ||
                    request.request.localizedCaseInsensitiveContains(selected.title) || source.localizedCaseInsensitiveContains(selected.title)
                return duplicateNames || !anchored
            } ?? false
            var action = ConversationActionDraft(id: UUID().uuidString,
                kind: task == nil ? .createTask : (parent.operation == "revise" ? .updateTask : .addSubtasks),
                title: parent.operation == "append" ? (task?.title ?? title) : title, sourceText: source.isEmpty ? previousSource : source, evidence: evidence,
                selectedCourseID: ambiguousCourse ? nil : course?.id,
                courseCandidates: ambiguousCourse ? matchingCourses.map { ConversationCourseCandidate(id: $0.id, title: $0.name, reason: "Possible source association; choose explicitly") } : [],
                dueDate: due, estimatedMinutes: nil, existingTaskID: task?.id, existingTaskTitle: task?.title,
                subtasks: steps, fingerprint: "structured-plan-\(index)")
            action.isStructuredPlan = true
            action.completionCriterion = parent.completionCriterion
            action.sourceExcerpt = parent.sourceExcerpt
            action.planOutcome = plan.outcome
            action.planConstraints = plan.constraints.map { "\($0.text)\nSource: \($0.sourceExcerpt)" }
            action.planMissingDetails = plan.missingInformation
            action.dependencies = parent.dependencies
            action.planSnapshot = task.map(TaskStepReviewSnapshot.init)
            action.replacesSubtasks = parent.operation == "revise"
            action.associationNeedsReview = ambiguousCourse || ambiguousTask
            return action
        }
    }

    private static func validateShape(_ json: String) throws {
        func keys(_ object: [String: Any], allowed: Set<String>) throws {
            guard Set(object.keys).isSubset(of: allowed) else { throw AIRevisionError.providerError("The plan contains unsupported fields. No changes were made.") }
        }
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw AIRevisionError.providerError("Invalid plan JSON.")
        }
        try keys(root, allowed: ["title", "outcome", "constraints", "missingInformation", "parents"])
        for constraint in root["constraints"] as? [[String: Any]] ?? [] {
            try keys(constraint, allowed: ["text", "sourceExcerpt"])
        }
        for parent in root["parents"] as? [[String: Any]] ?? [] {
            try keys(parent, allowed: ["title", "operation", "courseID", "existingTaskID", "completionCriterion", "sourceExcerpt", "evidence", "dueDate", "dateExcerpt", "dependencies", "steps"])
            for step in parent["steps"] as? [[String: Any]] ?? [] {
                try keys(step, allowed: ["title", "completionCriterion", "sourceExcerpt", "evidence", "dependencies", "completed"])
            }
        }
    }

    private static func validTitle(_ value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 500, !title.contains(where: { $0.isNewline }) else { throw AIRevisionError.providerError("Invalid plan title.") }
        return title
    }
    private static func validateEvidence(_ value: String, excerpt: String?, content: String) throws -> ConversationEvidenceState {
        guard ["explicit", "suggested"].contains(value),
              excerpt == nil || (!excerpt!.isEmpty && content.contains(excerpt!)),
              value != "explicit" || excerpt != nil else { throw AIRevisionError.providerError("A requirement has unsupported source evidence.") }
        return value == "explicit" ? .explicit : .suggested
    }
    private static func dateIsGrounded(_ day: String, excerpt: String) -> Bool {
        if excerpt.contains(day) { return true }
        // Only explicit month/day/year text; no inferred year or fabricated relative deadline.
        let normalized = excerpt.lowercased()
        let components = day.split(separator: "-")
        guard components.count == 3, let month = Int(components[1]), let date = Int(components[2]), (1...12).contains(month) else { return false }
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        return normalized.contains(String(components[0])) && normalized.contains(months[month - 1]) &&
            normalized.range(of: "\\b\(date)\\b", options: .regularExpression) != nil
    }
}
