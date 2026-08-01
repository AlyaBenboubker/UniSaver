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
                    NavigationLink {
                        SessionDetailView(session: session, quickAddTarget: $quickAddTarget)
                    } label: {
                        SessionRow(session: session)
                    }
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
                            try? modelContext.save()
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
                    try? modelContext.save()
                    self.deleteSession = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the session from Today and the course timeline.")
        }
    }
}

struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: ClassSession
    @Binding var quickAddTarget: QuickAddTarget?
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]
    @State private var editingSession = false
    @State private var deleteConfirmation = false

    private var linkedResources: [AcademicResource] {
        resources.filter { $0.session?.id == session.id }
    }

    private var linkedNotes: [StudyNote] {
        notes.filter { $0.session?.id == session.id }
    }

    private var linkedRecordings: [CourseRecording] {
        recordings.filter { $0.session?.id == session.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.course?.name ?? "Session")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.title)
                        .font(.title2.weight(.bold))
                    Text("\(UniDateFormatters.dayMonth.string(from: session.date)) · \(UniDateFormatters.interval(session.startTime, session.endTime))")
                    if let room = session.room {
                        Label(room, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                    }
                    ProgressMeter(value: session.progressStatus.structuralProgress)
                }
                .padding()
                .deskCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Linked content")
                        .font(.headline)
                    if linkedResources.isEmpty && linkedNotes.isEmpty && linkedRecordings.isEmpty {
                        Text("No resources, notes, or recordings linked to this session yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(linkedResources.prefix(4)) { ResourceRow(resource: $0) }
                        ForEach(linkedNotes.prefix(4)) { Label($0.title, systemImage: "note.text") }
                        ForEach(linkedRecordings.prefix(4)) { Label($0.title, systemImage: "waveform") }
                    }
                    HStack {
                        Button("Import", systemImage: "square.and.arrow.down") {
                            quickAddTarget = .resource(session.course, session.chapter, session)
                        }
                        Button("New Note", systemImage: "note.text") {
                            quickAddTarget = .note(session.course, session.chapter, session, nil)
                        }
                        Button("Record", systemImage: "waveform") {
                            quickAddTarget = .recording(session.course, session.chapter, session)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .deskCard()
            }
            .padding()
        }
        .navigationTitle(session.title)
        .toolbar {
            ToolbarItemGroup {
                Button("Edit", systemImage: "pencil") { editingSession = true }
                Button("Delete", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
            }
        }
        .sheet(isPresented: $editingSession) {
            if let course = session.course {
                SessionFormView(course: course, session: session)
            }
        }
        .confirmationDialog("Delete session?", isPresented: $deleteConfirmation) {
            Button("Delete Session", role: .destructive) {
                modelContext.delete(session)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
