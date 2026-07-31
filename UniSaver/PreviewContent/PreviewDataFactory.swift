import Foundation
import SwiftData

enum PreviewDataFactory {
    static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yearStart = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        let yearEnd = calendar.date(byAdding: .month, value: 10, to: yearStart) ?? today
        let semesterEnd = calendar.date(byAdding: .month, value: 4, to: today) ?? yearEnd

        let year = AcademicYear(name: "Academic Year 2026-2027", startDate: yearStart, endDate: yearEnd)
        let semester = Semester(name: "Fall Semester", order: 1, startDate: today, endDate: semesterEnd, academicYear: year)
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

        addChapters(["Supply and Demand", "Price Elasticity"], to: courses[0])
        addChapters(["Linear Algebra", "Optimization"], to: courses[1])
        addChapters(["Python Foundations"], to: courses[2])

        addSession("Demand Curves", course: courses[0], chapter: courses[0].chapters.first, dayOffset: 0, hour: 10, room: "B204")
        addSession("Linear Systems", course: courses[1], chapter: courses[1].chapters.first, dayOffset: 0, hour: 9, room: "A112")
        addSession("Motivation Theories", course: courses[3], chapter: nil, dayOffset: 0, hour: 14, room: "C301")
        addSession("Python Control Flow", course: courses[2], chapter: courses[2].chapters.first, dayOffset: 1, hour: 11, room: "Lab 3")

        try? context.save()
    }

    private static func addChapters(_ titles: [String], to course: Course) {
        for (index, title) in titles.enumerated() {
            let chapter = Chapter(
                number: index + 1,
                title: title,
                chapterDescription: "Core chapter for \(course.name).",
                learningObjectives: ["Understand \(title)", "Prepare practice questions"],
                order: index + 1,
                status: index == 0 ? .inProgress : .needsReview,
                course: course
            )
            course.chapters.append(chapter)
        }
    }

    private static func addSession(_ title: String, course: Course, chapter: Chapter?, dayOffset: Int, hour: Int, room: String) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: .now)) ?? .now
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(byAdding: .minute, value: 90, to: start) ?? start.addingTimeInterval(5400)
        let session = ClassSession(number: course.sessions.count + 1, title: title, date: day, startTime: start, endTime: end, room: room, professorName: course.professorName, progressStatus: .captured, course: course, chapter: chapter)
        course.sessions.append(session)
    }
}
