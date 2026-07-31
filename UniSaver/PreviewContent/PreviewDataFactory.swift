import Foundation
import SwiftData

enum PreviewDataFactory {
    static func seed(_ context: ModelContext, includeDashboardDemo: Bool = false) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yearStart = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        let yearEnd = calendar.date(byAdding: .month, value: 10, to: yearStart) ?? today
        let semesterEnd = calendar.date(byAdding: .month, value: 4, to: today) ?? yearEnd

        let year = AcademicYear(name: "Academic Year 2026-2027", startDate: yearStart, endDate: yearEnd)
        let semester = Semester(name: "Semester 1", order: 1, startDate: today, endDate: semesterEnd, academicYear: year)
        let workspace = AppWorkspace(
            firstName: "Alya",
            isDemoWorkspace: includeDashboardDemo,
            flashcardsDue: includeDashboardDemo ? 42 : 0,
            flashcardCourseCount: includeDashboardDemo ? 4 : 0,
            lastStudyActivity: includeDashboardDemo ? calendar.date(byAdding: .hour, value: -6, to: .now) : nil
        )
        context.insert(workspace)
        context.insert(year)
        context.insert(semester)

        let courses = [
            Course(name: "Microeconomics", code: "ECO101", courseDescription: "Markets, incentives, and consumer behavior.", professorName: "Dr. Martin Weber", defaultRoom: "B204", colorIdentifier: "blueViolet", symbolName: "chart.xyaxis.line", credits: 6, status: .inProgress, semester: semester),
            Course(name: "Mathematics", code: "MAT110", professorName: "Prof. Nadia Stein", defaultRoom: "A112", colorIdentifier: "teal", symbolName: "function", credits: 6, status: .inProgress, semester: semester),
            Course(name: "Computing Foundations", code: "CS100", professorName: "Dr. Elise Carter", defaultRoom: "Lab 3", colorIdentifier: "green", symbolName: "terminal", credits: 5, status: .needsReview, semester: semester),
            Course(name: "Organizational Behavior", code: "MGT140", professorName: "Prof. Sofia Keller", defaultRoom: "C301", colorIdentifier: "coral", symbolName: "person.3", credits: 4, status: .notStarted, semester: semester),
            Course(name: "German", code: "GERA2", professorName: "Frau Schneider", defaultRoom: "D018", colorIdentifier: "amber", symbolName: "text.book.closed", credits: 3, status: .inProgress, semester: semester)
        ]

        courses.forEach(context.insert)

        addChapters(["Supply and Demand", "Price Elasticity", "Consumer Choice", "Market Failure"], to: courses[0], statuses: [.mastered, .inProgress, .needsReview, .notStarted], context: context)
        addChapters(["Linear Algebra", "Optimization", "Differential Calculus"], to: courses[1], statuses: [.completed, .inProgress, .notStarted], context: context)
        addChapters(["Python Foundations", "Control Flow", "Data Structures"], to: courses[2], statuses: [.mastered, .completed, .inProgress], context: context)
        addChapters(["Teams and Motivation", "Decision Making", "Leadership Cases"], to: courses[3], statuses: [.inProgress, .notStarted, .notStarted], context: context)
        addChapters(["Campus Life", "Academic Vocabulary", "Presentation Practice"], to: courses[4], statuses: [.completed, .inProgress, .needsReview], context: context)

        addSession("Demand Curves", course: courses[0], chapter: courses[0].chapters.first, dayOffset: 0, hour: 10, room: "B204", type: .lecture, progress: .captured, context: context)
        addSession("Elasticity Workshop", course: courses[0], chapter: courses[0].chapters.first { $0.title == "Price Elasticity" }, dayOffset: 2, hour: 13, room: "B204", type: .tutorial, progress: .captured, context: context)
        addSession("Linear Systems", course: courses[1], chapter: courses[1].chapters.first, dayOffset: 0, hour: 9, room: "A112", type: .lecture, progress: .captured, context: context)
        addSession("Optimization Problem Set", course: courses[1], chapter: courses[1].chapters.first { $0.title == "Optimization" }, dayOffset: 1, hour: 15, room: "A112", type: .tutorial, progress: .captured, context: context)
        addSession("Motivation Theories", course: courses[3], chapter: courses[3].chapters.first, dayOffset: 0, hour: 14, room: "C301", type: .seminar, progress: .captured, context: context)
        addSession("Python Control Flow", course: courses[2], chapter: courses[2].chapters.first { $0.title == "Control Flow" }, dayOffset: 1, hour: 11, room: "Lab 3", type: .lab, progress: .organized, context: context)
        addSession("Data Structures Lab", course: courses[2], chapter: courses[2].chapters.first { $0.title == "Data Structures" }, dayOffset: 4, hour: 11, room: "Lab 3", type: .lab, progress: .captured, context: context)
        addSession("Conversation Practice", course: courses[4], chapter: courses[4].chapters.first, dayOffset: -1, hour: 15, room: "D018", type: .seminar, progress: .reviewed, context: context)

        if includeDashboardDemo {
            addDashboardDemoData(context: context, courses: courses, calendar: calendar, today: today)
        }

        try? context.save()
    }

    private static func addChapters(_ titles: [String], to course: Course, statuses: [AcademicItemStatus], context: ModelContext) {
        for (index, title) in titles.enumerated() {
            let chapter = Chapter(
                number: index + 1,
                title: title,
                chapterDescription: "Core chapter for \(course.name).",
                learningObjectives: ["Understand \(title)", "Prepare practice questions"],
                order: index + 1,
                status: statuses.indices.contains(index) ? statuses[index] : .notStarted,
                course: course
            )
            course.chapters.append(chapter)
            context.insert(chapter)
        }
    }

    private static func addSession(_ title: String, course: Course, chapter: Chapter?, dayOffset: Int, hour: Int, room: String, type: ClassSessionType, progress: SessionProgressStatus, context: ModelContext) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: .now)) ?? .now
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(byAdding: .minute, value: 90, to: start) ?? start.addingTimeInterval(5400)
        let session = ClassSession(number: course.sessions.count + 1, title: title, date: day, startTime: start, endTime: end, room: room, professorName: course.professorName, sessionType: type, progressStatus: progress, course: course, chapter: chapter)
        course.sessions.append(session)
        context.insert(session)
    }

    private static func addDashboardDemoData(context: ModelContext, courses: [Course], calendar: Calendar, today: Date) {
        let micro = courses[0]
        let math = courses[1]
        let computing = courses[2]
        let organization = courses[3]

        let studyStart = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: today) ?? today
        let studyEnd = calendar.date(byAdding: .minute, value: 75, to: studyStart) ?? studyStart.addingTimeInterval(4500)
        context.insert(StudyBlock(title: "Elasticity problem set", startDate: studyStart, endDate: studyEnd, status: .planned, course: micro))

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let inTwoDays = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        let examDay = calendar.date(byAdding: .day, value: 12, to: today) ?? today

        context.insert(AcademicTask(title: "Submit Optimization Sheet", taskDescription: "Finish questions 4-8 and attach derivations.", dueDate: tomorrow, priority: .urgent, estimatedDuration: 5400, course: math))
        context.insert(AcademicTask(title: "Review elasticity notes", taskDescription: "Prepare a clean concept summary before the next class.", dueDate: tomorrow, priority: .high, estimatedDuration: 2700, course: micro, chapter: micro.chapters.first { $0.title == "Price Elasticity" }))
        context.insert(AcademicTask(title: "Python exercises", taskDescription: "Complete loops and functions practice.", dueDate: inTwoDays, priority: .medium, estimatedDuration: 3600, course: computing))
        context.insert(AcademicTask(title: "Case reading", taskDescription: "Read the leadership case and mark two discussion points.", dueDate: inTwoDays, priority: .medium, estimatedDuration: 3000, course: organization))

        let examStart = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: examDay)
        let examEnd = examStart.flatMap { calendar.date(byAdding: .minute, value: 120, to: $0) }
        context.insert(Exam(title: "Microeconomics Midterm", date: examDay, startTime: examStart, endTime: examEnd, room: "B204", examType: .midterm, notes: "Covers supply, demand, and elasticity.", course: micro, chapters: micro.chapters))

        context.insert(ReadingProgress(resourceTitle: "Price Elasticity Reader", currentPage: 38, totalPages: 96, lastOpenedAt: calendar.date(byAdding: .hour, value: -3, to: .now) ?? .now, course: micro, chapter: micro.chapters.first { $0.title == "Price Elasticity" }, coverColorIdentifier: micro.colorIdentifier))
    }
}
