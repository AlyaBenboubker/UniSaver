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

extension AcademicResource {
    var effectiveResourceKind: AcademicResourceKind {
        let candidates = [fileExtension, URL(fileURLWithPath: originalFileName).pathExtension, URL(fileURLWithPath: storedRelativePath).pathExtension]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase }
            .filter { !$0.isEmpty }
        guard let extensionValue = candidates.first else {
            return resourceKind
        }
        return AcademicFileStore.resourceKind(for: extensionValue)
    }

    var effectiveResourceKindTitle: String {
        if effectiveResourceKind == .document {
            let ext = fileExtension.isEmpty ? URL(fileURLWithPath: originalFileName).pathExtension : fileExtension
            return ext.isEmpty ? effectiveResourceKind.title : ext.localizedUppercase
        }
        return effectiveResourceKind.title
    }

    var effectiveResourceSystemImage: String {
        effectiveResourceKind.systemImage
    }
}

enum FlashcardRating: String, Codable, CaseIterable, Identifiable {
    case again
    case hard
    case good
    case easy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

struct FlashcardReviewState: Codable, Equatable {
    var dueDate: Date
    var interval: TimeInterval
    var ease: Double
    var repetitions: Int
    var lapses: Int
    var lastReviewedAt: Date?
    var lastRating: FlashcardRating?

    init(
        dueDate: Date = .now,
        interval: TimeInterval = 0,
        ease: Double = 2.3,
        repetitions: Int = 0,
        lapses: Int = 0,
        lastReviewedAt: Date? = nil,
        lastRating: FlashcardRating? = nil
    ) {
        self.dueDate = dueDate
        self.interval = interval
        self.ease = ease
        self.repetitions = repetitions
        self.lapses = lapses
        self.lastReviewedAt = lastReviewedAt
        self.lastRating = lastRating
    }
}

enum QuizMode: String, Codable, CaseIterable, Identifiable {
    case practice
    case exam

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum QuizQuestionType: String, Codable, CaseIterable, Identifiable {
    case multipleChoice
    case multipleSelect
    case trueFalse
    case shortAnswer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .multipleSelect: "Multiple select"
        case .trueFalse: "True/false"
        case .shortAnswer: "Short answer"
        }
    }
}

enum UnderstandingHelpLevel: String, Codable, CaseIterable, Identifiable, Comparable {
    case none
    case hint
    case steps
    case solution

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No help"
        case .hint: "Hint"
        case .steps: "Steps"
        case .solution: "Solution"
        }
    }

    var rank: Int {
        switch self {
        case .none: 0
        case .hint: 1
        case .steps: 2
        case .solution: 3
        }
    }

    static func < (lhs: UnderstandingHelpLevel, rhs: UnderstandingHelpLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum AutonomousCheckResult: String, Codable, CaseIterable, Identifiable {
    case notChecked
    case couldNotRedo
    case partial
    case independent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notChecked: "Not checked"
        case .couldNotRedo: "Could not redo"
        case .partial: "Partial"
        case .independent: "Independent"
        }
    }

    var progressValue: Double {
        switch self {
        case .notChecked: 0
        case .couldNotRedo: 0
        case .partial: 0.55
        case .independent: 1
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
    var sessionTypeRawValue: String?
    @Transient var sessionType: ClassSessionType {
        get {
            guard let sessionTypeRawValue,
                  let value = ClassSessionType(rawValue: sessionTypeRawValue) else {
                return .lecture
            }
            return value
        }
        set {
            sessionTypeRawValue = newValue.rawValue
        }
    }
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
        self.sessionTypeRawValue = sessionType.rawValue
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

@Model
final class StudyDeck {
    @Attribute(.unique) var id: UUID
    var title: String
    var deckDescription: String
    var colorIdentifier: String
    var symbolName: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    var course: Course?
    var chapter: Chapter?
    var session: ClassSession?

    @Relationship(deleteRule: .cascade, inverse: \Flashcard.deck)
    var cards: [Flashcard]

    init(
        id: UUID = UUID(),
        title: String,
        deckDescription: String = "",
        colorIdentifier: String = "blueViolet",
        symbolName: String = "rectangle.stack.fill",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isArchived: Bool = false,
        course: Course? = nil,
        chapter: Chapter? = nil,
        session: ClassSession? = nil,
        cards: [Flashcard] = []
    ) {
        self.id = id
        self.title = title
        self.deckDescription = deckDescription
        self.colorIdentifier = colorIdentifier
        self.symbolName = symbolName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.course = course
        self.chapter = chapter
        self.session = session
        self.cards = cards
    }
}

@Model
final class Flashcard {
    @Attribute(.unique) var id: UUID
    var front: String
    var back: String
    var hint: String?
    var explanation: String?
    var tags: [String]
    var position: Int
    var createdAt: Date
    var updatedAt: Date

    /// Backing storage for ``reviewState``.
    ///
    /// `FlashcardReviewState` is a composite `Codable` struct. SwiftData's
    /// attribute coder (ModelCoders) cannot round-trip it on this toolchain —
    /// on fetch it traps with "Unable to decode this value
    /// FlashcardReviewState(...)", crashing the app before any card can be read.
    /// Persist the struct as a single JSON `Data` blob and expose it through a
    /// `@Transient` accessor, mirroring the `ClassSession.sessionType` /
    /// `sessionTypeRawValue` pattern already used in this schema.
    var reviewStateData: Data?

    @Transient var reviewState: FlashcardReviewState {
        get {
            guard let reviewStateData,
                  let decoded = try? JSONDecoder().decode(FlashcardReviewState.self, from: reviewStateData) else {
                return FlashcardReviewState()
            }
            return decoded
        }
        set {
            reviewStateData = try? JSONEncoder().encode(newValue)
        }
    }

    var deck: StudyDeck?

    init(
        id: UUID = UUID(),
        front: String,
        back: String,
        hint: String? = nil,
        explanation: String? = nil,
        tags: [String] = [],
        position: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        reviewState: FlashcardReviewState = FlashcardReviewState(),
        deck: StudyDeck? = nil
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.hint = hint
        self.explanation = explanation
        self.tags = tags
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reviewStateData = try? JSONEncoder().encode(reviewState)
        self.deck = deck
    }
}

@Model
final class FlashcardReviewEvent {
    @Attribute(.unique) var id: UUID
    var reviewedAt: Date
    var rating: FlashcardRating
    var previousDueDate: Date
    var nextDueDate: Date
    var responseDuration: TimeInterval

    var card: Flashcard?

    init(
        id: UUID = UUID(),
        reviewedAt: Date = .now,
        rating: FlashcardRating,
        previousDueDate: Date,
        nextDueDate: Date,
        responseDuration: TimeInterval = 0,
        card: Flashcard? = nil
    ) {
        self.id = id
        self.reviewedAt = reviewedAt
        self.rating = rating
        self.previousDueDate = previousDueDate
        self.nextDueDate = nextDueDate
        self.responseDuration = responseDuration
        self.card = card
    }
}

@Model
final class Quiz {
    @Attribute(.unique) var id: UUID
    var title: String
    var quizDescription: String
    var mode: QuizMode
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    var course: Course?
    var chapter: Chapter?
    var session: ClassSession?

    @Relationship(deleteRule: .cascade, inverse: \QuizQuestion.quiz)
    var questions: [QuizQuestion]

    @Relationship(deleteRule: .cascade, inverse: \QuizAttempt.quiz)
    var attempts: [QuizAttempt]

    init(
        id: UUID = UUID(),
        title: String,
        quizDescription: String = "",
        mode: QuizMode = .practice,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isArchived: Bool = false,
        course: Course? = nil,
        chapter: Chapter? = nil,
        session: ClassSession? = nil,
        questions: [QuizQuestion] = [],
        attempts: [QuizAttempt] = []
    ) {
        self.id = id
        self.title = title
        self.quizDescription = quizDescription
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.course = course
        self.chapter = chapter
        self.session = session
        self.questions = questions
        self.attempts = attempts
    }
}

@Model
final class QuizQuestion {
    @Attribute(.unique) var id: UUID
    var prompt: String
    var type: QuizQuestionType
    var choices: [String]
    var correctAnswers: [String]
    var explanation: String
    var hint: String?
    var points: Int
    var position: Int
    var tags: [String]

    var quiz: Quiz?

    init(
        id: UUID = UUID(),
        prompt: String,
        type: QuizQuestionType = .multipleChoice,
        choices: [String] = [],
        correctAnswers: [String] = [],
        explanation: String = "",
        hint: String? = nil,
        points: Int = 1,
        position: Int = 0,
        tags: [String] = [],
        quiz: Quiz? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.type = type
        self.choices = choices
        self.correctAnswers = correctAnswers
        self.explanation = explanation
        self.hint = hint
        self.points = max(points, 1)
        self.position = position
        self.tags = tags
        self.quiz = quiz
    }
}

@Model
final class QuizAttempt {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var completedAt: Date?
    var score: Double
    var maximumScore: Double
    var answers: [String]
    var duration: TimeInterval
    var isCompleted: Bool

    var quiz: Quiz?

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        completedAt: Date? = nil,
        score: Double = 0,
        maximumScore: Double = 0,
        answers: [String] = [],
        duration: TimeInterval = 0,
        isCompleted: Bool = false,
        quiz: Quiz? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.score = score
        self.maximumScore = maximumScore
        self.answers = answers
        self.duration = duration
        self.isCompleted = isCompleted
        self.quiz = quiz
    }
}

@Model
final class UnderstandingPracticeAttempt {
    @Attribute(.unique) var id: UUID
    var exercisePrompt: String
    var subject: String
    var studentAttempt: String
    var hint: String
    var explanationSteps: [String]
    var solution: String
    var transferQuestion: String
    var transferAnswer: String
    var suggestedTransferAnswer: String
    var helpLevelUsed: UnderstandingHelpLevel
    var autonomousResult: AutonomousCheckResult
    var assistanceSource: String
    var createdAt: Date
    var updatedAt: Date

    var course: Course?

    init(
        id: UUID = UUID(),
        exercisePrompt: String,
        subject: String,
        studentAttempt: String = "",
        hint: String = "",
        explanationSteps: [String] = [],
        solution: String = "",
        transferQuestion: String = "",
        transferAnswer: String = "",
        suggestedTransferAnswer: String = "",
        helpLevelUsed: UnderstandingHelpLevel = .none,
        autonomousResult: AutonomousCheckResult = .notChecked,
        assistanceSource: String = "demo",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        course: Course? = nil
    ) {
        self.id = id
        self.exercisePrompt = exercisePrompt
        self.subject = subject
        self.studentAttempt = studentAttempt
        self.hint = hint
        self.explanationSteps = explanationSteps
        self.solution = solution
        self.transferQuestion = transferQuestion
        self.transferAnswer = transferAnswer
        self.suggestedTransferAnswer = suggestedTransferAnswer
        self.helpLevelUsed = helpLevelUsed
        self.autonomousResult = autonomousResult
        self.assistanceSource = assistanceSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.course = course
    }
}

enum LibraryItemKind: String, Codable, CaseIterable, Identifiable {
    case note
    case resource
    case recording
    case quiz
    case studyDeck
    case flashcard
    case understandingPractice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: "Notes"
        case .resource: "Resources"
        case .recording: "Recordings"
        case .quiz: "Quizzes"
        case .studyDeck: "Decks"
        case .flashcard: "Flashcards"
        case .understandingPractice: "Exercises"
        }
    }

    var singularTitle: String {
        switch self {
        case .note: "Note"
        case .resource: "Resource"
        case .recording: "Recording"
        case .quiz: "Quiz"
        case .studyDeck: "Deck"
        case .flashcard: "Flashcard"
        case .understandingPractice: "Exercise"
        }
    }

    var systemImage: String {
        switch self {
        case .note: "note.text"
        case .resource: "doc.richtext"
        case .recording: "waveform"
        case .quiz: "questionmark.app"
        case .studyDeck: "rectangle.stack"
        case .flashcard: "rectangle.stack.fill"
        case .understandingPractice: "brain.head.profile"
        }
    }
}

enum RecordingTranscriptionStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case ready
    case recording
    case transcribing
    case completed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: "Not started"
        case .ready: "Ready"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

enum CourseRecordingSource: String, Codable, CaseIterable, Identifiable {
    case recorded
    case imported
    case demo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recorded: "Recorded in UniSaver"
        case .imported: "Imported audio"
        case .demo: "Demo"
        }
    }
}

@Model
final class LibraryFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \LibraryItem.folder)
    var items: [LibraryItem]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        items: [LibraryItem] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
    }
}

@Model
final class LibraryItem {
    @Attribute(.unique) var id: UUID
    var itemKindRawValue: String
    var itemID: String
    var createdAt: Date
    var updatedAt: Date
    var folder: LibraryFolder?

    init(
        id: UUID = UUID(),
        itemKind: LibraryItemKind,
        itemID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        folder: LibraryFolder? = nil
    ) {
        self.id = id
        self.itemKindRawValue = itemKind.rawValue
        self.itemID = itemID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.folder = folder
    }

    var itemKind: LibraryItemKind {
        LibraryItemKind(rawValue: itemKindRawValue) ?? .resource
    }
}

enum ExternalCalendarProvider: String, Codable, CaseIterable, Identifiable {
    case appleCalendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleCalendar: "Apple Calendar"
        }
    }
}

@Model
final class ExternalCalendarEventLink {
    @Attribute(.unique) var id: UUID
    var providerRawValue: String
    var externalEventIdentifier: String
    var externalStableIdentifier: String?
    var externalCalendarIdentifier: String
    var occurrenceStartDate: Date
    var titleSnapshot: String
    var calendarTitleSnapshot: String
    var sourceURLString: String?
    var createdAt: Date
    var updatedAt: Date

    var course: Course?
    var chapter: Chapter?
    var session: ClassSession?

    init(
        id: UUID = UUID(),
        provider: ExternalCalendarProvider = .appleCalendar,
        externalEventIdentifier: String,
        externalStableIdentifier: String? = nil,
        externalCalendarIdentifier: String,
        occurrenceStartDate: Date,
        titleSnapshot: String,
        calendarTitleSnapshot: String,
        sourceURLString: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        course: Course? = nil,
        chapter: Chapter? = nil,
        session: ClassSession? = nil
    ) {
        self.id = id
        self.providerRawValue = provider.rawValue
        self.externalEventIdentifier = externalEventIdentifier
        self.externalStableIdentifier = externalStableIdentifier
        self.externalCalendarIdentifier = externalCalendarIdentifier
        self.occurrenceStartDate = occurrenceStartDate
        self.titleSnapshot = titleSnapshot
        self.calendarTitleSnapshot = calendarTitleSnapshot
        self.sourceURLString = sourceURLString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.course = course
        self.chapter = chapter
        self.session = session
    }

    var provider: ExternalCalendarProvider {
        ExternalCalendarProvider(rawValue: providerRawValue) ?? .appleCalendar
    }
}

enum ExternalLearningPlatform: String, Codable, CaseIterable, Identifiable {
    case moodle
    case quizlet
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moodle: "Moodle / eCampus"
        case .quizlet: "Quizlet"
        case .other: "Other"
        }
    }
}

enum ExternalLearningActivityType: String, Codable, CaseIterable, Identifiable {
    case exercise
    case quiz
    case flashcards
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exercise: "Exercise"
        case .quiz: "Quiz"
        case .flashcards: "Flashcards"
        case .other: "Other"
        }
    }
}

enum ExternalLearningActivityStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case inProgress
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In progress"
        case .completed: "Completed"
        }
    }
}

enum MathExerciseSourceKind: String, Codable, CaseIterable, Identifiable {
    case pdf
    case image
    case photo
    case screenshot
    case moodle
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .image: "Image"
        case .photo: "Photo"
        case .screenshot: "Screenshot"
        case .moodle: "Moodle"
        case .other: "Other"
        }
    }
}

enum MathExerciseRecognitionStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case extracted
    case needsReview
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: "Not started"
        case .extracted: "Text extracted"
        case .needsReview: "Needs verification"
        case .failed: "Recognition failed"
        }
    }
}

enum MathExerciseWorkMode: String, Codable, CaseIterable, Identifiable {
    case exam
    case autonomy
    case coach
    case guided
    case freeCorrection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exam: "Examen"
        case .autonomy: "Autonomie"
        case .coach: "Coach"
        case .guided: "Guidé"
        case .freeCorrection: "Correction libre"
        }
    }

    var explanation: String {
        switch self {
        case .exam:
            "Aucun indice ni correction avant la remise."
        case .autonomy:
            "Tu travailles seule ; UniSaver peut proposer un indice après une longue pause."
        case .coach:
            "Tu peux demander une vérification, un indice ou l’explication d’une erreur sur une étape."
        case .guided:
            "UniSaver pose une question à la fois et attend ta tentative."
        case .freeCorrection:
            "Aucune intervention pendant la résolution ; tu demandes la correction quand tu es prête."
        }
    }
}

enum MathExerciseAttemptStatus: String, Codable, CaseIterable, Identifiable {
    case inProgress
    case submitted
    case reviewed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inProgress: "In progress"
        case .submitted: "Submitted"
        case .reviewed: "Reviewed"
        }
    }
}

enum EssayAssignmentKind: String, Codable, CaseIterable, Identifiable {
    case openQuestion
    case essay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openQuestion: "Question ouverte"
        case .essay: "Essai"
        }
    }
}

enum EssayWorkMode: String, Codable, CaseIterable, Identifiable {
    case training
    case examSimulation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .training: "Entraînement"
        case .examSimulation: "Simulation d’examen"
        }
    }
}

enum EssayAssignmentStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case submitted
    case feedbackAvailable
    case revised

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Brouillon"
        case .submitted: "Remis"
        case .feedbackAvailable: "Retour disponible"
        case .revised: "Révisé"
        }
    }
}

enum EssayFeedbackStatus: String, Codable, CaseIterable, Identifiable {
    case notRequested
    case unavailable
    case available
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notRequested: "Not requested"
        case .unavailable: "AI unavailable"
        case .available: "Available"
        case .failed: "Failed"
        }
    }
}

@Model
final class ExternalLearningActivity {
    @Attribute(.unique) var id: UUID
    var title: String
    var originalURLString: String
    var platformRawValue: String
    var activityTypeRawValue: String
    var statusRawValue: String
    var addedAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var observedScore: String
    var personalNote: String
    var difficultConcepts: [String]

    var course: Course?
    var chapter: Chapter?

    init(
        id: UUID = UUID(),
        title: String,
        originalURLString: String,
        platform: ExternalLearningPlatform,
        activityType: ExternalLearningActivityType,
        status: ExternalLearningActivityStatus = .todo,
        addedAt: Date = .now,
        updatedAt: Date = .now,
        lastOpenedAt: Date? = nil,
        observedScore: String = "",
        personalNote: String = "",
        difficultConcepts: [String] = [],
        course: Course? = nil,
        chapter: Chapter? = nil
    ) {
        self.id = id
        self.title = title
        self.originalURLString = originalURLString
        self.platformRawValue = platform.rawValue
        self.activityTypeRawValue = activityType.rawValue
        self.statusRawValue = status.rawValue
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.observedScore = observedScore
        self.personalNote = personalNote
        self.difficultConcepts = difficultConcepts
        self.course = course
        self.chapter = chapter
    }

    var platform: ExternalLearningPlatform {
        get { ExternalLearningPlatform(rawValue: platformRawValue) ?? .other }
        set { platformRawValue = newValue.rawValue }
    }

    var activityType: ExternalLearningActivityType {
        get { ExternalLearningActivityType(rawValue: activityTypeRawValue) ?? .other }
        set { activityTypeRawValue = newValue.rawValue }
    }

    var status: ExternalLearningActivityStatus {
        get { ExternalLearningActivityStatus(rawValue: statusRawValue) ?? .todo }
        set { statusRawValue = newValue.rawValue }
    }

    var originalURL: URL? {
        URL(string: originalURLString)
    }
}

@Model
final class EssayAssignment {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRawValue: String
    var modeRawValue: String
    var statusRawValue: String
    var prompt: String
    var promptRecognitionNotes: String
    var expectedWordCount: Int?
    var durationMinutes: Int?
    var dueDate: Date?
    var evaluationCriteria: String
    var allowedResources: String
    var outlineThesis: String
    var outlineArguments: String
    var outlineEvidence: String
    var outlineObjections: String
    var draftBody: String
    var pasteBlockedCount: Int
    var activeDuration: TimeInterval
    var createdAt: Date
    var updatedAt: Date

    var course: Course?
    var chapter: Chapter?
    var promptResource: AcademicResource?

    @Relationship(deleteRule: .cascade, inverse: \EssaySource.assignment)
    var sources: [EssaySource]

    @Relationship(deleteRule: .cascade, inverse: \EssaySubmission.assignment)
    var submissions: [EssaySubmission]

    init(
        id: UUID = UUID(),
        title: String,
        kind: EssayAssignmentKind,
        mode: EssayWorkMode = .training,
        status: EssayAssignmentStatus = .draft,
        prompt: String = "",
        promptRecognitionNotes: String = "",
        expectedWordCount: Int? = nil,
        durationMinutes: Int? = nil,
        dueDate: Date? = nil,
        evaluationCriteria: String = "",
        allowedResources: String = "",
        outlineThesis: String = "",
        outlineArguments: String = "",
        outlineEvidence: String = "",
        outlineObjections: String = "",
        draftBody: String = "",
        pasteBlockedCount: Int = 0,
        activeDuration: TimeInterval = 0,
        course: Course? = nil,
        chapter: Chapter? = nil,
        promptResource: AcademicResource? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sources: [EssaySource] = [],
        submissions: [EssaySubmission] = []
    ) {
        self.id = id
        self.title = title
        self.kindRawValue = kind.rawValue
        self.modeRawValue = mode.rawValue
        self.statusRawValue = status.rawValue
        self.prompt = prompt
        self.promptRecognitionNotes = promptRecognitionNotes
        self.expectedWordCount = expectedWordCount
        self.durationMinutes = durationMinutes
        self.dueDate = dueDate
        self.evaluationCriteria = evaluationCriteria
        self.allowedResources = allowedResources
        self.outlineThesis = outlineThesis
        self.outlineArguments = outlineArguments
        self.outlineEvidence = outlineEvidence
        self.outlineObjections = outlineObjections
        self.draftBody = draftBody
        self.pasteBlockedCount = pasteBlockedCount
        self.activeDuration = activeDuration
        self.course = course
        self.chapter = chapter
        self.promptResource = promptResource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sources = sources
        self.submissions = submissions
    }

    var kind: EssayAssignmentKind {
        get { EssayAssignmentKind(rawValue: kindRawValue) ?? .essay }
        set { kindRawValue = newValue.rawValue }
    }

    var mode: EssayWorkMode {
        get { EssayWorkMode(rawValue: modeRawValue) ?? .training }
        set { modeRawValue = newValue.rawValue }
    }

    var status: EssayAssignmentStatus {
        get { EssayAssignmentStatus(rawValue: statusRawValue) ?? .draft }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class EssaySource {
    @Attribute(.unique) var id: UUID
    var author: String
    var title: String
    var year: String
    var page: String
    var urlString: String
    var highlightedExcerpt: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    var assignment: EssayAssignment?
    var resource: AcademicResource?
    var studyNote: StudyNote?

    init(
        id: UUID = UUID(),
        author: String = "",
        title: String,
        year: String = "",
        page: String = "",
        urlString: String = "",
        highlightedExcerpt: String = "",
        note: String = "",
        assignment: EssayAssignment? = nil,
        resource: AcademicResource? = nil,
        studyNote: StudyNote? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.author = author
        self.title = title
        self.year = year
        self.page = page
        self.urlString = urlString
        self.highlightedExcerpt = highlightedExcerpt
        self.note = note
        self.assignment = assignment
        self.resource = resource
        self.studyNote = studyNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class EssaySubmission {
    @Attribute(.unique) var id: UUID
    var versionNumber: Int
    var body: String
    var submittedAt: Date
    var wordCount: Int
    var activeDuration: TimeInterval
    var revisionExplanation: String
    var feedbackStatusRawValue: String
    var feedbackSourceLabel: String
    var feedbackGeneratedAt: Date?
    var feedbackObservations: String
    var feedbackSuggestions: String
    var feedbackUncertainties: String
    var revisionPlan: [String]

    var assignment: EssayAssignment?

    init(
        id: UUID = UUID(),
        versionNumber: Int,
        body: String,
        submittedAt: Date = .now,
        wordCount: Int,
        activeDuration: TimeInterval = 0,
        revisionExplanation: String = "",
        feedbackStatus: EssayFeedbackStatus = .notRequested,
        feedbackSourceLabel: String = "",
        feedbackGeneratedAt: Date? = nil,
        feedbackObservations: String = "",
        feedbackSuggestions: String = "",
        feedbackUncertainties: String = "",
        revisionPlan: [String] = [],
        assignment: EssayAssignment? = nil
    ) {
        self.id = id
        self.versionNumber = versionNumber
        self.body = body
        self.submittedAt = submittedAt
        self.wordCount = wordCount
        self.activeDuration = activeDuration
        self.revisionExplanation = revisionExplanation
        self.feedbackStatusRawValue = feedbackStatus.rawValue
        self.feedbackSourceLabel = feedbackSourceLabel
        self.feedbackGeneratedAt = feedbackGeneratedAt
        self.feedbackObservations = feedbackObservations
        self.feedbackSuggestions = feedbackSuggestions
        self.feedbackUncertainties = feedbackUncertainties
        self.revisionPlan = revisionPlan
        self.assignment = assignment
    }

    var feedbackStatus: EssayFeedbackStatus {
        get { EssayFeedbackStatus(rawValue: feedbackStatusRawValue) ?? .notRequested }
        set { feedbackStatusRawValue = newValue.rawValue }
    }
}

@Model
final class MathExercise {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceKindRawValue: String
    var selectedPage: Int
    var selectedRegionDescription: String
    var recognizedPrompt: String
    var recognitionStatusRawValue: String
    var recognitionNotes: String
    var professorSolution: String
    var createdAt: Date
    var updatedAt: Date

    var course: Course?
    var chapter: Chapter?
    var sourceResource: AcademicResource?
    var externalActivity: ExternalLearningActivity?

    @Relationship(deleteRule: .cascade, inverse: \MathExerciseAttempt.exercise)
    var attempts: [MathExerciseAttempt]

    init(
        id: UUID = UUID(),
        title: String,
        sourceKind: MathExerciseSourceKind,
        selectedPage: Int = 1,
        selectedRegionDescription: String = "",
        recognizedPrompt: String = "",
        recognitionStatus: MathExerciseRecognitionStatus = .notStarted,
        recognitionNotes: String = "",
        professorSolution: String = "",
        course: Course? = nil,
        chapter: Chapter? = nil,
        sourceResource: AcademicResource? = nil,
        externalActivity: ExternalLearningActivity? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        attempts: [MathExerciseAttempt] = []
    ) {
        self.id = id
        self.title = title
        self.sourceKindRawValue = sourceKind.rawValue
        self.selectedPage = max(selectedPage, 1)
        self.selectedRegionDescription = selectedRegionDescription
        self.recognizedPrompt = recognizedPrompt
        self.recognitionStatusRawValue = recognitionStatus.rawValue
        self.recognitionNotes = recognitionNotes
        self.professorSolution = professorSolution
        self.course = course
        self.chapter = chapter
        self.sourceResource = sourceResource
        self.externalActivity = externalActivity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attempts = attempts
    }

    var sourceKind: MathExerciseSourceKind {
        get { MathExerciseSourceKind(rawValue: sourceKindRawValue) ?? .other }
        set { sourceKindRawValue = newValue.rawValue }
    }

    var recognitionStatus: MathExerciseRecognitionStatus {
        get { MathExerciseRecognitionStatus(rawValue: recognitionStatusRawValue) ?? .notStarted }
        set { recognitionStatusRawValue = newValue.rawValue }
    }
}

@Model
final class MathExerciseAttempt {
    @Attribute(.unique) var id: UUID
    var workModeRawValue: String
    var statusRawValue: String
    var startedAt: Date
    var updatedAt: Date
    var submittedAt: Date?
    var activeDuration: TimeInterval
    var currentQuestionIndex: Int
    var scratchPageIndex: Int
    var pencilDrawingData: Data?
    var typedScratch: String
    var selectedStepDescription: String
    var helpRequests: [String]
    var selfAssessment: String

    var exercise: MathExercise?

    init(
        id: UUID = UUID(),
        workMode: MathExerciseWorkMode,
        status: MathExerciseAttemptStatus = .inProgress,
        startedAt: Date = .now,
        updatedAt: Date = .now,
        submittedAt: Date? = nil,
        activeDuration: TimeInterval = 0,
        currentQuestionIndex: Int = 0,
        scratchPageIndex: Int = 0,
        pencilDrawingData: Data? = nil,
        typedScratch: String = "",
        selectedStepDescription: String = "",
        helpRequests: [String] = [],
        selfAssessment: String = "",
        exercise: MathExercise? = nil
    ) {
        self.id = id
        self.workModeRawValue = workMode.rawValue
        self.statusRawValue = status.rawValue
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.submittedAt = submittedAt
        self.activeDuration = activeDuration
        self.currentQuestionIndex = currentQuestionIndex
        self.scratchPageIndex = scratchPageIndex
        self.pencilDrawingData = pencilDrawingData
        self.typedScratch = typedScratch
        self.selectedStepDescription = selectedStepDescription
        self.helpRequests = helpRequests
        self.selfAssessment = selfAssessment
        self.exercise = exercise
    }

    var workMode: MathExerciseWorkMode {
        get { MathExerciseWorkMode(rawValue: workModeRawValue) ?? .autonomy }
        set { workModeRawValue = newValue.rawValue }
    }

    var status: MathExerciseAttemptStatus {
        get { MathExerciseAttemptStatus(rawValue: statusRawValue) ?? .inProgress }
        set { statusRawValue = newValue.rawValue }
    }
}
