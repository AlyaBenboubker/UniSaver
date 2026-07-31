import Foundation
import SwiftData

enum PersistenceController {
    static let schema = Schema([
        AcademicYear.self,
        Semester.self,
        Course.self,
        Chapter.self,
        ClassSession.self
    ])

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
