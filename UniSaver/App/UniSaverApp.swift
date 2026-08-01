import SwiftData
import SwiftUI

@main
struct UniSaverApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try PersistenceController.appContainer()
        } catch {
            fatalError("Unable to initialize UniSaver SwiftData store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
        .commands {
            CommandMenu("UniSaver") {
                Button("New Course") {
                    NotificationCenter.default.post(name: .openQuickAddCourse, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                Divider()
                Button("Today") {
                    NotificationCenter.default.post(name: .selectAppSection, object: AppSection.today)
                }
                .keyboardShortcut("1", modifiers: [.command])
                Button("Classes") {
                    NotificationCenter.default.post(name: .selectAppSection, object: AppSection.classes)
                }
                .keyboardShortcut("2", modifiers: [.command])
                Button("Study") {
                    NotificationCenter.default.post(name: .selectAppSection, object: AppSection.study)
                }
                .keyboardShortcut("3", modifiers: [.command])
            }
            CommandMenu("Workspace") {
                Button("Reset Workspace Choice") {
                    NotificationCenter.default.post(name: .resetWorkspaceChoice, object: nil)
                }
                Button("Load Demo Workspace") {
                    NotificationCenter.default.post(name: .loadDemoWorkspace, object: nil)
                }
                Button("Reset Demo Data") {
                    NotificationCenter.default.post(name: .resetDemoData, object: nil)
                }
                Button("Start Empty Workspace") {
                    NotificationCenter.default.post(name: .startEmptyWorkspace, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let openQuickAddCourse = Notification.Name("openQuickAddCourse")
    static let selectAppSection = Notification.Name("selectAppSection")
    static let loadDemoWorkspace = Notification.Name("loadDemoWorkspace")
    static let resetDemoData = Notification.Name("resetDemoData")
    static let resetWorkspaceChoice = Notification.Name("resetWorkspaceChoice")
    static let startEmptyWorkspace = Notification.Name("startEmptyWorkspace")
    static let courseCreated = Notification.Name("courseCreated")
    static let openPlannerTasks = Notification.Name("openPlannerTasks")
}
