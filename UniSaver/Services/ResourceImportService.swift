import Foundation
import PDFKit
import SwiftData

struct ResourceImportDraft {
    var fileURL: URL?
    var title: String
    var resourceDescription: String
    var course: Course?
    var chapter: Chapter?
    var session: ClassSession?
    var tags: [String]

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ResourceImportValidation: Equatable {
    var fileError: String?
    var titleError: String?
    var courseError: String?
    var chapterError: String?
    var sessionError: String?

    var isValid: Bool {
        fileError == nil && titleError == nil && courseError == nil && chapterError == nil && sessionError == nil
    }

    static func validate(_ draft: ResourceImportDraft) -> ResourceImportValidation {
        var validation = ResourceImportValidation()
        if draft.fileURL == nil {
            validation.fileError = "Choose a file to import."
        }
        if draft.trimmedTitle.isEmpty {
            validation.titleError = "Enter a title."
        }
        if draft.course == nil {
            if draft.chapter != nil {
                validation.chapterError = "Choose a course before selecting a chapter."
            }
            if draft.session != nil {
                validation.sessionError = "Choose a course before selecting a session."
            }
            return validation
        }
        guard let course = draft.course else { return validation }
        if let chapter = draft.chapter, chapter.course?.id != course.id {
            validation.chapterError = "The selected chapter does not belong to this course."
        }
        if let session = draft.session {
            guard session.course?.id == course.id else {
                validation.sessionError = "The selected session is no longer available."
                return validation
            }
            if let chapter = draft.chapter, session.chapter?.id != chapter.id {
                validation.sessionError = "The selected session is no longer available."
            }
        }
        return validation
    }
}

enum ResourceImportSubmitError: LocalizedError {
    case invalid(ResourceImportValidation)
    case duplicate(UUID)

    var errorDescription: String? {
        switch self {
        case .invalid:
            "The resource form is incomplete."
        case .duplicate:
            "This file is already in your library."
        }
    }
}

enum ResourceImportService {
    @MainActor
    static func submit(
        draft: ResourceImportDraft,
        existingResources: [AcademicResource],
        modelContext: ModelContext,
        fileStore: AcademicFileStore,
        allowDuplicate: Bool = false
    ) throws -> AcademicResource {
        let validation = ResourceImportValidation.validate(draft)
        guard validation.isValid, let fileURL = draft.fileURL else {
            throw ResourceImportSubmitError.invalid(validation)
        }

        let sourceHash = try fileStore.fingerprint(for: fileURL)
        if !allowDuplicate,
           let duplicate = duplicateResource(hash: sourceHash, draft: draft, existingResources: existingResources) {
            throw ResourceImportSubmitError.duplicate(duplicate.id)
        }

        let stored = try fileStore.importFile(from: fileURL)
        var insertedResource: AcademicResource?
        do {
            let pageCount = stored.resourceKind == .pdf ? (PDFDocument(url: try fileStore.url(for: stored.storedRelativePath))?.pageCount ?? 1) : 1
            let resource = AcademicResource(
                title: draft.trimmedTitle,
                resourceKind: stored.resourceKind,
                originalFileName: stored.originalFileName,
                resourceDescription: draft.resourceDescription,
                storedRelativePath: stored.storedRelativePath,
                mimeType: stored.mimeType,
                fileExtension: stored.fileExtension,
                fileSize: stored.fileSize,
                contentHash: stored.contentHash,
                pageCount: pageCount,
                tags: draft.tags,
                course: draft.course,
                chapter: draft.chapter,
                session: draft.session
            )
            insertedResource = resource
            modelContext.insert(resource)
            try modelContext.save()
            return resource
        } catch {
            if let insertedResource {
                modelContext.delete(insertedResource)
            }
            try? fileStore.delete(relativePath: stored.storedRelativePath)
            throw error
        }
    }

    static func duplicateResource(hash: String, draft: ResourceImportDraft, existingResources: [AcademicResource]) -> AcademicResource? {
        existingResources.first { resource in
            resource.contentHash == hash &&
            resource.course?.id == draft.course?.id &&
            resource.chapter?.id == draft.chapter?.id &&
            resource.session?.id == draft.session?.id
        }
    }
}
