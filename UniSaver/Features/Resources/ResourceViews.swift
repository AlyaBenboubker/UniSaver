import SwiftData
import SwiftUI

struct ResourceCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var allResources: [AcademicResource]
    let resources: [AcademicResource]
    let emptyTitle: String
    let importAction: () -> Void
    @State private var deleteResource: AcademicResource?
    @State private var openResource: AcademicResource?
    @State private var renameResource: AcademicResource?
    @State private var renameTitle = ""
    @State private var moveResource: AcademicResource?
    private let fileStore = AcademicFileStore()

    var body: some View {
        List {
            if resources.isEmpty {
                EmptyStateView(title: emptyTitle, message: "Import a PDF or file and link it to this workspace.", systemImage: "doc.richtext", actionTitle: "Import File", action: importAction)
            } else {
                ForEach(resources) { resource in
                    NavigationLink {
                        ResourceDetailView(resource: resource)
                    } label: {
                        ResourceRow(resource: resource)
                    }
                    .contextMenu {
                        Button("Open", systemImage: "arrow.right") {
                            openResource = resource
                        }
                        Button("Rename", systemImage: "pencil") {
                            renameResource = resource
                            renameTitle = resource.title
                        }
                        Button("Move/Change Academic Context", systemImage: "folder") {
                            moveResource = resource
                        }
                        Button(resource.isFavorite ? "Remove Favorite" : "Favorite", systemImage: "star") {
                            resource.isFavorite.toggle()
                            resource.updatedAt = .now
                            try? modelContext.save()
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteResource = resource
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $openResource) { resource in
            ResourceDetailView(resource: resource)
        }
        .sheet(item: $moveResource) { resource in
            ResourceContextEditorView(resource: resource)
        }
        .alert("Rename resource", isPresented: Binding(
            get: { renameResource != nil },
            set: { if !$0 { renameResource = nil } }
        )) {
            TextField("Title", text: $renameTitle)
            Button("Save") {
                let trimmed = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    renameResource?.title = trimmed
                    renameResource?.updatedAt = .now
                    try? modelContext.save()
                }
                renameResource = nil
            }
            Button("Cancel", role: .cancel) { renameResource = nil }
        }
        .confirmationDialog("Delete resource?", isPresented: Binding(
            get: { deleteResource != nil },
            set: { if !$0 { deleteResource = nil } }
        )) {
            Button("Delete Resource", role: .destructive) {
                if let deleteResource {
                    let sharedReferences = allResources.filter { $0.id != deleteResource.id && $0.storedRelativePath == deleteResource.storedRelativePath }
                    if sharedReferences.isEmpty {
                        try? fileStore.delete(relativePath: deleteResource.storedRelativePath)
                    }
                    modelContext.delete(deleteResource)
                    try? modelContext.save()
                    self.deleteResource = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the metadata and only the stored file linked to this resource.")
        }
    }
}

struct ResourceContextEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var resource: AcademicResource
    @Query(sort: \Course.name) private var courses: [Course]
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var selectedSessionID: UUID?

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    private var chapters: [Chapter] {
        selectedCourse?.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order } ?? []
    }

    private var sessions: [ClassSession] {
        let all = selectedCourse?.sessions.sorted { $0.startTime < $1.startTime } ?? []
        guard let selectedChapterID else { return all }
        return all.filter { $0.chapter?.id == selectedChapterID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Course", selection: $selectedCourseID) {
                    Text("No course").tag(UUID?.none)
                    ForEach(courses.filter { !$0.isArchived }) { course in
                        Text(course.name).tag(Optional(course.id))
                    }
                }
                Picker("Chapter", selection: $selectedChapterID) {
                    Text("No chapter").tag(UUID?.none)
                    ForEach(chapters) { chapter in
                        Text(chapter.title).tag(Optional(chapter.id))
                    }
                }
                Picker("Session", selection: $selectedSessionID) {
                    Text("No session").tag(UUID?.none)
                    ForEach(sessions) { session in
                        Text(session.title).tag(Optional(session.id))
                    }
                }
            }
            .navigationTitle("Academic Context")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        resource.course = selectedCourse
                        resource.chapter = chapters.first { $0.id == selectedChapterID }
                        resource.session = sessions.first { $0.id == selectedSessionID }
                        resource.updatedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedCourseID = resource.course?.id
                selectedChapterID = resource.chapter?.id
                selectedSessionID = resource.session?.id
            }
            .onChange(of: selectedCourseID) { _, _ in
                if !chapters.contains(where: { $0.id == selectedChapterID }) {
                    selectedChapterID = nil
                }
                if !sessions.contains(where: { $0.id == selectedSessionID }) {
                    selectedSessionID = nil
                }
            }
        }
    }
}

struct ResourceRow: View {
    let resource: AcademicResource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: resource.resourceKind.systemImage)
                .font(.title3)
                .foregroundStyle(CourseColor.color(for: resource.course?.colorIdentifier ?? "blueViolet"))
                .frame(width: 36, height: 36)
                .background(CourseColor.color(for: resource.course?.colorIdentifier ?? "blueViolet").opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(resource.title)
                    .font(.headline)
                    .lineLimit(1)
                Text([resource.course?.name, resource.chapter?.title, resource.session?.title].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if resource.resourceKind == .pdf {
                Text(resource.readingProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text(resource.resourceKind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ResourceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var resource: AcademicResource
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @State private var errorMessage: String?
    @State private var notesVisible = true
    @State private var selectedNote: StudyNote?
    @State private var isCreatingLinkedNote = false
    private let fileStore = AcademicFileStore()

    private var linkedNotes: [StudyNote] {
        notes.filter { $0.resource?.id == resource.id }
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if resource.resourceKind == .pdf {
                    if proxy.size.width > 820 && notesVisible {
                        HStack(spacing: 0) {
                            reader
                                .frame(minWidth: 420)
                            Divider()
                            notesPanel
                                .frame(width: max(320, min(420, proxy.size.width * 0.34)))
                        }
                    } else {
                        reader
                    }
                } else {
                    metadataView
                }
            }
        }
        .navigationTitle(resource.title)
        .toolbar {
            ToolbarItemGroup {
                if resource.resourceKind == .pdf {
                    Button(notesVisible ? "Hide Notes" : "Open Notes", systemImage: "note.text") {
                        notesVisible.toggle()
                    }
                }
                Button(resource.isFavorite ? "Unfavorite" : "Favorite", systemImage: resource.isFavorite ? "star.fill" : "star") {
                    resource.isFavorite.toggle()
                    resource.updatedAt = .now
                    try? modelContext.save()
                }
            }
        }
        .navigationDestination(item: $selectedNote) { note in
            NoteEditorView(note: note)
                .accessibilityIdentifier("noteEditor_\(note.id.uuidString)")
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .onAppear {
            resource.lastOpenedAt = .now
            try? modelContext.save()
        }
    }

    private var reader: some View {
        Group {
            if let url = try? fileStore.url(for: resource.storedRelativePath) {
                PDFKitReaderView(url: url, initialPage: resource.lastPage) { page, count in
                    resource.lastPage = page
                    resource.pageCount = count
                    resource.readingProgress = Double(page) / Double(max(count, 1))
                    resource.lastOpenedAt = .now
                    resource.updatedAt = .now
                    try? modelContext.save()
                }
            } else {
                EmptyStateView(title: "File missing", message: "The resource metadata exists, but the stored file cannot be found.", systemImage: "exclamationmark.triangle")
                    .padding()
            }
        }
    }

    private var notesPanel: some View {
        NavigationStack {
            NoteListView(notes: linkedNotes, emptyTitle: "No linked notes") {
                createLinkedNote()
            }
            .navigationTitle("Notes")
        }
    }

    private var metadataView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(resource.resourceKind.title, systemImage: resource.resourceKind.systemImage)
                .font(.title3.weight(.bold))
            Text(resource.originalFileName)
                .foregroundStyle(.secondary)
            Text("\(resource.fileSize) bytes")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                createOrOpenLinkedNote()
            } label: {
                if isCreatingLinkedNote {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Creating note...")
                    }
                } else {
                    Label(linkedNotes.first == nil ? "Create Linked Note" : "Open Linked Note", systemImage: "note.text")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCreatingLinkedNote)
            .accessibilityIdentifier(linkedNotes.first == nil ? "createLinkedNoteButton" : "openLinkedNoteButton")
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @discardableResult
    private func createLinkedNote() -> StudyNote {
        (try? LinkedNoteService.note(for: resource, existingNotes: notes, in: modelContext)) ?? StudyNote(title: "Notes — \(resource.title)", resource: resource)
    }

    @MainActor
    private func createOrOpenLinkedNote() {
        if let existing = linkedNotes.first {
            selectedNote = existing
            return
        }
        guard !isCreatingLinkedNote else { return }
        isCreatingLinkedNote = true
        errorMessage = nil
        do {
            let note = try LinkedNoteService.note(for: resource, existingNotes: notes, in: modelContext)
            selectedNote = note
        } catch {
            errorMessage = "The linked note could not be created."
        }
        isCreatingLinkedNote = false
    }
}
