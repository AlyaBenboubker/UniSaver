import Foundation
import SwiftData

enum AcademicItemStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case inProgress
    case completed
    case needsReview
    case mastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .completed: "Completed"
        case .needsReview: "Needs review"
        case .mastered: "Mastered"
        }
    }
}

enum SemesterStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case active
    case completed
    case archived

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AttendanceStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case attended
    case missed
    case excused

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum SessionProgressStatus: String, Codable, CaseIterable, Identifiable {
    case captured
    case organized
    case reviewed
    case practiced
    case mastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captured: "Captured"
        case .organized: "Organized"
        case .reviewed: "Reviewed"
        case .practiced: "Practiced"
        case .mastered: "Mastered"
        }
    }

    var structuralProgress: Double {
        switch self {
        case .captured: 0.2
        case .organized: 0.4
        case .reviewed: 0.6
        case .practiced: 0.8
        case .mastered: 1.0
        }
    }

    func advanced() -> SessionProgressStatus {
        switch self {
        case .captured: .organized
        case .organized: .reviewed
        case .reviewed: .practiced
        case .practiced, .mastered: .mastered
        }
    }
}

@Model
final class AcademicYear {
    @Attribute(.unique) var id: UUID
    var name: String
    var startDate: Date
    var endDate: Date
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Semester.academicYear)
    var semesters: [Semester]

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        endDate: Date,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        semesters: [Semester] = []
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.semesters = semesters
    }
}

@Model
final class Semester {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    var startDate: Date
    var endDate: Date
    var status: SemesterStatus
    var createdAt: Date
    var updatedAt: Date

    var academicYear: AcademicYear?

    @Relationship(deleteRule: .cascade, inverse: \Course.semester)
    var courses: [Course]

    init(
        id: UUID = UUID(),
        name: String,
        order: Int,
        startDate: Date,
        endDate: Date,
        status: SemesterStatus = .active,
        academicYear: AcademicYear? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        courses: [Course] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.academicYear = academicYear
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.courses = courses
    }
}

@Model
final class Course {
    @Attribute(.unique) var id: UUID
    var name: String
    var code: String
    var courseDescription: String
    var professorName: String
    var professorEmail: String?
    var defaultRoom: String?
    var colorIdentifier: String
    var symbolName: String?
    var credits: Double?
    var evaluationMethod: String?
    var status: AcademicItemStatus
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    var semester: Semester?

    @Relationship(deleteRule: .cascade, inverse: \Chapter.course)
    var chapters: [Chapter]

    @Relationship(deleteRule: .cascade, inverse: \ClassSession.course)
    var sessions: [ClassSession]

    init(
        id: UUID = UUID(),
        name: String,
        code: String,
        courseDescription: String = "",
        professorName: String = "",
        professorEmail: String? = nil,
        defaultRoom: String? = nil,
        colorIdentifier: String = "blueViolet",
        symbolName: String? = "book.closed",
        credits: Double? = nil,
        evaluationMethod: String? = nil,
        status: AcademicItemStatus = .notStarted,
        isArchived: Bool = false,
        semester: Semester? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        chapters: [Chapter] = [],
        sessions: [ClassSession] = []
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.courseDescription = courseDescription
        self.professorName = professorName
        self.professorEmail = professorEmail
        self.defaultRoom = defaultRoom
        self.colorIdentifier = colorIdentifier
        self.symbolName = symbolName
        self.credits = credits
        self.evaluationMethod = evaluationMethod
        self.status = status
        self.isArchived = isArchived
        self.semester = semester
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.chapters = chapters
        self.sessions = sessions
    }
}

@Model
final class Chapter {
    @Attribute(.unique) var id: UUID
    var number: Int
    var title: String
    var chapterDescription: String
    var learningObjectives: [String]
    var order: Int
    var status: AcademicItemStatus
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    var course: Course?

    @Relationship(deleteRule: .nullify, inverse: \ClassSession.chapter)
    var sessions: [ClassSession]

    init(
        id: UUID = UUID(),
        number: Int,
        title: String,
        chapterDescription: String = "",
        learningObjectives: [String] = [],
        order: Int,
        status: AcademicItemStatus = .notStarted,
        isArchived: Bool = false,
        course: Course? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessions: [ClassSession] = []
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.chapterDescription = chapterDescription
        self.learningObjectives = learningObjectives
        self.order = order
        self.status = status
        self.isArchived = isArchived
        self.course = course
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessions = sessions
    }
}

@Model
final class ClassSession {
    @Attribute(.unique) var id: UUID
    var number: Int
    var title: String
    var sessionDescription: String
    var date: Date
    var startTime: Date
    var endTime: Date
    var room: String?
    var professorName: String?
    var attendanceStatus: AttendanceStatus
    var learningObjectives: [String]
    var importantConcepts: [String]
    var reviewTasks: [String]
    var progressStatus: SessionProgressStatus
    var createdAt: Date
    var updatedAt: Date

    var course: Course?
    var chapter: Chapter?

    init(
        id: UUID = UUID(),
        number: Int,
        title: String,
        sessionDescription: String = "",
        date: Date,
        startTime: Date,
        endTime: Date,
        room: String? = nil,
        professorName: String? = nil,
        attendanceStatus: AttendanceStatus = .planned,
        learningObjectives: [String] = [],
        importantConcepts: [String] = [],
        reviewTasks: [String] = [],
        progressStatus: SessionProgressStatus = .captured,
        course: Course? = nil,
        chapter: Chapter? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.sessionDescription = sessionDescription
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.room = room
        self.professorName = professorName
        self.attendanceStatus = attendanceStatus
        self.learningObjectives = learningObjectives
        self.importantConcepts = importantConcepts
        self.reviewTasks = reviewTasks
        self.progressStatus = progressStatus
        self.course = course
        self.chapter = chapter
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
