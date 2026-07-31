import SwiftData
import SwiftUI

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var editingSession: ClassSession?
    @State private var deleteSession: ClassSession?
    @State private var showsDeleteConfirmation = false

    private var sessions: [ClassSession] {
        course.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        List {
            if sessions.isEmpty {
                EmptyStateView(title: "No sessions", message: "Add a dated session to make Today and this workspace actionable.", systemImage: "calendar.badge.plus", actionTitle: "New Session") {
                    quickAddTarget = .session(course, nil)
                }
            } else {
                ForEach(sessions) { session in
                    Button {
                        editingSession = session
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            deleteSession = session
                            showsDeleteConfirmation = true
                        }
                    }
                    .contextMenu {
                        Button("Edit") { editingSession = session }
                        Button("Advance Progress") {
                            session.progressStatus = session.progressStatus.advanced()
                            session.updatedAt = .now
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("New Session", systemImage: "plus") { quickAddTarget = .session(course, nil) }
            }
        }
        .sheet(item: $editingSession) { session in
            SessionFormView(course: course, session: session)
        }
        .confirmationDialog("Delete session?", isPresented: $showsDeleteConfirmation) {
            Button("Delete Session", role: .destructive) {
                if let deleteSession {
                    modelContext.delete(deleteSession)
                    self.deleteSession = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the session from Today and the course timeline.")
        }
    }
}
