import Foundation
import SwiftData

enum RecordingPersistenceService {
    @discardableResult
    static func createRecording(
        title: String,
        savedRecording: SavedAcademicRecording,
        course: Course?,
        chapter: Chapter?,
        session: ClassSession?,
        note: StudyNote?,
        source: CourseRecordingSource = .recorded,
        languageIdentifier: String = Locale.current.identifier,
        in context: ModelContext,
        fileStore: AcademicFileStore = AcademicFileStore()
    ) throws -> CourseRecording {
        let recording = CourseRecording(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Course recording" : title.trimmingCharacters(in: .whitespacesAndNewlines),
            storedRelativePath: savedRecording.storedRelativePath,
            duration: savedRecording.duration,
            course: course,
            chapter: chapter,
            session: session,
            note: note
        )
        context.insert(recording)
        do {
            try context.save()
            return recording
        } catch {
            try? fileStore.delete(relativePath: savedRecording.storedRelativePath)
            throw error
        }
    }

    static func deleteRecording(_ recording: CourseRecording, in context: ModelContext, fileStore: AcademicFileStore = AcademicFileStore()) {
        try? fileStore.delete(relativePath: recording.storedRelativePath)
        context.delete(recording)
        try? context.save()
    }
}
