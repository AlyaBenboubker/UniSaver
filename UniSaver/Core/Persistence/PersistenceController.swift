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
    static var schemas: [any VersionedSchema.Type] {
        [UniSaverSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum PersistenceController {
    static let schema = Schema(UniSaverSchemaV1.models)

    static func appContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration("UniSaverStore", schema: schema)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func previewContainer() -> ModelContainer {
        let configuration = ModelConfiguration("UniSaverPreviewStore", schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            PreviewDataFactory.seed(container.mainContext)
            return container
        } catch {
            fatalError("Unable to initialize preview SwiftData store: \(error.localizedDescription)")
        }
    }
}
