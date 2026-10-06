import SwiftData
import SwiftUI

private enum LibraryLocation: Hashable, Identifiable {
    case all
    case unfiled
    case folder(UUID)

    var id: String {
        switch self {
        case .all: "all"
        case .unfiled: "unfiled"
        case .folder(let id): id.uuidString
        }
    }
}

private struct LibraryDisplayItem: Identifiable, Hashable {
    let kind: LibraryItemKind
    let itemID: String
    let title: String
    let subtitle: String
    let courseID: UUID?
    let courseName: String?
    let updatedAt: Date

    var id: String { "\(kind.rawValue):\(itemID)" }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @Query(sort: \LibraryItem.updatedAt, order: .reverse) private var libraryItems: [LibraryItem]
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]
    @Query(sort: \Quiz.updatedAt, order: .reverse) private var quizzes: [Quiz]
    @Query(sort: \StudyDeck.updatedAt, order: .reverse) private var decks: [StudyDeck]
    @Query(sort: \Flashcard.updatedAt, order: .reverse) private var flashcards: [Flashcard]
    @Query(sort: \UnderstandingPracticeAttempt.updatedAt, order: .reverse) private var practiceAttempts: [UnderstandingPracticeAttempt]
    @Query(sort: \Course.name) private var courses: [Course]

    @State private var selectedLocation: LibraryLocation = .all
    @State private var searchText = ""
    @State private var selectedKind: LibraryItemKind?
    @State private var selectedCourseID: UUID?
    @State private var importing = false
    @State private var selectedItem: LibraryDisplayItem?
    @State private var contextItem: LibraryDisplayItem?
    @State private var folderName = ""
    @State private var folderToRename: LibraryFolder?
    @State private var folderToDelete: LibraryFolder?
    @State private var confirmationMessage: String?

    private var allDisplayItems: [LibraryDisplayItem] {
        var items: [LibraryDisplayItem] = []
        items += notes.map {
            LibraryDisplayItem(
                kind: .note,
                itemID: $0.id.uuidString,
                title: $0.title.isEmpty ? "Untitled note" : $0.title,
                subtitle: contextText(course: $0.course, chapter: $0.chapter, session: $0.session),
                courseID: $0.course?.id,
                courseName: $0.course?.name,
                updatedAt: $0.updatedAt
            )
        }
        items += resources.map {
            LibraryDisplayItem(
                kind: .resource,
                itemID: $0.id.uuidString,
                title: $0.title,
                subtitle: [$0.effectiveResourceKindTitle, contextText(course: $0.course, chapter: $0.chapter, session: $0.session)].filter { !$0.isEmpty }.joined(separator: " · "),
                courseID: $0.course?.id,
                courseName: $0.course?.name,
                updatedAt: $0.updatedAt
            )
        }
        items += recordings.map {
            LibraryDisplayItem(
                kind: .recording,
                itemID: $0.id.uuidString,
                title: $0.title,
                subtitle: contextText(course: $0.course, chapter: $0.chapter, session: $0.session),
                courseID: $0.course?.id,
                courseName: $0.course?.name,
                updatedAt: $0.updatedAt
            )
        }
        items += quizzes.filter { !$0.isArchived }.map {
            LibraryDisplayItem(
                kind: .quiz,
                itemID: $0.id.uuidString,
                title: $0.title,
                subtitle: contextText(course: $0.course, chapter: $0.chapter, session: $0.session),
                courseID: $0.course?.id,
                courseName: $0.course?.name,
                updatedAt: $0.updatedAt
            )
        }
        items += decks.filter { !$0.isArchived }.map {
            LibraryDisplayItem(
                kind: .studyDeck,
                itemID: $0.id.uuidString,
                title: $0.title,
                subtitle: contextText(course: $0.course, chapter: $0.chapter, session: $0.session),
                courseID: $0.course?.id,
                courseName: $0.course?.name,
                updatedAt: $0.updatedAt
            )
        }
        items += flashcards.map {
            LibraryDisplayItem(
                kind: .flashcard,
                itemID: $0.id.uuidString,
                title: $0.front.isEmpty ? "Untitled flashcard" : $0.front,
                subtitle: $0.deck?.title ?? "Loose flashcard",
                courseID: $0.deck?.course?.id,
                courseName: $0.deck?.course?.name,
                updatedAt: $0.updatedAt
            )
        }
        items += practiceAttempts.map {
            LibraryDisplayItem(
                kind: .understandingPractice,
                itemID: $0.id.uuidString,
                title: $0.exercisePrompt.isEmpty ? $0.subject : $0.exercisePrompt,
                subtitle: [$0.subject, $0.autonomousResult.title].filter { !$0.isEmpty }.joined(separator: " · "),
                courseID: $0.course?.id,
                courseName: $0.course?.name,
                updatedAt: $0.updatedAt
            )
        }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var filteredItems: [LibraryDisplayItem] {
        allDisplayItems.filter { item in
            let matchesLocation: Bool
            switch selectedLocation {
            case .all:
                matchesLocation = true
            case .unfiled:
                matchesLocation = folder(for: item) == nil
            case .folder(let folderID):
                matchesLocation = folder(for: item)?.id == folderID
            }

            let matchesSearch = searchText.isEmpty
                || item.title.localizedCaseInsensitiveContains(searchText)
                || item.courseName?.localizedCaseInsensitiveContains(searchText) == true
            let matchesKind = selectedKind == nil || item.kind == selectedKind
            let matchesCourse = selectedCourseID == nil || item.courseID == selectedCourseID
            return matchesLocation && matchesSearch && matchesKind && matchesCourse
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if proxy.size.width < 780 {
                    VStack(spacing: 0) {
                        controls
                        itemList
                    }
                } else {
                    HStack(spacing: 0) {
                        sidebar
                            .frame(width: 250)
                        Divider()
                        VStack(spacing: 0) {
                            controls
                            itemList
                        }
                    }
                }
            }
            .background(StudyDeskTheme.backgroundPrimary)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        folderName = uniqueFolderName()
                        folderToRename = LibraryFolder(name: folderName)
                    }
                    Button("Import File", systemImage: "square.and.arrow.down") {
                        importing = true
                    }
                }
            }
            .sheet(isPresented: $importing) {
                ResourceImportView { resource in
                    selectedItem = LibraryDisplayItem(
                        kind: .resource,
                        itemID: resource.id.uuidString,
                        title: resource.title,
                        subtitle: resource.effectiveResourceKindTitle,
                        courseID: resource.course?.id,
                        courseName: resource.course?.name,
                        updatedAt: resource.updatedAt
                    )
                    confirmationMessage = "Resource imported"
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                destination(for: item)
            }
            .sheet(item: $contextItem) { item in
                LibraryAcademicContextEditorView(item: item)
            }
            .alert("Folder name", isPresented: Binding(
                get: { folderToRename != nil },
                set: { if !$0 { folderToRename = nil } }
            )) {
                TextField("Folder name", text: $folderName)
                Button("Save") {
                    saveFolderName()
                }
                Button("Cancel", role: .cancel) {
                    folderToRename = nil
                }
            } message: {
                Text("Folders classify Library items without moving or duplicating their underlying content.")
            }
            .confirmationDialog("Delete folder?", isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            )) {
                Button("Delete Folder", role: .destructive) {
                    deleteSelectedFolder()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The folder will be deleted. Its contents will be kept and shown in Unfiled.")
            }
            .overlay(alignment: .bottom) {
                if let confirmationMessage {
                    Text(confirmationMessage)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 18)
                        .task {
                            try? await Task.sleep(for: .seconds(2))
                            self.confirmationMessage = nil
                        }
                }
            }
            .onAppear {
                applyRequestedCourseFilter()
            }
            .onChange(of: navigation.libraryCourseID) { _, _ in
                applyRequestedCourseFilter()
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedLocation) {
            Section {
                Label("All Items", systemImage: "tray.full")
                    .tag(LibraryLocation.all)
                Label("Unfiled", systemImage: "tray")
                    .tag(LibraryLocation.unfiled)
            }
            Section("Folders") {
                ForEach(folders) { folder in
                    Label(folder.name, systemImage: "folder")
                        .tag(LibraryLocation.folder(folder.id))
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                folderName = folder.name
                                folderToRename = folder
                            }
                            Button("Delete Folder", systemImage: "trash", role: .destructive) {
                                folderToDelete = folder
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                searchField
                Picker("Type", selection: $selectedKind) {
                    Text("All Types").tag(LibraryItemKind?.none)
                    ForEach(LibraryItemKind.allCases) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                .frame(maxWidth: 190)
                Picker("Course", selection: $selectedCourseID) {
                    Text("All Courses").tag(UUID?.none)
                    ForEach(courses.filter { !$0.isArchived }) { course in
                        Text(course.name).tag(Optional(course.id))
                    }
                }
                .frame(maxWidth: 220)
            }
            if selectedLocation == .all || selectedLocation == .unfiled {
                compactLocationPicker
            }
        }
        .padding()
        .background(StudyDeskTheme.surfacePrimary)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search title or course", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(StudyDeskTheme.backgroundPrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var compactLocationPicker: some View {
        Picker("Location", selection: $selectedLocation) {
            Text("All Items").tag(LibraryLocation.all)
            Text("Unfiled").tag(LibraryLocation.unfiled)
            ForEach(folders) { folder in
                Text(folder.name).tag(LibraryLocation.folder(folder.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var itemList: some View {
        List {
            if filteredItems.isEmpty {
                EmptyStateView(
                    title: "No library items",
                    message: "Notes, files, recordings, quizzes, flashcards, and exercises appear here from the same data used in courses and Study.",
                    systemImage: "folder"
                )
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(filteredItems) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            LibraryItemRow(item: item, folderName: folder(for: item)?.name)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Menu("Move to Folder", systemImage: "folder") {
                                Button("Unfiled") {
                                    assign(item, to: nil)
                                }
                                ForEach(folders) { folder in
                                    Button(folder.name) {
                                        assign(item, to: folder)
                                    }
                                }
                            }
                            if canEditAcademicContext(item) {
                                Button("Academic Context", systemImage: "books.vertical") {
                                    contextItem = item
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(filteredItems.count) item\(filteredItems.count == 1 ? "" : "s")")
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func destination(for item: LibraryDisplayItem) -> some View {
        switch item.kind {
        case .note:
            if let note = notes.first(where: { $0.id.uuidString == item.itemID }) {
                NoteEditorView(note: note)
            } else {
                missingItemView
            }
        case .resource:
            if let resource = resources.first(where: { $0.id.uuidString == item.itemID }) {
                ResourceDetailView(resource: resource)
            } else {
                missingItemView
            }
        case .recording:
            if let recording = recordings.first(where: { $0.id.uuidString == item.itemID }) {
                RecordingLibraryDetailView(recording: recording)
            } else {
                missingItemView
            }
        case .quiz:
            if let quiz = quizzes.first(where: { $0.id.uuidString == item.itemID }) {
                QuizPracticeView(quiz: quiz)
            } else {
                missingItemView
            }
        case .studyDeck:
            if let deck = decks.first(where: { $0.id.uuidString == item.itemID }) {
                DeckWorkspaceView(deck: deck)
            } else {
                missingItemView
            }
        case .flashcard:
            if let card = flashcards.first(where: { $0.id.uuidString == item.itemID }) {
                FlashcardEditView(card: card)
            } else {
                missingItemView
            }
        case .understandingPractice:
            if let attempt = practiceAttempts.first(where: { $0.id.uuidString == item.itemID }) {
                UnderstandingPracticeAttemptDetailView(attempt: attempt)
            } else {
                missingItemView
            }
        }
    }

    private var missingItemView: some View {
        EmptyStateView(title: "Item unavailable", message: "This Library entry points to content that is no longer available.", systemImage: "exclamationmark.triangle")
            .padding()
    }

    private func assignment(for item: LibraryDisplayItem) -> LibraryItem? {
        libraryItems.first { $0.itemKind == item.kind && $0.itemID == item.itemID }
    }

    private func folder(for item: LibraryDisplayItem) -> LibraryFolder? {
        assignment(for: item)?.folder
    }

    private func assign(_ item: LibraryDisplayItem, to folder: LibraryFolder?) {
        let libraryItem = assignment(for: item) ?? LibraryItem(itemKind: item.kind, itemID: item.itemID)
        if assignment(for: item) == nil {
            modelContext.insert(libraryItem)
        }
        libraryItem.folder = folder
        libraryItem.updatedAt = .now
        folder?.updatedAt = .now
        do {
            try modelContext.save()
            confirmationMessage = folder.map { "Moved to \($0.name)" } ?? "Moved to Unfiled"
        } catch {
            confirmationMessage = "Move failed: \(error.localizedDescription)"
        }
    }

    private func canEditAcademicContext(_ item: LibraryDisplayItem) -> Bool {
        item.kind != .flashcard
    }

    private func contextText(course: Course?, chapter: Chapter?, session: ClassSession?) -> String {
        [course?.name, chapter?.title, session?.title].compactMap { $0 }.joined(separator: " · ")
    }

    private func uniqueFolderName() -> String {
        var index = folders.count + 1
        var name = "New Folder"
        while folders.contains(where: { $0.name == name }) {
            index += 1
            name = "New Folder \(index)"
        }
        return name
    }

    private func saveFolderName() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            folderToRename = nil
            return
        }
        if let folderToRename, folders.contains(where: { $0.id == folderToRename.id }) {
            folderToRename.name = trimmed
            folderToRename.updatedAt = .now
        } else {
            let folder = LibraryFolder(name: trimmed)
            modelContext.insert(folder)
            selectedLocation = .folder(folder.id)
        }
        do {
            try modelContext.save()
        } catch {
            confirmationMessage = "Folder save failed: \(error.localizedDescription)"
        }
        folderToRename = nil
    }

    private func deleteSelectedFolder() {
        guard let folderToDelete else { return }
        folderToDelete.items.forEach { item in
            item.folder = nil
            item.updatedAt = .now
        }
        if selectedLocation == .folder(folderToDelete.id) {
            selectedLocation = .unfiled
        }
        modelContext.delete(folderToDelete)
        do {
            try modelContext.save()
            confirmationMessage = "Folder deleted. Contents kept in Unfiled."
        } catch {
            confirmationMessage = "Folder deletion failed: \(error.localizedDescription)"
        }
        self.folderToDelete = nil
    }

    private func applyRequestedCourseFilter() {
        guard let courseID = navigation.libraryCourseID else { return }
        selectedCourseID = courseID
        selectedLocation = .all
    }
}

private struct LibraryItemRow: View {
    let item: LibraryDisplayItem
    let folderName: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(StudyDeskTheme.accentPrimary, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.subtitle.isEmpty ? "No academic context" : item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.kind.singularTitle)
                    .font(.caption.weight(.semibold))
                Text(folderName ?? "Unfiled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct LibraryAcademicContextEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: LibraryDisplayItem
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]
    @Query(sort: \Quiz.updatedAt, order: .reverse) private var quizzes: [Quiz]
    @Query(sort: \StudyDeck.updatedAt, order: .reverse) private var decks: [StudyDeck]
    @Query(sort: \UnderstandingPracticeAttempt.updatedAt, order: .reverse) private var practiceAttempts: [UnderstandingPracticeAttempt]
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var selectedSessionID: UUID?
    @State private var errorMessage: String?

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

    private var supportsChapterAndSession: Bool {
        switch item.kind {
        case .note, .resource, .recording, .quiz, .studyDeck:
            true
        case .understandingPractice, .flashcard:
            false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    Picker("Course", selection: $selectedCourseID) {
                        Text("No course").tag(UUID?.none)
                        ForEach(courses.filter { !$0.isArchived }) { course in
                            Text(course.name).tag(Optional(course.id))
                        }
                    }
                }
                if supportsChapterAndSession {
                    Section("Chapter and Session") {
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
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Academic Context")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: loadCurrentContext)
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

    private func loadCurrentContext() {
        switch item.kind {
        case .note:
            let model = notes.first { $0.id.uuidString == item.itemID }
            selectedCourseID = model?.course?.id
            selectedChapterID = model?.chapter?.id
            selectedSessionID = model?.session?.id
        case .resource:
            let model = resources.first { $0.id.uuidString == item.itemID }
            selectedCourseID = model?.course?.id
            selectedChapterID = model?.chapter?.id
            selectedSessionID = model?.session?.id
        case .recording:
            let model = recordings.first { $0.id.uuidString == item.itemID }
            selectedCourseID = model?.course?.id
            selectedChapterID = model?.chapter?.id
            selectedSessionID = model?.session?.id
        case .quiz:
            let model = quizzes.first { $0.id.uuidString == item.itemID }
            selectedCourseID = model?.course?.id
            selectedChapterID = model?.chapter?.id
            selectedSessionID = model?.session?.id
        case .studyDeck:
            let model = decks.first { $0.id.uuidString == item.itemID }
            selectedCourseID = model?.course?.id
            selectedChapterID = model?.chapter?.id
            selectedSessionID = model?.session?.id
        case .understandingPractice:
            selectedCourseID = practiceAttempts.first { $0.id.uuidString == item.itemID }?.course?.id
        case .flashcard:
            break
        }
    }

    private func save() {
        let course = selectedCourse
        let chapter = supportsChapterAndSession ? chapters.first { $0.id == selectedChapterID } : nil
        let session = supportsChapterAndSession ? sessions.first { $0.id == selectedSessionID } : nil
        switch item.kind {
        case .note:
            let model = notes.first { $0.id.uuidString == item.itemID }
            model?.course = course
            model?.chapter = chapter
            model?.session = session
            model?.updatedAt = .now
        case .resource:
            let model = resources.first { $0.id.uuidString == item.itemID }
            model?.course = course
            model?.chapter = chapter
            model?.session = session
            model?.updatedAt = .now
        case .recording:
            let model = recordings.first { $0.id.uuidString == item.itemID }
            model?.course = course
            model?.chapter = chapter
            model?.session = session
            model?.updatedAt = .now
        case .quiz:
            let model = quizzes.first { $0.id.uuidString == item.itemID }
            model?.course = course
            model?.chapter = chapter
            model?.session = session
            model?.updatedAt = .now
        case .studyDeck:
            let model = decks.first { $0.id.uuidString == item.itemID }
            model?.course = course
            model?.chapter = chapter
            model?.session = session
            model?.updatedAt = .now
        case .understandingPractice:
            let model = practiceAttempts.first { $0.id.uuidString == item.itemID }
            model?.course = course
            model?.updatedAt = .now
        case .flashcard:
            break
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RecordingLibraryDetailView: View {
    @Bindable var recording: CourseRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(recording.title, systemImage: "waveform")
                .font(.title2.weight(.bold))
            Text(nonEmpty([recording.course?.name, recording.chapter?.title, recording.session?.title].compactMap { $0 }.joined(separator: " · ")) ?? "No academic context")
                .foregroundStyle(.secondary)
            Text("Duration \(recording.duration, format: .number.precision(.fractionLength(0))) seconds")
                .font(.callout.monospacedDigit())
            if let notes = recording.notes, !notes.isEmpty {
                Text(notes)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
            }
            RecordingTranscriptEditor(recording: recording)
            Spacer()
        }
        .padding()
        .navigationTitle("Recording")
        .background(StudyDeskTheme.backgroundPrimary)
    }

    private func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

private struct UnderstandingPracticeAttemptDetailView: View {
    let attempt: UnderstandingPracticeAttempt

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(attempt.subject, systemImage: "brain.head.profile")
                    .font(.title2.weight(.bold))
                Text(attempt.exercisePrompt)
                    .font(.headline)
                LabeledContent("Help used", value: attempt.helpLevelUsed.title)
                LabeledContent("Autonomous result", value: attempt.autonomousResult.title)
                if !attempt.studentAttempt.isEmpty {
                    section("Student attempt", attempt.studentAttempt)
                }
                if !attempt.transferQuestion.isEmpty {
                    section("Transfer question", attempt.transferQuestion)
                }
                if !attempt.transferAnswer.isEmpty {
                    section("Transfer answer", attempt.transferAnswer)
                }
            }
            .padding()
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Exercise")
        .background(StudyDeskTheme.backgroundPrimary)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
    }
}
