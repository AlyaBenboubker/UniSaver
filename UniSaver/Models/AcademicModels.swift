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

enum AcademicTaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case inProgress
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In progress"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }
}

enum AcademicTaskPriority: String, Codable, CaseIterable, Identifiable, Comparable {
    case low
    case medium
    case high
    case urgent

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var rank: Int {
        switch self {
        case .urgent: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }

    static func < (lhs: AcademicTaskPriority, rhs: AcademicTaskPriority) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum ExamType: String, Codable, CaseIterable, Identifiable {
    case quiz
    case midterm
    case final
    case oral
    case project
    case other

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum StudyBlockStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case inProgress
    case completed
    case cancelled

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

enum ClassSessionType: String, Codable, CaseIterable, Identifiable {
    case lecture
    case tutorial
    case lab
    case seminar
    case study
    case examPrep
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lecture: "Lecture"
        case .tutorial: "Tutorial"
        case .lab: "Lab"
        case .seminar: "Seminar"
        case .study: "Study"
        case .examPrep: "Exam prep"
        case .custom: "Custom"
        }
    }
}

enum AcademicResourceKind: String, Codable, CaseIterable, Identifiable {
    case pdf
    case image
    case audio
    case video
    case document
    case spreadsheet
    case link
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .image: "Image"
        case .audio: "Audio"
        case .video: "Video"
        case .document: "Document"
        case .spreadsheet: "Spreadsheet"
        case .link: "Link"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .audio: "waveform"
        case .video: "play.rectangle"
        case .document: "doc.text"
        case .spreadsheet: "tablecells"
        case .link: "link"
        case .other: "doc"
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
    var startDate: Date?
    var endDate: Date?
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
        startDate: Date? = nil,
        endDate: Date? = nil,
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
        self.startDate = startDate
        self.endDate = endDate
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
    var sessionType: ClassSessionType
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
        sessionType: ClassSessionType = .lecture,
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
        self.sessionType = sessionType
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

@Model
final class AcademicTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var taskDescription: String
    var dueDate: Date
    var priority: AcademicTaskPriority
    var status: AcademicTaskStatus
    var estimatedDuration: TimeInterval
    var createdAt: Date
    var updatedAt: Date

    var course: Course?
    var chapter: Chapter?
    var session: ClassSession?

    init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String = "",
        dueDate: Date,
        priority: AcademicTaskPriority = .medium,
        status: AcademicTaskStatus = .todo,
        estimatedDuration: TimeInterval = 3600,
        course: Course? = nil,
        chapter: Chapter? = nil,
        session: ClassSession? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.dueDate = dueDate
        self.priority = priority
        self.status = status
        self.estimatedDuration = estimatedDuration
        self.course = course
        self.chapter = chapter
        self.session = session
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Exam {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: Date
    var startTime: Date?
    var endTime: Date?
    var room: String?
    var examType: ExamType
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    var course: Course?

    @Relationship(deleteRule: .nullify)
    var chapters: [Chapter]

    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        startTime: Date? = nil,
        endTime: Date? = nil,
        room: String? = nil,
        examType: ExamType = .midterm,
        notes: String = "",
        course: Course? = nil,
        chapters: [Chapter] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.room = room
        self.examType = examType
        self.notes = notes
        self.course = course
        self.chapters = chapters
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class StudyBlock {
    @Attribute(.unique) var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var status: StudyBlockStatus
    var createdAt: Date
    var updatedAt: Date

    var course: Course?
    var task: AcademicTask?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        status: StudyBlockStatus = .planned,
        course: Course? = nil,
        task: AcademicTask? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.course = course
        self.task = task
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ReadingProgress {
    @Attribute(.unique) var id: UUID
    var resourceTitle: String
    var currentPage: Int
    var totalPages: Int
    var lastOpenedAt: Date
    var coverColorIdentifier: String
    var createdAt: Date
    var updatedAt: Date

    var course: Course?
    var chapter: Chapter?

    init(
        id: UUID = UUID(),
        resourceTitle: String,
        currentPage: Int,
        totalPages: Int,
        lastOpenedAt: Date = .now,
        course: Course? = nil,
        chapter: Chapter? = nil,
        coverColorIdentifier: String = "blueViolet",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.resourceTitle = resourceTitle
        self.currentPage = currentPage
        self.totalPages = max(totalPages, 1)
        self.lastOpenedAt = lastOpenedAt
        self.course = course
        self.chapter = chapter
        self.coverColorIdentifier = coverColorIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var progress: Double {
        min(max(Double(currentPage) / Double(totalPages), 0), 1)
    }
}

@Model
final class AcademicResource {
    @Attribute(.unique) var id: UUID
    var title: String
    var resourceKind: AcademicResourceKind
    var originalFileName: String
    var resourceDescription: String
    var storedRelativePath: String
    var mimeType: String
    var fileExtension: String
    var fileSize: Int64
    var contentHash: String?
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var readingProgress: Double
    var lastPage: Int
    var pageCount: Int
    var isFavorite: Bool
    var tags: [String]

    var course: Course?
    var chapter: Chapter?
    var session: ClassSession?

    init(
        id: UUID = UUID(),
        title: String,
        resourceKind: AcademicResourceKind,
        originalFileName: String,
        resourceDescription: String = "",
        storedRelativePath: String,
        mimeType: String = "application/octet-stream",
        fileExtension: String = "",
        fileSize: Int64 = 0,
        contentHash: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastOpenedAt: Date? = nil,
        readingProgress: Double = 0,
        lastPage: Int = 1,
        pageCount: Int = 1,
        isFavorite: Bool = false,
        tags: [String] = [],
        course: Course? = nil,
        chapter: Chapter? = nil,
        session: ClassSession? = nil
    ) {
        self.id = id
        self.title = title
        self.resourceKind = resourceKind
        self.originalFileName = originalFileName
        self.resourceDescription = resourceDescription
        self.storedRelativePath = storedRelativePath
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.readingProgress = min(max(readingProgress, 0), 1)
        self.lastPage = max(lastPage, 1)
        self.pageCount = max(pageCount, 1)
        self.isFavorite = isFavorite
        self.tags = tags
        self.course = course
        self.chapter = chapter
        self.session = session
    }
}

@Model
final class StudyNote {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    var course: Course?
    var chapter: Chapter?
    var session: ClassSession?
    var resource: AcademicResource?

    init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isPinned: Bool = false,
        course: Course? = nil,
        chapter: Chapter? = nil,
        session: ClassSession? = nil,
        resource: AcademicResource? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.course = course
        self.chapter = chapter
        self.session = session
        self.resource = resource
    }
}

@Model
final class CourseRecording {
    @Attribute(.unique) var id: UUID
    var title: String
    var storedRelativePath: String
    var duration: TimeInterval
    var createdAt: Date
    var updatedAt: Date
    var notes: String?
    var note: StudyNote?

    var course: Course?
    var chapter: Chapter?
    var session: ClassSession?

    init(
        id: UUID = UUID(),
        title: String,
        storedRelativePath: String,
        duration: TimeInterval = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        course: Course? = nil,
        chapter: Chapter? = nil,
        session: ClassSession? = nil,
        note: StudyNote? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.storedRelativePath = storedRelativePath
        self.duration = duration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.course = course
        self.chapter = chapter
        self.session = session
        self.note = note
        self.notes = notes
    }
}

@Model
final class AppWorkspace {
    @Attribute(.unique) var id: String
    var firstName: String
    var isDemoWorkspace: Bool
    var flashcardsDue: Int
    var flashcardCourseCount: Int
    var lastStudyActivity: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "default",
        firstName: String = "Alya",
        isDemoWorkspace: Bool = false,
        flashcardsDue: Int = 0,
        flashcardCourseCount: Int = 0,
        lastStudyActivity: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.firstName = firstName
        self.isDemoWorkspace = isDemoWorkspace
        self.flashcardsDue = flashcardsDue
        self.flashcardCourseCount = flashcardCourseCount
        self.lastStudyActivity = lastStudyActivity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
