import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [AppWorkspace]
    @Query(sort: \Course.name) private var courses: [Course]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title.weight(.bold))
                    Text("Workspace controls for development and validation.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Workspace", systemImage: "rectangle.grid.2x2")
                        .font(.headline)

                    HStack {
                        metric("Workspace", workspaces.first?.isDemoWorkspace == true ? "Demo" : workspaces.isEmpty ? "Not chosen" : "Empty")
                        metric("Courses", "\(courses.count)")
                    }

                    HStack {
                        Button("Load Demo Workspace", systemImage: "sparkles") {
                            DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Reset Demo Data", systemImage: "arrow.clockwise") {
                            DemoWorkspaceService.resetWorkspace(in: modelContext)
                            DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                        }
                        .buttonStyle(.bordered)

                        Button("Start Empty Workspace", systemImage: "plus") {
                            DemoWorkspaceService.resetWorkspace(in: modelContext)
                            DemoWorkspaceService.startEmptyWorkspace(in: modelContext)
                        }
                        .buttonStyle(.bordered)

                        Button("Reset Workspace Choice", systemImage: "trash") {
                            DemoWorkspaceService.resetWorkspaceChoice(in: modelContext)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .deskCard()
            }
            .padding()
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .navigationTitle("Settings")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
    }
}
