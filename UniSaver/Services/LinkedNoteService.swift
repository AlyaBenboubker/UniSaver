import Foundation
import SwiftData

enum LinkedNoteService {
    @MainActor
    static func note(for resource: AcademicResource, existingNotes: [StudyNote], in context: ModelContext) throws -> StudyNote {
        if let existing = existingNotes.first(where: { $0.resource?.id == resource.id }) {
            return existing
        }
        let note = StudyNote(
            title: "Notes — \(resource.title)",
            body: "",
            course: resource.course,
            chapter: resource.chapter,
            session: resource.session,
            resource: resource
        )
        context.insert(note)
        do {
            try context.save()
            return note
        } catch {
            context.delete(note)
            throw error
        }
    }
}
