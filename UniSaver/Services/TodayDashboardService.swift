import Foundation
import SwiftData

struct TodayDashboardSnapshot {
    let selectedDate: Date
    let workspace: AppWorkspace?
    let weeklyOverview: WeeklyOverview
    let sessions: [ClassSession]
    let studyBlocks: [StudyBlock]
    let timelineItems: [DashboardTimelineItem]
    let nextSession: ClassSession?
    let priorityTasks: [AcademicTask]
    let upcomingExam: Exam?
    let assignmentDue: AcademicTask?
    let courseProgress: [CourseProgressSummary]
    let flashcards: FlashcardsSummary
    let recentReading: ReadingProgress?
}

struct WeeklyOverview {
    let weekInterval: DateInterval
    let days: [WeeklyDashboardDay]
    let nextSession: ClassSession?
    let overdueTasks: [AcademicTask]
    let upcomingTasks: [AcademicTask]
    let dueFlashcards: [Flashcard]

    var hasEvents: Bool {
        days.contains { !$0.sessions.isEmpty || !$0.tasks.isEmpty || !$0.flashcards.isEmpty }
    }
}

struct WeeklyDashboardDay: Identifiable {
    let id: Date
    let date: Date
    let sessions: [ClassSession]
    let tasks: [AcademicTask]
    let flashcards: [Flashcard]
}

struct DashboardTimelineItem: Identifiable {
    enum Kind {
        case session(ClassSession)
        case studyBlock(StudyBlock)
    }

    let id: String
    let title: String
    let subtitle: String
    let startDate: Date
    let endDate: Date
    let colorIdentifier: String
    let status: String
    let kind: Kind
}

struct CourseProgressSummary: Identifiable {
    let id: UUID
    let course: Course
    let progress: Double
}

struct FlashcardsSummary {
    let dueCount: Int
    let courseCount: Int
    let lastActivity: Date?
    let isConfigured: Bool

    static let notConfigured = FlashcardsSummary(dueCount: 0, courseCount: 0, lastActivity: nil, isConfigured: false)
}

enum GamificationActivityType: String, Codable, CaseIterable {
    case taskCompletion
    case studyBlockCompletion
    case quizAttempt
    case flashcardPractice
    case exerciseAttempt

    var ruleXP: Int {
        switch self {
        case .taskCompletion: 20
        case .studyBlockCompletion: 15
        case .quizAttempt: 25
        case .flashcardPractice: 10
        case .exerciseAttempt: 25
        }
    }
}

struct RewardLedgerEvent: Codable, Identifiable, Hashable {
    var id: String
    var activityType: GamificationActivityType
    var sourceID: String
    var courseID: UUID?
    var occurredAt: Date
    var xp: Int
    var ruleVersion: Int
    var isActive: Bool
}

struct GamificationSettings: Codable, Hashable {
    var weeklyActiveDayGoal = 3
    var comebackAfterInactiveDays = 4
    var isGamificationHidden = false
    var reduceGamificationMotion = false
    var dismissedQuestIDs: [String] = []
    var postponedQuestIDs: [String: Date] = [:]
    var systemStartedAt: Date = .now
}

struct GamificationLedger: Codable, Hashable {
    var schemaVersion = 1
    var settings = GamificationSettings()
    var events: [RewardLedgerEvent] = []

    var activeEvents: [RewardLedgerEvent] {
        events.filter(\.isActive)
    }

    var totalXP: Int {
        activeEvents.reduce(0) { $0 + $1.xp }
    }
}

enum DailyQuestKind: String, Codable {
    case task
    case studyBlock
    case practice
    case comeback
}

struct DailyQuest: Identifiable, Hashable {
    var id: String
    var kind: DailyQuestKind
    var title: String
    var courseTitle: String
    var estimatedMinutes: Int?
    var reason: String
    var sourceID: String
    var courseID: UUID?
    var isComeback = false
}

struct WeeklyGamificationSummary {
    var completedMilestones: Int
    var totalMilestones: Int
    var label: String
    var activeDays: Int
    var activeDayGoal: Int
    var totalXP: Int
    var scopeNote: String?
    var isHidden: Bool
}

enum TaskCompletionProofLevel: String, Codable, CaseIterable, Identifiable {
    case selfReported
    case appRecorded
    case sourceConfirmed
    case supportingAttachment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selfReported: "Self-reported"
        case .appRecorded: "App-recorded"
        case .sourceConfirmed: "Source-confirmed"
        case .supportingAttachment: "Supporting attachment added"
        }
    }
}

enum WorkEvidenceAttachmentKind: String, Codable, CaseIterable {
    case file
    case screenshot
    case link
    case note
}

enum WorkEvidenceUploadState: String, Codable, CaseIterable {
    case localOnly
    case pendingUpload
    case uploaded
    case failed
}

struct WorkEvidenceAttachment: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: WorkEvidenceAttachmentKind
    var displayName: String
    var mimeType: String? = nil
    var storedRelativePath: String? = nil
    var urlString: String? = nil
    var note: String
    var fileSize: Int64? = nil
    var contentHash: String? = nil
    var uploadState: WorkEvidenceUploadState
    var createdAt = Date()
}

enum TaskBlockerReason: String, Codable, CaseIterable, Identifiable {
    case missingInstructions
    case dontUnderstand
    case waitingForSomeone
    case notEnoughTime
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .missingInstructions: "Missing instructions"
        case .dontUnderstand: "Don’t understand the content"
        case .waitingForSomeone: "Waiting for someone"
        case .notEnoughTime: "Not enough time"
        case .other: "Other"
        }
    }
}

enum TaskTimerMode: String, Codable, CaseIterable, Identifiable {
    case elapsed
    case countdown

    var id: String { rawValue }
}

struct TaskSubtaskItem: Identifiable, Hashable {
    var id: String
    var title: String
    var isCompleted: Bool
    var originalLine: String
}

struct ActiveTaskTimer: Codable, Hashable {
    var taskID: UUID
    var mode: TaskTimerMode
    var startedAt: Date
    var accumulatedSeconds: TimeInterval
    var pauseStartedAt: Date?
    var targetSeconds: TimeInterval?

    var isRunning: Bool {
        pauseStartedAt == nil
    }

    func elapsedSeconds(now: Date = .now) -> TimeInterval {
        guard pauseStartedAt == nil else { return accumulatedSeconds }
        return max(0, accumulatedSeconds + now.timeIntervalSince(startedAt))
    }

    func remainingSeconds(now: Date = .now) -> TimeInterval? {
        guard let targetSeconds else { return nil }
        return max(0, targetSeconds - elapsedSeconds(now: now))
    }
}

struct TaskExecutionRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var taskID: UUID
    var courseID: UUID?
    var startedAt: Date
    var endedAt: Date
    var recordedSeconds: TimeInterval?
    var completedSubtaskTitles: [String]
    var finishedTask: Bool
    var proofLevel: TaskCompletionProofLevel
    var blocker: TaskBlockerReason?
    var note: String
    var attachments: [WorkEvidenceAttachment] = []
    var remainingWork: String?
    var initialEstimatedSeconds: TimeInterval?
    var helpRequests: Int?
    var planCorrections: Int?
}

struct TaskExecutionLedger: Codable, Hashable {
    var schemaVersion = 1
    var activeTimer: ActiveTaskTimer?
    var records: [TaskExecutionRecord] = []
    var workspaces: [TaskWorkspaceDraft]?
}

enum TaskExecutionLedgerStore {
    static let marker = "UNISAVER_TASK_EXECUTION_LEDGER_V1:"

    static func ledgerNote(in notes: [StudyNote], context: ModelContext) -> StudyNote {
        // @Query may not yet include a note just inserted earlier in this run loop.
        let currentNotes = (try? context.fetch(FetchDescriptor<StudyNote>())) ?? notes
        if let note = currentNotes.first(where: { $0.body.hasPrefix(marker) }) {
            return note
        }
        let note = StudyNote(title: "UniSaver Task Execution Ledger", body: marker + "{}")
        context.insert(note)
        return note
    }

    static func decode(_ note: StudyNote) -> TaskExecutionLedger {
        let raw = note.body.hasPrefix(marker) ? String(note.body.dropFirst(marker.count)) : ""
        if let data = raw.data(using: .utf8),
           let ledger = try? JSONDecoder().decode(TaskExecutionLedger.self, from: data) {
            return ledger
        }
        return TaskExecutionLedger()
    }

    static func save(_ ledger: TaskExecutionLedger, into note: StudyNote) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(ledger)) ?? Data()
        note.body = marker + (String(data: data, encoding: .utf8) ?? "{}")
        note.updatedAt = .now
    }
}

enum TaskStructureService {
    static func deadlineLabel(for task: AcademicTask) -> String {
        task.dueDate == .distantFuture ? "No deadline supplied" : UniDateFormatters.dayMonth.string(from: task.dueDate)
    }

    static func subtasks(from task: AcademicTask) -> [TaskSubtaskItem] {
        task.taskDescription
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let lower = trimmed.lowercased()
                guard lower.hasPrefix("- [ ]") || lower.hasPrefix("- [x]") else { return nil }
                let completed = lower.hasPrefix("- [x]")
                let title = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return nil }
                return TaskSubtaskItem(
                    id: ConversationProposalEngine.stableHash(title),
                    title: title,
                    isCompleted: completed,
                    originalLine: line
                )
            }
    }

    static func progressLabel(for task: AcademicTask) -> String {
        let items = subtasks(from: task)
        guard !items.isEmpty else {
            return task.status.title
        }
        return "\(items.filter(\.isCompleted).count) of \(items.count) steps completed"
    }

    static func setSubtask(_ item: TaskSubtaskItem, completed: Bool, in task: AcademicTask) {
        let lines = task.taskDescription.components(separatedBy: .newlines)
        task.taskDescription = lines.map { line in
            line == item.originalLine ? "- [\(completed ? "x" : " ")] \(item.title)" : line
        }.joined(separator: "\n")
        task.updatedAt = .now
    }

    static func appendSuggestedSteps(to task: AcademicTask) {
        guard subtasks(from: task).isEmpty else { return }
        let title = task.title.lowercased()
        let steps: [String]
        if title.contains("test") || title.contains("exam") {
            steps = ["List tested topics", "Review notes", "Complete one practice set", "Review mistakes"]
        } else if title.contains("submission") || title.contains("hw") || title.contains("assignment") {
            steps = ["Read the instructions", "Work through the exercises", "Check the answers", "Submit assignment"]
        } else {
            steps = ["Clarify the goal", "Do the main work", "Review the result"]
        }
        let existing = task.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let checklist = (["Subtasks:"] + steps.map { "- [ ] \($0)" }).joined(separator: "\n")
        task.taskDescription = [existing, checklist].filter { !$0.isEmpty }.joined(separator: "\n")
        task.updatedAt = .now
    }
}

enum GamificationLedgerStore {
    static let marker = "UNISAVER_GAMIFICATION_LEDGER_V1:"
    static let ruleVersion = 1

    static func ledgerNote(in notes: [StudyNote], context: ModelContext) -> StudyNote {
        // @Query may not yet include a note just inserted earlier in this run loop.
        let currentNotes = (try? context.fetch(FetchDescriptor<StudyNote>())) ?? notes
        if let note = currentNotes.first(where: { $0.body.hasPrefix(marker) }) {
            return note
        }
        let note = StudyNote(title: "UniSaver Gamification Ledger", body: marker + "{}")
        context.insert(note)
        return note
    }

    static func decode(_ note: StudyNote) -> GamificationLedger {
        let raw = note.body.hasPrefix(marker) ? String(note.body.dropFirst(marker.count)) : ""
        if let data = raw.data(using: .utf8),
           let ledger = try? JSONDecoder().decode(GamificationLedger.self, from: data) {
            return ledger
        }
        return GamificationLedger()
    }

    static func save(_ ledger: GamificationLedger, into note: StudyNote) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(ledger)) ?? Data()
        note.body = marker + (String(data: data, encoding: .utf8) ?? "{}")
        note.updatedAt = .now
    }

    static func award(
        activityType: GamificationActivityType,
        sourceID: String,
        courseID: UUID?,
        occurredAt: Date = .now,
        ledger: inout GamificationLedger
    ) {
        guard occurredAt >= ledger.settings.systemStartedAt else { return }
        let stableEventID = "\(activityType.rawValue)-\(sourceID)-v\(ruleVersion)"
        if let index = ledger.events.firstIndex(where: { $0.id == stableEventID }) {
            ledger.events[index].isActive = true
            ledger.events[index].occurredAt = occurredAt
            return
        }
        ledger.events.append(
            RewardLedgerEvent(
                id: stableEventID,
                activityType: activityType,
                sourceID: sourceID,
                courseID: courseID,
                occurredAt: occurredAt,
                xp: activityType.ruleXP,
                ruleVersion: ruleVersion,
                isActive: true
            )
        )
    }

    static func annul(activityType: GamificationActivityType, sourceID: String, ledger: inout GamificationLedger) {
        let stableEventID = "\(activityType.rawValue)-\(sourceID)-v\(ruleVersion)"
        guard let index = ledger.events.firstIndex(where: { $0.id == stableEventID }), ledger.events[index].isActive else {
            return
        }
        ledger.events[index].isActive = false
    }
}

enum GamificationEngine {
    static func quests(
        tasks: [AcademicTask],
        studyBlocks: [StudyBlock],
        flashcards: [Flashcard],
        ledger: GamificationLedger,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [DailyQuest] {
        if ledger.settings.isGamificationHidden { return [] }
        let postponed = ledger.settings.postponedQuestIDs.filter { _, date in
            calendar.isDate(date, inSameDayAs: now)
        }
        let blockedIDs = Set(ledger.settings.dismissedQuestIDs).union(postponed.keys)
        let activeSources = Set(ledger.activeEvents.map { "\($0.activityType.rawValue):\($0.sourceID)" })

        var candidates: [DailyQuest] = []
        for task in TodayDashboardService.priorityOrderedTasks(tasks, now: now) {
            let id = "task-\(task.id.uuidString)"
            guard !blockedIDs.contains(id), !activeSources.contains("taskCompletion:\(task.id.uuidString)") else { continue }
            let nextStep = TaskStructureService.subtasks(from: task).first(where: { !$0.isCompleted })?.title
            candidates.append(DailyQuest(
                id: id,
                kind: .task,
                title: nextStep.map { "Work on \(task.title): \($0)" } ?? task.title,
                courseTitle: task.course?.name ?? "General",
                estimatedMinutes: Int(task.estimatedDuration / 60),
                reason: taskReason(task, calendar: calendar, now: now),
                sourceID: task.id.uuidString,
                courseID: task.course?.id
            ))
        }
        for block in studyBlocks
            .filter({ $0.status != .completed && $0.status != .cancelled && $0.startDate >= calendar.startOfDay(for: now) })
            .sorted(by: { $0.startDate < $1.startDate }) {
            let id = "studyBlock-\(block.id.uuidString)"
            guard !blockedIDs.contains(id), !activeSources.contains("studyBlockCompletion:\(block.id.uuidString)") else { continue }
            candidates.append(DailyQuest(
                id: id,
                kind: .studyBlock,
                title: block.title,
                courseTitle: block.course?.name ?? "Study",
                estimatedMinutes: Int(block.endDate.timeIntervalSince(block.startDate) / 60),
                reason: "Scheduled work session",
                sourceID: block.id.uuidString,
                courseID: block.course?.id
            ))
        }
        let dueFlashcards = flashcards.filter { $0.reviewState.dueDate <= now }
        if !dueFlashcards.isEmpty {
            let courses = Set(dueFlashcards.compactMap { $0.deck?.course?.name })
            let id = "practice-flashcards-\(calendar.startOfDay(for: now).timeIntervalSince1970)"
            if !blockedIDs.contains(id) {
                candidates.append(DailyQuest(
                    id: id,
                    kind: .practice,
                    title: "Review \(min(10, dueFlashcards.count)) due flashcards",
                    courseTitle: courses.sorted().first ?? "Study",
                    estimatedMinutes: min(15, max(5, dueFlashcards.count * 2)),
                    reason: "Due for spaced repetition",
                    sourceID: "flashcards-\(calendar.startOfDay(for: now).timeIntervalSince1970)",
                    courseID: dueFlashcards.first?.deck?.course?.id
                ))
            }
        }
        var selected = Array(candidates.prefix(3))
        if shouldShowComeback(ledger: ledger, calendar: calendar, now: now),
           let first = selected.first {
            selected[0] = DailyQuest(
                id: "comeback-\(first.id)",
                kind: first.kind,
                title: first.title,
                courseTitle: first.courseTitle,
                estimatedMinutes: min(first.estimatedMinutes ?? 20, 20),
                reason: "Welcome back. Start small.",
                sourceID: first.sourceID,
                courseID: first.courseID,
                isComeback: true
            )
        }
        return selected
    }

    static func weeklySummary(tasks: [AcademicTask], ledger: GamificationLedger, calendar: Calendar = .current, now: Date = .now) -> WeeklyGamificationSummary {
        let week = TodayDashboardService.weekInterval(containing: now, calendar: calendar)
        let weekTasks = tasks.filter { week.contains($0.dueDate) && $0.status != .cancelled }
        let milestoneTasks = weekTasks.filter { $0.taskDescription.localizedCaseInsensitiveContains("AssignmentPlanID") }
        let scopedTasks = milestoneTasks.isEmpty ? weekTasks : milestoneTasks
        let completed = scopedTasks.filter { $0.status == .completed }.count
        let activeDays = Set(ledger.activeEvents.filter { week.contains($0.occurredAt) }.map { calendar.startOfDay(for: $0.occurredAt) }).count
        return WeeklyGamificationSummary(
            completedMilestones: completed,
            totalMilestones: scopedTasks.count,
            label: milestoneTasks.isEmpty ? "Weekly progress: \(completed) of \(scopedTasks.count) planned tasks completed." : "Weekly progress: \(completed) of \(scopedTasks.count) milestones completed.",
            activeDays: activeDays,
            activeDayGoal: ledger.settings.weeklyActiveDayGoal,
            totalXP: ledger.totalXP,
            scopeNote: milestoneTasks.isEmpty ? "No assignment milestones are scheduled this week, so UniSaver is using planned tasks instead." : nil,
            isHidden: ledger.settings.isGamificationHidden
        )
    }

    private static func taskReason(_ task: AcademicTask, calendar: Calendar, now: Date) -> String {
        let days = TodayDashboardService.daysUntil(task.dueDate, calendar: calendar, from: now)
        if task.priority == .urgent || task.priority == .high {
            return "\(task.priority.title) priority"
        }
        if days < 0 { return "Overdue" }
        if days == 0 { return "Due today" }
        if days <= 3 { return "Due in \(days) day\(days == 1 ? "" : "s")" }
        return "Next useful step"
    }

    private static func shouldShowComeback(ledger: GamificationLedger, calendar: Calendar, now: Date) -> Bool {
        guard ledger.settings.comebackAfterInactiveDays > 0 else { return false }
        guard let latest = ledger.activeEvents.map(\.occurredAt).max() else { return false }
        let latestDay = calendar.startOfDay(for: latest)
        let today = calendar.startOfDay(for: now)
        let gap = calendar.dateComponents([.day], from: latestDay, to: today).day ?? 0
        return gap >= ledger.settings.comebackAfterInactiveDays
    }
}

enum ConversationEvidenceState: String, Codable, CaseIterable, Identifiable {
    case explicit
    case needsConfirmation
    case suggested

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explicit: "Explicit in message"
        case .needsConfirmation: "Needs confirmation"
        case .suggested: "Suggested by UniSaver"
        }
    }
}

enum ConversationActionKind: String, Codable, CaseIterable, Identifiable {
    case createTask = "CreateTask"
    case updateTask = "UpdateTask"
    case addSubtasks = "AddSubtasks"
    case updateProgress = "UpdateProgress"
    case proposeWorkSessions = "ProposeWorkSessions"
    case rescheduleWorkSessions = "RescheduleWorkSessions"
    case flagCalendarConflict = "FlagCalendarConflict"
    case importQuestionBank = "ImportQuestionBank"

    var id: String { rawValue }

    var title: String { rawValue }
}

struct ConversationCourseCandidate: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var reason: String
}

struct ConversationSubtaskDraft: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var estimatedMinutes: Int?
    var completionCriterion: String?
    var sourceExcerpt: String?
    var dependencies: [String]?
    var isCompleted: Bool?
    var isSelected = true
    var evidence: ConversationEvidenceState = .suggested
}

struct ConversationWorkSessionDraft: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var startDate: Date
    var endDate: Date
    var reason: String
    var isSelected = true
}

struct ConversationActionDraft: Identifiable, Hashable, Codable {
    var id: String
    var kind: ConversationActionKind
    var title: String
    var sourceText: String
    var evidence: ConversationEvidenceState
    var selectedCourseID: UUID?
    var selectedChapterID: UUID?
    var questionBankDraftJSON: String?
    var approvedAnswerChangeKeys: [String]?
    var courseCandidates: [ConversationCourseCandidate]
    var dueDate: Date?
    var hasKnownTime = false
    var estimatedMinutes: Int?
    var existingTaskID: UUID?
    var existingTaskTitle: String?
    var beforeValue: String?
    var afterValue: String?
    var missingInformation: [String] = []
    var subtasks: [ConversationSubtaskDraft] = []
    var sessions: [ConversationWorkSessionDraft] = []
    var isSelected = true
    var fingerprint: String
    var isStructuredPlan: Bool?
    var completionCriterion: String?
    var sourceExcerpt: String?
    var planOutcome: String?
    var planConstraints: [String]?
    var planMissingDetails: [String]?
    var dependencies: [String]?
    var planSnapshot: TaskStepReviewSnapshot?
    var replacesSubtasks: Bool?
    var associationNeedsReview: Bool?

    var canApply: Bool {
        isSelected && missingInformation.isEmpty && associationNeedsReview != true
    }
}

struct ConversationAnalysisProposal: Identifiable, Hashable, Codable {
    var id: String
    var createdAt: Date
    var referenceDate: Date
    var timeZoneIdentifier: String
    var originalMessage: String
    var summary: String
    var actions: [ConversationActionDraft]
    var warnings: [String]
    var executionTaskIDs: [UUID]?
    var supersedesProposalID: String?
}

enum TodayConversationRole: String, Codable {
    case student
    case agent
    case system
}

struct TodayConversationMessage: Identifiable, Hashable, Codable {
    var id = UUID()
    var role: TodayConversationRole
    var text: String
    var createdAt = Date()
    var proposalID: String?
    var isError = false
}

struct TodayConversationState: Codable, Hashable {
    var schemaVersion = 1
    var messages: [TodayConversationMessage] = []
    var pendingProposals: [String: ConversationAnalysisProposal] = [:]
    var contextMemory: String?
    var toolResults: [String]?
    var accountID: String?
    var sharedResourceIDs: [UUID]?
    var lastExecutionTaskIDs: [UUID]?
    var creationReceipt: ConversationCreationReceipt?
    var appliedProposalIDs: [String]?
    var supersededProposalIDs: [String]?

    mutating func prepareForAccount(_ id: String) {
        if accountID != id {
            let explicitlySelected = accountID == nil ? sharedResourceIDs : nil
            self = TodayConversationState()
            sharedResourceIDs = explicitlySelected
        }
        accountID = id
    }

    mutating func compact() {
        guard messages.count > 24 else { return }
        // Exact bounded excerpts preserve corrections without a fabricated summarization.
        let old = messages.dropLast(16).filter { !$0.isError }
        let excerpts = old.suffix(12).map { "\($0.role.rawValue): \($0.text.prefix(700))" }.joined(separator: "\n")
        contextMemory = String(((contextMemory ?? "") + "\n" + excerpts).suffix(12000))
        messages = Array(messages.suffix(16))
        toolResults = Array((toolResults ?? []).suffix(8))
    }
}

enum TodayConversationStore {
    static let marker = "UNISAVER_TODAY_CONVERSATION_V1:"

    static func conversationNote(in notes: [StudyNote], context: ModelContext) -> StudyNote {
        // @Query may not yet include a note just inserted earlier in this run loop.
        let currentNotes = (try? context.fetch(FetchDescriptor<StudyNote>())) ?? notes
        if let note = currentNotes.first(where: { $0.body.hasPrefix(marker) }) {
            return note
        }
        let note = StudyNote(title: "UniSaver Today Conversation", body: marker + "{}")
        context.insert(note)
        return note
    }

    static func decode(_ note: StudyNote) -> TodayConversationState {
        let raw = note.body.hasPrefix(marker) ? String(note.body.dropFirst(marker.count)) : ""
        guard let data = raw.data(using: .utf8),
              let state = try? JSONDecoder().decode(TodayConversationState.self, from: data) else {
            return TodayConversationState()
        }
        return state
    }

    static func save(_ state: TodayConversationState, into note: StudyNote) {
        var trimmed = state
        trimmed.messages = Array(trimmed.messages.suffix(60))
        let activeProposalIDs = Set(trimmed.messages.compactMap(\.proposalID))
        trimmed.pendingProposals = trimmed.pendingProposals.filter { activeProposalIDs.contains($0.key) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(trimmed)) ?? Data()
        note.body = marker + (String(data: data, encoding: .utf8) ?? "{}")
        note.updatedAt = .now
    }
}

enum TodayConversationAgent {
    static func localReply(for message: String, proposal: ConversationAnalysisProposal, tasks: [AcademicTask]) -> String {
        let actionable = proposal.actions.filter { $0.kind != .flagCalendarConflict }
        let lower = message.lowercased()
        if actionable.isEmpty {
            if proposal.actions.contains(where: { $0.kind == .flagCalendarConflict }) {
                return "I found a calendar change to verify. I will not remove or move classes unless you approve a concrete change."
            }
            if lower.contains("?") || lower.hasPrefix("how ") || lower.hasPrefix("what ") || lower.hasPrefix("can ") {
                return "I can help reason through that. If it should change Tasks or Planner, tell me the class, date, and what you want to update."
            }
            return "I read it. I do not see a safe task or planning change yet, so I will keep your message as context instead of creating work from a guess."
        }
        let createCount = actionable.filter { $0.kind == .createTask }.count
        let updateCount = actionable.filter { $0.kind == .updateTask || $0.kind == .updateProgress || $0.kind == .addSubtasks }.count
        let sessionCount = actionable.flatMap(\.sessions).count
        var pieces: [String] = []
        if createCount > 0 { pieces.append("\(createCount) task\(createCount == 1 ? "" : "s") to add") }
        if updateCount > 0 { pieces.append("\(updateCount) update\(updateCount == 1 ? "" : "s")") }
        if sessionCount > 0 { pieces.append("\(sessionCount) study block\(sessionCount == 1 ? "" : "s") to review") }
        let intro = pieces.isEmpty ? "I found changes to review" : "I found \(pieces.joined(separator: ", "))"
        if lower.contains("behind") || lower.contains("overwhelmed") || lower.contains("lighter") {
            let nextTask = TodayDashboardService.priorityOrderedTasks(tasks).first?.title ?? actionable.first?.title ?? "one small step"
            return "Let’s keep it manageable. Start with \(nextTask), then review the suggested changes before anything moves."
        }
        return "\(intro). Want to see the suggested changes?"
    }
}

enum ConversationProposalEngine {
    static func analyze(
        message: String,
        referenceDate: Date = .now,
        timeZone: TimeZone = .current,
        courses: [Course],
        tasks: [AcademicTask],
        studyBlocks: [StudyBlock]
    ) -> ConversationAnalysisProposal {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var actions: [ConversationActionDraft] = []
        var warnings: [String] = []
        var currentDate: Date?
        let defaultMonthYear = monthYear(from: cleanMessage, referenceDate: referenceDate, calendar: calendar)
        let lines = cleanMessage.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "•-* "))
            guard !line.isEmpty else { continue }
            if let date = dayHeaderDate(from: line, defaultMonthYear: defaultMonthYear, calendar: calendar) {
                currentDate = date
                continue
            }
            let lower = line.lowercased()
            if lower.contains("no classes") || lower.contains("aucun cours") || lower.contains("pas cours") {
                actions.append(flagCalendarAction(line: line, date: currentDate))
                continue
            }
            if lower.contains("free") || lower.contains("libre") || lower.contains("available") {
                actions.append(contentsOf: availabilityActions(from: line, referenceDate: referenceDate, calendar: calendar, tasks: tasks))
                continue
            }
            if lower.contains("finished") || lower.contains("terminé") || lower.contains("done") || lower.contains("déjà commencé") || lower.contains("already started") {
                actions.append(contentsOf: progressActions(from: line, courses: courses, tasks: tasks))
                continue
            }
            let parsed = parsedCourseLine(line, courses: courses)
            let courseCandidates = parsed.candidates
            let courseID = courseCandidates.count == 1 ? courseCandidates.first?.id : nil
            if courseCandidates.count > 1 {
                warnings.append("Several classes may match “\(parsed.courseText)”. Choose one before applying dependent actions.")
            }
            actions.append(contentsOf: academicActions(
                content: parsed.content,
                originalLine: line,
                dueDate: currentDate,
                selectedCourseID: courseID,
                candidates: courseCandidates,
                tasks: tasks,
                calendar: calendar
            ))
        }

        if actions.isEmpty, !cleanMessage.isEmpty {
            actions.append(genericTaskAction(message: cleanMessage, courses: courses, tasks: tasks))
        }
        let deduped = dedupe(actions)
        return ConversationAnalysisProposal(
            id: stableHash(cleanMessage + referenceDate.description + timeZone.identifier),
            createdAt: .now,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZone.identifier,
            originalMessage: cleanMessage,
            summary: "Here’s what I picked up",
            actions: deduped,
            warnings: warnings
        )
    }

    private static func academicActions(content: String, originalLine: String, dueDate: Date?, selectedCourseID: UUID?, candidates: [ConversationCourseCandidate], tasks: [AcademicTask], calendar: Calendar) -> [ConversationActionDraft] {
        let lower = content.lowercased()
        var actions: [ConversationActionDraft] = []
        if lower.contains("+ test") || lower.contains(" and test") {
            let parts = content.components(separatedBy: "+")
            if let prep = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !prep.isEmpty {
                actions.append(taskAction(title: prep, line: originalLine, dueDate: dueDate, selectedCourseID: selectedCourseID, candidates: candidates, tasks: tasks, calendar: calendar))
            }
            actions.append(taskAction(title: "Test · \(content.replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespacesAndNewlines))", line: originalLine, dueDate: dueDate, selectedCourseID: selectedCourseID, candidates: candidates, tasks: tasks, calendar: calendar, estimatedMinutes: 45))
            return actions
        }
        if lower.contains("test") || lower.contains("exam") {
            actions.append(taskAction(title: "Test · \(content)", line: originalLine, dueDate: dueDate, selectedCourseID: selectedCourseID, candidates: candidates, tasks: tasks, calendar: calendar, estimatedMinutes: 45))
        } else if lower.contains("submission") || lower.contains("devoir") || lower.contains("hw") || lower.contains("case") || lower.contains("readings") || lower.contains("lecture") {
            actions.append(taskAction(title: content, line: originalLine, dueDate: dueDate, selectedCourseID: selectedCourseID, candidates: candidates, tasks: tasks, calendar: calendar))
        } else {
            actions.append(taskAction(title: content, line: originalLine, dueDate: dueDate, selectedCourseID: selectedCourseID, candidates: candidates, tasks: tasks, calendar: calendar, evidence: .needsConfirmation))
        }
        return actions
    }

    private static func taskAction(title: String, line: String, dueDate: Date?, selectedCourseID: UUID?, candidates: [ConversationCourseCandidate], tasks: [AcademicTask], calendar: Calendar, estimatedMinutes: Int = 60, evidence: ConversationEvidenceState = .explicit) -> ConversationActionDraft {
        let existing = tasks.first { task in
            normalized(task.title).contains(normalized(title).prefix(24)) || normalized(title).contains(normalized(task.title).prefix(24))
        }
        let missing = selectedCourseID == nil && candidates.count != 1 ? ["Confirm class"] : []
        let kind: ConversationActionKind = existing == nil ? .createTask : .updateTask
        let fingerprint = "\(kind.rawValue)|\(selectedCourseID?.uuidString ?? "none")|\(normalized(title))|\(dueDate?.timeIntervalSince1970 ?? 0)"
        return ConversationActionDraft(
            id: stableHash(fingerprint),
            kind: kind,
            title: title,
            sourceText: line,
            evidence: evidence,
            selectedCourseID: selectedCourseID,
            courseCandidates: candidates,
            dueDate: dueDate,
            hasKnownTime: false,
            estimatedMinutes: estimatedMinutes,
            existingTaskID: existing?.id,
            existingTaskTitle: existing?.title,
            beforeValue: existing.map { "\($0.title) · \($0.dueDate.formatted(date: .abbreviated, time: .omitted))" },
            afterValue: dueDate.map { "\(title) · \($0.formatted(date: .abbreviated, time: .omitted))" },
            missingInformation: missing,
            subtasks: suggestedSubtasks(for: title),
            fingerprint: stableHash(fingerprint)
        )
    }

    private static func progressActions(from line: String, courses: [Course], tasks: [AcademicTask]) -> [ConversationActionDraft] {
        let candidates = parsedCourseLine(line, courses: courses).candidates
        let related = tasks.first { normalized(line).contains(normalized($0.title).prefix(18)) }
        let title = related?.title ?? line
        return [ConversationActionDraft(
            id: stableHash("progress|\(line)"),
            kind: .updateProgress,
            title: title,
            sourceText: line,
            evidence: .needsConfirmation,
            selectedCourseID: related?.course?.id ?? (candidates.count == 1 ? candidates.first?.id : nil),
            courseCandidates: candidates,
            existingTaskID: related?.id,
            existingTaskTitle: related?.title,
            beforeValue: related?.status.title,
            afterValue: "In progress",
            missingInformation: related == nil ? ["Choose the task to update"] : [],
            fingerprint: stableHash("progress|\(related?.id.uuidString ?? line)")
        )]
    }

    private static func availabilityActions(from line: String, referenceDate: Date, calendar: Calendar, tasks: [AcademicTask]) -> [ConversationActionDraft] {
        guard let targetDay = weekdayDate(in: line, referenceDate: referenceDate, calendar: calendar) else {
            return [ConversationActionDraft(id: stableHash("availability|\(line)"), kind: .proposeWorkSessions, title: "Use available time", sourceText: line, evidence: .needsConfirmation, selectedCourseID: nil, courseCandidates: [], missingInformation: ["Confirm the date and time range"], fingerprint: stableHash("availability|\(line)"))]
        }
        let start = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: targetDay) ?? targetDay
        let end = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: targetDay) ?? start.addingTimeInterval(3 * 3600)
        let nextTask = TodayDashboardService.priorityOrderedTasks(tasks, now: referenceDate).first
        let session = ConversationWorkSessionDraft(title: nextTask?.title ?? "Focused work", startDate: start, endDate: minDate(end, start.addingTimeInterval(TimeInterval((nextTask.map { Int($0.estimatedDuration / 60) } ?? 60) * 60))), reason: "Explicit availability: \(line)")
        return [ConversationActionDraft(id: stableHash("availability|\(line)|\(start)"), kind: .proposeWorkSessions, title: nextTask?.title ?? "Plan available time", sourceText: line, evidence: .needsConfirmation, selectedCourseID: nextTask?.course?.id, courseCandidates: nextTask?.course.map { [ConversationCourseCandidate(id: $0.id, title: $0.name, reason: "Task class")] } ?? [], estimatedMinutes: Int(session.endDate.timeIntervalSince(session.startDate) / 60), missingInformation: ["Confirm exact time range if afternoon means something else"], sessions: [session], fingerprint: stableHash("availability|\(line)|\(start)"))]
    }

    private static func flagCalendarAction(line: String, date: Date?) -> ConversationActionDraft {
        ConversationActionDraft(id: stableHash("calendar|\(line)|\(date?.description ?? "")"), kind: .flagCalendarConflict, title: "Verify calendar update: \(line)", sourceText: line, evidence: .explicit, selectedCourseID: nil, courseCandidates: [], dueDate: date, estimatedMinutes: 5, fingerprint: stableHash("calendar|\(line)|\(date?.description ?? "")"))
    }

    private static func genericTaskAction(message: String, courses: [Course], tasks: [AcademicTask]) -> ConversationActionDraft {
        let parsed = parsedCourseLine(message, courses: courses)
        return taskAction(title: String(message.prefix(80)), line: message, dueDate: nil, selectedCourseID: parsed.candidates.count == 1 ? parsed.candidates.first?.id : nil, candidates: parsed.candidates, tasks: tasks, calendar: .current, evidence: .needsConfirmation)
    }

    private static func parsedCourseLine(_ line: String, courses: [Course]) -> (courseText: String, content: String, candidates: [ConversationCourseCandidate]) {
        let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let courseText = parts.count == 2 ? parts[0] : line
        let content = parts.count == 2 ? parts[1] : line
        let candidates = courseMatches(for: courseText, courses: courses)
        return (courseText, content, candidates)
    }

    private static func courseMatches(for text: String, courses: [Course]) -> [ConversationCourseCandidate] {
        let key = normalized(text)
        let words = Set(key.split(separator: " ").map(String.init).filter { $0.count > 1 })
        return courses.compactMap { course in
            let name = normalized(course.name)
            let code = normalized(course.code)
            let acronym = course.name.split(separator: " ").compactMap { $0.first }.map(String.init).joined().lowercased()
            if key.contains(name) || (!code.isEmpty && key.contains(code)) || (!acronym.isEmpty && key.contains(acronym)) {
                return ConversationCourseCandidate(id: course.id, title: course.name, reason: "Matched title, code or abbreviation")
            }
            let courseWords = Set(name.split(separator: " ").map(String.init).filter { $0.count > 3 })
            if !words.intersection(courseWords).isEmpty && words.intersection(courseWords).count >= 2 {
                return ConversationCourseCandidate(id: course.id, title: course.name, reason: "Matched class words")
            }
            return nil
        }
    }

    private static func suggestedSubtasks(for title: String) -> [ConversationSubtaskDraft] {
        let lower = title.lowercased()
        if lower.contains("hw") || lower.contains("exercise") || lower.contains("submission") {
            return ["Read the instructions", "Work through the exercises", "Check the answers", "Submit the assignment"].map { ConversationSubtaskDraft(title: $0, estimatedMinutes: 30) }
        }
        if lower.contains("case") {
            return ["Read the case", "Outline the issue", "Prepare examples", "Review before class"].map { ConversationSubtaskDraft(title: $0, estimatedMinutes: 30) }
        }
        if lower.contains("test") {
            return ["List tested topics", "Review notes", "Do one practice set", "Check mistakes"].map { ConversationSubtaskDraft(title: $0, estimatedMinutes: 25) }
        }
        if lower.contains("reading") {
            return ["Find the reading", "Read actively", "Write three takeaways"].map { ConversationSubtaskDraft(title: $0, estimatedMinutes: 25) }
        }
        return []
    }

    private static func monthYear(from message: String, referenceDate: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents([.year, .month], from: referenceDate)
        let lower = message.lowercased()
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        if let match = months.first(where: { lower.contains($0.key) }) {
            components.month = match.value
        }
        return components
    }

    private static func dayHeaderDate(from line: String, defaultMonthYear: DateComponents, calendar: Calendar) -> Date? {
        let lower = line.lowercased()
        guard ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "lundi", "mardi", "mercredi", "jeudi", "vendredi"].contains(where: { lower.hasPrefix($0) }) else {
            return nil
        }
        let digits = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).first(where: { !$0.isEmpty })
        guard let day = digits.flatMap(Int.init) else { return nil }
        var comps = defaultMonthYear
        comps.day = day
        return calendar.date(from: comps)
    }

    private static func weekdayDate(in text: String, referenceDate: Date, calendar: Calendar) -> Date? {
        let names = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7, "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7]
        guard let target = names.first(where: { text.lowercased().contains($0.key) })?.value else { return nil }
        let start = calendar.startOfDay(for: referenceDate)
        for offset in 0..<14 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if calendar.component(.weekday, from: date) == target {
                return date
            }
        }
        return nil
    }

    private static func dedupe(_ actions: [ConversationActionDraft]) -> [ConversationActionDraft] {
        var seen: Set<String> = []
        return actions.filter { action in
            if seen.contains(action.fingerprint) { return false }
            seen.insert(action.fingerprint)
            return true
        }
    }

    private static func minDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs < rhs ? lhs : rhs
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

enum TodayDashboardService {
    static func makeSnapshot(
        selectedDate: Date,
        workspace: AppWorkspace?,
        courses: [Course],
        sessions: [ClassSession],
        tasks: [AcademicTask],
        exams: [Exam],
        studyBlocks: [StudyBlock],
        readingProgress: [ReadingProgress],
        flashcardsDue: [Flashcard] = [],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> TodayDashboardSnapshot {
        let dayInterval = calendar.dateInterval(of: .day, for: selectedDate) ?? DateInterval(start: selectedDate, duration: 86_400)
        let daySessions = sessions
            .filter { dayInterval.contains($0.startTime) }
            .sorted { $0.startTime < $1.startTime }
        let dayBlocks = studyBlocks
            .filter { dayInterval.intersects(DateInterval(start: $0.startDate, end: $0.endDate)) }
            .sorted { $0.startDate < $1.startDate }

        let timeline = makeTimelineItems(sessions: daySessions, studyBlocks: dayBlocks)
        let nextSession = sessions
            .filter { $0.startTime >= now }
            .sorted { $0.startTime < $1.startTime }
            .first
        let priorityTasks = priorityOrderedTasks(tasks, now: now)
        let upcomingExam = exams
            .filter { $0.date >= calendar.startOfDay(for: now) }
            .sorted { $0.date < $1.date }
            .first
        let assignmentDue = tasks
            .filter { $0.status != .completed && $0.status != .cancelled && $0.dueDate != .distantFuture && $0.dueDate >= calendar.startOfDay(for: now) }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.priority < rhs.priority
            }
            .first
        let progress = courses
            .filter { !$0.isArchived }
            .sorted { $0.name < $1.name }
            .map { CourseProgressSummary(id: $0.id, course: $0, progress: AcademicValidationService.courseStructuralProgress($0)) }
        let recentReading = readingProgress.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.first
        let weeklyOverview = makeWeeklyOverview(
            selectedDate: selectedDate,
            sessions: sessions,
            tasks: tasks,
            flashcards: flashcardsDue,
            calendar: calendar,
            now: now
        )
        let flashcards: FlashcardsSummary
        if let workspace, workspace.isDemoWorkspace {
            flashcards = FlashcardsSummary(
                dueCount: workspace.flashcardsDue,
                courseCount: workspace.flashcardCourseCount,
                lastActivity: workspace.lastStudyActivity,
                isConfigured: true
            )
        } else {
            flashcards = .notConfigured
        }

        return TodayDashboardSnapshot(
            selectedDate: selectedDate,
            workspace: workspace,
            weeklyOverview: weeklyOverview,
            sessions: daySessions,
            studyBlocks: dayBlocks,
            timelineItems: timeline,
            nextSession: nextSession,
            priorityTasks: priorityTasks,
            upcomingExam: upcomingExam,
            assignmentDue: assignmentDue,
            courseProgress: progress,
            flashcards: flashcards,
            recentReading: recentReading
        )
    }

    static func priorityOrderedTasks(_ tasks: [AcademicTask], now: Date = .now) -> [AcademicTask] {
        tasks
            .filter { $0.status != .completed && $0.status != .cancelled }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.title < rhs.title
            }
    }

    static func daysUntil(_ date: Date, calendar: Calendar = .current, from now: Date = .now) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func makeWeeklyOverview(
        selectedDate: Date,
        sessions: [ClassSession],
        tasks: [AcademicTask],
        flashcards: [Flashcard],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> WeeklyOverview {
        let interval = weekInterval(containing: selectedDate, calendar: calendar)
        let days = (0..<7).compactMap { offset -> WeeklyDashboardDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start),
                  let dayInterval = calendar.dateInterval(of: .day, for: day) else {
                return nil
            }
            return WeeklyDashboardDay(
                id: dayInterval.start,
                date: dayInterval.start,
                sessions: sessions
                    .filter { dayInterval.contains($0.startTime) }
                    .sorted { $0.startTime < $1.startTime },
                tasks: tasks
                    .filter { $0.status != .completed && $0.status != .cancelled && dayInterval.contains($0.dueDate) }
                    .sorted { lhs, rhs in
                        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                        return lhs.priority < rhs.priority
                    },
                flashcards: flashcards
                    .filter { dayInterval.contains($0.reviewState.dueDate) }
                    .sorted { $0.reviewState.dueDate < $1.reviewState.dueDate }
            )
        }
        let activeTasks = tasks.filter { $0.status != .completed && $0.status != .cancelled }
        let weekEnd = interval.end
        return WeeklyOverview(
            weekInterval: interval,
            days: days,
            nextSession: sessions.filter { $0.startTime >= now }.sorted { $0.startTime < $1.startTime }.first,
            overdueTasks: activeTasks.filter { $0.dueDate < calendar.startOfDay(for: now) }.sorted { $0.dueDate < $1.dueDate },
            upcomingTasks: activeTasks
                .filter { $0.dueDate >= calendar.startOfDay(for: now) && $0.dueDate < weekEnd }
                .sorted { lhs, rhs in
                    if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                    return lhs.priority < rhs.priority
                },
            dueFlashcards: flashcards
                .filter { $0.reviewState.dueDate < weekEnd }
                .sorted { $0.reviewState.dueDate < $1.reviewState.dueDate }
        )
    }

    static func weekInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        return DateInterval(start: start, end: end)
    }

    private static func makeTimelineItems(sessions: [ClassSession], studyBlocks: [StudyBlock]) -> [DashboardTimelineItem] {
        let sessionItems = sessions.map { session in
            DashboardTimelineItem(
                id: "session-\(session.id.uuidString)",
                title: session.course?.name ?? "Class",
                subtitle: session.title,
                startDate: session.startTime,
                endDate: session.endTime,
                colorIdentifier: session.course?.colorIdentifier ?? "blueViolet",
                status: session.progressStatus.title,
                kind: .session(session)
            )
        }
        let blockItems = studyBlocks.map { block in
            DashboardTimelineItem(
                id: "study-\(block.id.uuidString)",
                title: block.course?.name ?? "Study Block",
                subtitle: block.title,
                startDate: block.startDate,
                endDate: block.endDate,
                colorIdentifier: block.course?.colorIdentifier ?? "rose",
                status: block.status.title,
                kind: .studyBlock(block)
            )
        }
        return (sessionItems + blockItems).sorted { $0.startDate < $1.startDate }
    }
}

extension DateInterval {
    func intersects(_ other: DateInterval) -> Bool {
        start < other.end && other.start < end
    }
}
