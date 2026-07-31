import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var selection: AppSection? = .today
    @State private var quickAddTarget: QuickAddTarget?

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
            .navigationTitle("UniSaver")
        } detail: {
            NavigationStack {
                Group {
                    switch selection ?? .today {
                    case .today:
                        TodayView(quickAddTarget: $quickAddTarget)
                    case .classes:
                        ClassesView(quickAddTarget: $quickAddTarget)
                    case .study:
                        PlaceholderFeatureView(section: .study)
                    case .planner:
                        PlaceholderFeatureView(section: .planner)
                    case .progress:
                        PlaceholderFeatureView(section: .progress)
                    case .library:
                        PlaceholderFeatureView(section: .library)
                    }
                }
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            quickAddTarget = .course(nil)
                        } label: {
                            Label("Quick Add", systemImage: "plus")
                        }
                        .keyboardShortcut("n", modifiers: [.command])
                        .help("Quick Add")
                    }
                }
                .sheet(item: $quickAddTarget) { target in
                    QuickAddSheet(target: target)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openQuickAddCourse)) { _ in
                    quickAddTarget = .course(nil)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.previewContainer())
}
