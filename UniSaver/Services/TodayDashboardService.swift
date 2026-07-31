import Foundation
import SwiftData

struct TodayDashboardSnapshot {
    let selectedDate: Date
    let workspace: AppWorkspace?
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
            .filter { $0.status != .completed && $0.status != .cancelled && $0.dueDate >= calendar.startOfDay(for: now) }
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
