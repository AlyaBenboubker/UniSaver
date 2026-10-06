import Foundation
import SwiftData

enum DemoWorkspaceService {
    static func startEmptyWorkspace(in context: ModelContext) {
        if (try? context.fetch(FetchDescriptor<AppWorkspace>()).isEmpty) == false {
            return
        }
        let workspace = AppWorkspace(firstName: "Alya", isDemoWorkspace: false)
        context.insert(workspace)
        try? context.save()
    }

    static func loadDemoWorkspace(in context: ModelContext) {
        if (try? context.fetch(FetchDescriptor<AppWorkspace>()).contains(where: { $0.isDemoWorkspace })) == true {
            return
        }
        resetWorkspace(in: context)
        PreviewDataFactory.seed(context, includeDashboardDemo: true)
    }

    static func resetWorkspace(in context: ModelContext) {
        deleteAll(LibraryItem.self, in: context)
        deleteAll(LibraryFolder.self, in: context)
        deleteAll(UnderstandingPracticeAttempt.self, in: context)
        deleteAll(QuizAttempt.self, in: context)
        deleteAll(QuizQuestion.self, in: context)
        deleteAll(Quiz.self, in: context)
        deleteAll(FlashcardReviewEvent.self, in: context)
        deleteAll(Flashcard.self, in: context)
        deleteAll(StudyDeck.self, in: context)
        deleteAll(ClassSession.self, in: context)
        deleteAll(CourseRecording.self, in: context)
        deleteAll(StudyNote.self, in: context)
        deleteAll(AcademicResource.self, in: context)
        deleteAll(StudyBlock.self, in: context)
        deleteAll(AcademicTask.self, in: context)
        deleteAll(Exam.self, in: context)
        deleteAll(ReadingProgress.self, in: context)
        deleteAll(Chapter.self, in: context)
        deleteAll(Course.self, in: context)
        deleteAll(Semester.self, in: context)
        deleteAll(AcademicYear.self, in: context)
        deleteAll(AppWorkspace.self, in: context)
        try? context.save()
    }

    static func resetWorkspaceThrowing(in context: ModelContext) throws {
        try deleteAllThrowing(LibraryItem.self, in: context)
        try deleteAllThrowing(LibraryFolder.self, in: context)
        try deleteAllThrowing(UnderstandingPracticeAttempt.self, in: context)
        try deleteAllThrowing(QuizAttempt.self, in: context)
        try deleteAllThrowing(QuizQuestion.self, in: context)
        try deleteAllThrowing(Quiz.self, in: context)
        try deleteAllThrowing(FlashcardReviewEvent.self, in: context)
        try deleteAllThrowing(Flashcard.self, in: context)
        try deleteAllThrowing(StudyDeck.self, in: context)
        try deleteAllThrowing(ClassSession.self, in: context)
        try deleteAllThrowing(CourseRecording.self, in: context)
        try deleteAllThrowing(StudyNote.self, in: context)
        try deleteAllThrowing(AcademicResource.self, in: context)
        try deleteAllThrowing(StudyBlock.self, in: context)
        try deleteAllThrowing(AcademicTask.self, in: context)
        try deleteAllThrowing(Exam.self, in: context)
        try deleteAllThrowing(ReadingProgress.self, in: context)
        try deleteAllThrowing(Chapter.self, in: context)
        try deleteAllThrowing(Course.self, in: context)
        try deleteAllThrowing(Semester.self, in: context)
        try deleteAllThrowing(AcademicYear.self, in: context)
        try deleteAllThrowing(AppWorkspace.self, in: context)
        try context.save()
    }

    static func resetWorkspaceChoice(in context: ModelContext) {
        deleteAll(AppWorkspace.self, in: context)
        try? context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        if let models = try? context.fetch(FetchDescriptor<T>()) {
            models.forEach(context.delete)
        }
    }

    private static func deleteAllThrowing<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let models = try context.fetch(FetchDescriptor<T>())
        models.forEach(context.delete)
    }
}
