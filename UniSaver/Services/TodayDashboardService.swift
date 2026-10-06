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
