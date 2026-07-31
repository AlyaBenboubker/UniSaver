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
            }
        }
    }
}

extension Notification.Name {
    static let openQuickAddCourse = Notification.Name("openQuickAddCourse")
}
