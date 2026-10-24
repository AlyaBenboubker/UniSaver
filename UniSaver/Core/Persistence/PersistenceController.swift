import Foundation
import SwiftData

enum UniSaverSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AcademicYear.self,
            Semester.self,
            Course.self,
            Chapter.self,
            ClassSession.self,
            AcademicTask.self,
            Exam.self,
            StudyBlock.self,
            ReadingProgress.self,
            AcademicResource.self,
            StudyNote.self,
            CourseRecording.self,
            AppWorkspace.self
        ]
    }
}

enum UniSaverMigrationPlan: SchemaMigrationPlan {
    // Keep only the current schema in the effective plan. Older schema
    // definitions remain below for diagnostics and regression checks, but
    // stores observed at 5.0.0 and 6.0.0 share the same CoreData checksum.
    // Listing both, or listing a source schema equal to the opened store,
    // makes CoreData abort with "Duplicate version checksums detected".
    // SwiftData performs the required lightweight migration directly to V10.
    static var schemas: [any VersionedSchema.Type] {
        [
            UniSaverSchemaV10.self
        ]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum UniSaverSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AcademicYear.self,
            Semester.self,
            Course.self,
            Chapter.self,
            ClassSession.self,
            AcademicTask.self,
            Exam.self,
            StudyBlock.self,
            ReadingProgress.self,
            AcademicResource.self,
            StudyNote.self,
            CourseRecording.self,
            AppWorkspace.self,
            StudyDeck.self,
            Flashcard.self,
            FlashcardReviewEvent.self,
            Quiz.self,
            QuizQuestion.self,
            QuizAttempt.self
        ]
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

        init() {
            id = UUID()
            name = ""
            startDate = .now
            endDate = .now
            isActive = true
            createdAt = .now
            updatedAt = .now
            semesters = []
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

        init() {
            id = UUID()
            name = ""
            order = 0
            startDate = .now
            endDate = .now
            status = .active
            createdAt = .now
            updatedAt = .now
            courses = []
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

        init() {
            id = UUID()
            name = ""
            code = ""
            courseDescription = ""
            professorName = ""
            colorIdentifier = "blueViolet"
            status = .notStarted
            isArchived = false
            createdAt = .now
            updatedAt = .now
            chapters = []
            sessions = []
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

        init() {
            id = UUID()
            number = 0
            title = ""
            chapterDescription = ""
            learningObjectives = []
            order = 0
            status = .notStarted
            isArchived = false
            createdAt = .now
            updatedAt = .now
            sessions = []
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
        var learningObjectives: [String]
        var importantConcepts: [String]
        var reviewTasks: [String]
        var progressStatus: SessionProgressStatus
        var createdAt: Date
        var updatedAt: Date
        var course: Course?
        var chapter: Chapter?

        init() {
            id = UUID()
            number = 0
            title = ""
            sessionDescription = ""
            date = .now
            startTime = .now
            endTime = .now
            attendanceStatus = .planned
            sessionTypeRawValue = ClassSessionType.lecture.rawValue
            learningObjectives = []
            importantConcepts = []
            reviewTasks = []
            progressStatus = .captured
            createdAt = .now
            updatedAt = .now
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

        init() {
            id = UUID()
            title = ""
            taskDescription = ""
            dueDate = .now
            priority = .medium
            status = .todo
            estimatedDuration = 3600
            createdAt = .now
            updatedAt = .now
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

        init() {
            id = UUID()
            title = ""
            date = .now
            examType = .midterm
            notes = ""
            createdAt = .now
            updatedAt = .now
            chapters = []
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

        init() {
            id = UUID()
            title = ""
            startDate = .now
            endDate = .now
            status = .planned
            createdAt = .now
            updatedAt = .now
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

        init() {
            id = UUID()
            resourceTitle = ""
            currentPage = 1
            totalPages = 1
            lastOpenedAt = .now
            coverColorIdentifier = "blueViolet"
            createdAt = .now
            updatedAt = .now
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

        init() {
            id = UUID()
            title = ""
            resourceKind = .document
            originalFileName = ""
            resourceDescription = ""
            storedRelativePath = ""
            mimeType = "application/octet-stream"
            fileExtension = ""
            fileSize = 0
            createdAt = .now
            updatedAt = .now
            readingProgress = 0
            lastPage = 1
            pageCount = 1
            isFavorite = false
            tags = []
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

        init() {
            id = UUID()
            title = ""
            body = ""
            createdAt = .now
            updatedAt = .now
            isPinned = false
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

        init() {
            id = UUID()
            title = ""
            storedRelativePath = ""
            duration = 0
            createdAt = .now
            updatedAt = .now
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

        init() {
            id = "default"
            firstName = "Alya"
            isDemoWorkspace = false
            flashcardsDue = 0
            flashcardCourseCount = 0
            createdAt = .now
            updatedAt = .now
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

        init() {
            id = UUID()
            title = ""
            deckDescription = ""
            colorIdentifier = "blueViolet"
            symbolName = "rectangle.stack.fill"
            createdAt = .now
            updatedAt = .now
            isArchived = false
            cards = []
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
        var reviewState: FlashcardReviewState
        var deck: StudyDeck?

        init() {
            id = UUID()
            front = ""
            back = ""
            tags = []
            position = 0
            createdAt = .now
            updatedAt = .now
            reviewState = FlashcardReviewState()
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

        init() {
            id = UUID()
            reviewedAt = .now
            rating = .good
            previousDueDate = .now
            nextDueDate = .now
            responseDuration = 0
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

        init() {
            id = UUID()
            title = ""
            quizDescription = ""
            mode = .practice
            createdAt = .now
            updatedAt = .now
            isArchived = false
            questions = []
            attempts = []
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

        init() {
            id = UUID()
            prompt = ""
            type = .multipleChoice
            choices = []
            correctAnswers = []
            explanation = ""
            points = 1
            position = 0
            tags = []
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

        init() {
            id = UUID()
            startedAt = .now
            score = 0
            maximumScore = 0
            answers = []
            duration = 0
            isCompleted = false
        }
    }
}

// Version 3 was a no-op snapshot with the same model checksum as V2, so it is
// intentionally skipped. SwiftData rejects duplicate checksums in a migration
// plan. The effective app plan migrates lightweight stores directly to V10.
enum UniSaverSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AcademicYear.self,
            Semester.self,
            Course.self,
            Chapter.self,
            ClassSession.self,
            AcademicTask.self,
            Exam.self,
            StudyBlock.self,
            ReadingProgress.self,
            AcademicResource.self,
            StudyNote.self,
            CourseRecording.self,
            AppWorkspace.self,
            StudyDeck.self,
            Flashcard.self,
            FlashcardReviewEvent.self,
            Quiz.self,
            QuizQuestion.self,
            QuizAttempt.self,
            UnderstandingPracticeAttempt.self
        ]
    }
}

enum UniSaverSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AcademicYear.self,
            Semester.self,
            Course.self,
            Chapter.self,
            ClassSession.self,
            AcademicTask.self,
            Exam.self,
            StudyBlock.self,
            ReadingProgress.self,
            AcademicResource.self,
            StudyNote.self,
            CourseRecording.self,
            AppWorkspace.self,
            StudyDeck.self,
            Flashcard.self,
            FlashcardReviewEvent.self,
            Quiz.self,
            QuizQuestion.self,
            QuizAttempt.self,
            UnderstandingPracticeAttempt.self,
            LibraryFolder.self,
            LibraryItem.self
        ]
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

        init() {
            id = UUID()
            title = ""
            storedRelativePath = ""
            duration = 0
            createdAt = .now
            updatedAt = .now
        }
    }
}

enum UniSaverSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AcademicYear.self,
            Semester.self,
            Course.self,
            Chapter.self,
            ClassSession.self,
            AcademicTask.self,
            Exam.self,
            StudyBlock.self,
            ReadingProgress.self,
            AcademicResource.self,
            StudyNote.self,
            CourseRecording.self,
            AppWorkspace.self,
            StudyDeck.self,
            Flashcard.self,
            FlashcardReviewEvent.self,
            Quiz.self,
            QuizQuestion.self,
            QuizAttempt.self,
            UnderstandingPracticeAttempt.self,
            LibraryFolder.self,
            LibraryItem.self
        ]
    }
}

// Version 6 had the same model graph as V5. Keeping both in
// SchemaMigrationPlan.schemas makes SwiftData abort with "Duplicate version
// checksums detected". Existing stores observed in the wild are stamped 6.0.0
// for this checksum; both definitions remain historical diagnostics only.

enum UniSaverSchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AcademicYear.self,
            Semester.self,
            Course.self,
            Chapter.self,
            ClassSession.self,
            AcademicTask.self,
            Exam.self,
            StudyBlock.self,
            ReadingProgress.self,
            AcademicResource.self,
            StudyNote.self,
            CourseRecording.self,
            AppWorkspace.self,
            StudyDeck.self,
            Flashcard.self,
            FlashcardReviewEvent.self,
            Quiz.self,
            QuizQuestion.self,
            QuizAttempt.self,
            UnderstandingPracticeAttempt.self,
            LibraryFolder.self,
            LibraryItem.self,
            ExternalCalendarEventLink.self
        ]
    }
}

enum UniSaverSchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AcademicYear.self,
            Semester.self,
            Course.self,
            Chapter.self,
            ClassSession.self,
            AcademicTask.self,
            Exam.self,
            StudyBlock.self,
            ReadingProgress.self,
            AcademicResource.self,
            StudyNote.self,
            CourseRecording.self,
            AppWorkspace.self,
            StudyDeck.self,
            Flashcard.self,
            FlashcardReviewEvent.self,
            Quiz.self,
            QuizQuestion.self,
            QuizAttempt.self,
            UnderstandingPracticeAttempt.self,
            LibraryFolder.self,
            LibraryItem.self,
            ExternalCalendarEventLink.self,
            ExternalLearningActivity.self
        ]
    }
}

enum UniSaverSchemaV9: VersionedSchema {
    static var versionIdentifier = Schema.Version(9, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AcademicYear.self,
            Semester.self,
            Course.self,
            Chapter.self,
            ClassSession.self,
            AcademicTask.self,
            Exam.self,
            StudyBlock.self,
            ReadingProgress.self,
            AcademicResource.self,
            StudyNote.self,
            CourseRecording.self,
            AppWorkspace.self,
            StudyDeck.self,
            Flashcard.self,
            FlashcardReviewEvent.self,
            Quiz.self,
            QuizQuestion.self,
            QuizAttempt.self,
            UnderstandingPracticeAttempt.self,
            LibraryFolder.self,
            LibraryItem.self,
            ExternalCalendarEventLink.self,
            ExternalLearningActivity.self,
            MathExercise.self,
            MathExerciseAttempt.self
        ]
    }
}

enum UniSaverSchemaV10: VersionedSchema {
    static var versionIdentifier = Schema.Version(10, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AcademicYear.self,
            Semester.self,
            Course.self,
            Chapter.self,
            ClassSession.self,
            AcademicTask.self,
            Exam.self,
            StudyBlock.self,
            ReadingProgress.self,
            AcademicResource.self,
            StudyNote.self,
            CourseRecording.self,
            AppWorkspace.self,
            StudyDeck.self,
            Flashcard.self,
            FlashcardReviewEvent.self,
            Quiz.self,
            QuizQuestion.self,
            QuizAttempt.self,
            UnderstandingPracticeAttempt.self,
            LibraryFolder.self,
            LibraryItem.self,
            ExternalCalendarEventLink.self,
            ExternalLearningActivity.self,
            MathExercise.self,
            MathExerciseAttempt.self,
            EssayAssignment.self,
            EssaySource.self,
            EssaySubmission.self
        ]
    }
}

enum PersistenceController {
    static let schema = Schema(versionedSchema: UniSaverSchemaV10.self)

    static func appContainer() throws -> ModelContainer {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--exam-lab-validation") {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        if arguments.contains("--p0-validation"), let index = arguments.firstIndex(of: "--p0-test-store"), arguments.indices.contains(index + 1) {
            // Use this app's own sandbox temporary directory. The runner cannot grant file access.
            guard let id = UUID(uuidString: arguments[index + 1]) else { throw CocoaError(.fileWriteInvalidFileName) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("UniSaver-P0-" + id.uuidString + ".store")
            let configuration = ModelConfiguration("P0Validation", schema: schema, url: url)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        #endif
        let configuration = ModelConfiguration("UniSaverStore", schema: schema)
        let container = try ModelContainer(for: schema, migrationPlan: UniSaverMigrationPlan.self, configurations: [configuration])
        try repairSessionTypes(in: container.mainContext)
        return container
    }

    static func previewContainer() -> ModelContainer {
        let configuration = ModelConfiguration("UniSaverPreviewStore", schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, migrationPlan: UniSaverMigrationPlan.self, configurations: [configuration])
            PreviewDataFactory.seed(container.mainContext)
            try repairSessionTypes(in: container.mainContext)
            return container
        } catch {
            fatalError("Unable to initialize preview SwiftData store: \(error.localizedDescription)")
        }
    }

    static func repairSessionTypes(in context: ModelContext) throws {
        let sessions = try context.fetch(FetchDescriptor<ClassSession>())
        var didRepair = false
        for session in sessions {
            guard let rawValue = session.sessionTypeRawValue,
                  ClassSessionType(rawValue: rawValue) != nil else {
                session.sessionTypeRawValue = ClassSessionType.lecture.rawValue
                didRepair = true
                continue
            }
        }
        if didRepair {
            try context.save()
        }
    }
}
