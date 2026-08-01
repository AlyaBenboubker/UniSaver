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

    static func resetWorkspaceChoice(in context: ModelContext) {
        deleteAll(AppWorkspace.self, in: context)
        try? context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        if let models = try? context.fetch(FetchDescriptor<T>()) {
            models.forEach(context.delete)
        }
    }
}
