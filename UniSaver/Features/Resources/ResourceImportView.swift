import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ResourceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]

    let initialCourse: Course?
    let initialChapter: Chapter?
    let initialSession: ClassSession?
    let onImported: (AcademicResource) -> Void

    @State private var selectedURL: URL?
    @State private var title = ""
    @State private var resourceDescription = ""
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var selectedSessionID: UUID?
    @State private var tagDraft = ""
    @State private var tags: [String] = []
    @State private var didAttemptSubmit = false
    @State private var importError: String?
    @State private var duplicateResource: AcademicResource?
    @State private var isFileImporterPresented = false
    @State private var isImporting = false
    @State private var showsCourseForm = false

    private let fileStore = AcademicFileStore()

    init(
        initialCourse: Course? = nil,
        initialChapter: Chapter? = nil,
        initialSession: ClassSession? = nil,
        onImported: @escaping (AcademicResource) -> Void = { _ in }
    ) {
        self.initialCourse = initialCourse
        self.initialChapter = initialChapter
        self.initialSession = initialSession
        self.onImported = onImported
        _selectedCourseID = State(initialValue: initialCourse?.id)
        _selectedChapterID = State(initialValue: initialChapter?.id)
        _selectedSessionID = State(initialValue: initialSession?.id)
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID } ?? initialCourse
    }

    private var chapters: [Chapter] {
        selectedCourse?.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order } ?? []
    }

    private var sessions: [ClassSession] {
        let courseSessions = selectedCourse?.sessions.sorted { $0.startTime < $1.startTime } ?? []
        guard let selectedChapterID else { return courseSessions }
        return courseSessions.filter { $0.chapter?.id == selectedChapterID }
    }

    private var selectedKind: AcademicResourceKind {
        AcademicFileStore.resourceKind(for: selectedURL?.pathExtension ?? "")
    }

    private var selectedChapter: Chapter? {
        chapters.first { $0.id == selectedChapterID }
    }

    private var selectedSession: ClassSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    private var draft: ResourceImportDraft {
        ResourceImportDraft(
            fileURL: selectedURL,
            title: title,
            resourceDescription: resourceDescription,
            course: selectedCourse,
            chapter: selectedChapter,
            session: selectedSession,
            tags: tags
        )
    }

    private var validation: ResourceImportValidation {
        ResourceImportValidation.validate(draft)
    }

    private var displayedValidation: ResourceImportValidation {
        didAttemptSubmit ? validation : ResourceImportValidation()
    }

    private var canImport: Bool {
        validation.isValid && !isImporting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fileCard
                    metadataCard
                    if let importError {
                        fieldError(importError)
                    }
                }
                .padding(18)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(StudyDeskTheme.backgroundPrimary)
            .navigationTitle("Import Resource")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submitImport() }
                    } label: {
                        if isImporting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Importing...")
                            }
                        } else {
                            Text("Import")
                        }
                    }
                    .disabled(!canImport)
                    .accessibilityIdentifier("resourceImportSubmitButton")
                    .accessibilityHint(importDisabledReason)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.pdf, .image, .audio, .movie, .text, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("This file is already in your library.", isPresented: Binding(
                get: { duplicateResource != nil },
                set: { if !$0 { duplicateResource = nil } }
            )) {
                Button("Open Existing") {
                    if let duplicateResource {
                        onImported(duplicateResource)
                        dismiss()
                    }
                }
                Button("Import Another Copy") {
                    Task { await submitImport(allowDuplicate: true) }
                }
                Button("Cancel", role: .cancel) {
                    duplicateResource = nil
                }
            } message: {
                Text("The same file is already linked to this course context.")
            }
            .sheet(isPresented: $showsCourseForm) {
                CourseFormView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .courseCreated)) { notification in
                if let course = notification.object as? Course {
                    selectedCourseID = course.id
                    showsCourseForm = false
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .disabled(isImporting)
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File")
                .font(.headline)
            if let selectedURL {
                HStack(spacing: 12) {
                    Image(systemName: selectedKind.systemImage)
                        .font(.title2)
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                        .frame(width: 42, height: 42)
                        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedURL.lastPathComponent)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        Text("\(selectedKind.title) · \(selectedURL.pathExtension.uppercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Replace") { isFileImporterPresented = true }
                    Button("Remove", role: .destructive) {
                        self.selectedURL = nil
                    }
                }
            } else {
                Button {
                    isFileImporterPresented = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                        Text("Choose a file")
                            .font(.headline)
                        Text("PDF, images, documents, audio and video")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .foregroundStyle(StudyDeskTheme.borderSubtle)
                    }
                }
                .buttonStyle(.plain)
            }
            if let fileError = displayedValidation.fileError {
                fieldError(fileError)
            }
        }
        .padding()
        .deskCard()
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField("Title", error: displayedValidation.titleError) {
                TextField("Resource title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            labeledField("Course", error: displayedValidation.courseError) {
                HStack {
                    Picker("Course", selection: $selectedCourseID) {
                        Text("Non classé").tag(UUID?.none)
                        ForEach(courses.filter { !$0.isArchived }) { course in
                            Text(course.name).tag(Optional(course.id))
                        }
                    }
                    Button("Créer un cours", systemImage: "plus") {
                        showsCourseForm = true
                    }
                }
            }
            labeledField("Chapter", error: displayedValidation.chapterError) {
                Picker("Chapter", selection: $selectedChapterID) {
                    Text("No chapter").tag(UUID?.none)
                    ForEach(chapters) { chapter in
                        Text(chapter.title).tag(Optional(chapter.id))
                    }
                }
            }
            labeledField("Session", error: displayedValidation.sessionError) {
                Picker("Session", selection: $selectedSessionID) {
                    Text("No session").tag(UUID?.none)
                    ForEach(sessions) { session in
                        Text(session.title).tag(Optional(session.id))
                    }
                }
            }
            labeledField("Description", error: nil) {
                TextField("Short description", text: $resourceDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
            tagsEditor
        }
        .padding()
        .deskCard()
        .onChange(of: selectedCourseID) { _, _ in
            if !chapters.contains(where: { $0.id == selectedChapterID }) {
                selectedChapterID = nil
            }
            if !sessions.contains(where: { $0.id == selectedSessionID }) {
                selectedSessionID = nil
            }
        }
        .onChange(of: selectedChapterID) { _, _ in
            if !sessions.contains(where: { $0.id == selectedSessionID }) {
                selectedSessionID = nil
            }
        }
    }

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                TextField("Add tag", text: $tagDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .disabled(tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !tags.isEmpty {
                FlowLayout(items: tags) { tag in
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        Label(tag, systemImage: "xmark")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(StudyDeskTheme.surfaceTinted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func labeledField<Content: View>(_ title: String, error: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
            if let error {
                fieldError(error)
            }
        }
    }

    private func fieldError(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importDisabledReason: String {
        if let fileError = validation.fileError { return fileError }
        if let titleError = validation.titleError { return titleError }
        if let courseError = validation.courseError { return courseError }
        if let chapterError = validation.chapterError { return chapterError }
        if let sessionError = validation.sessionError { return sessionError }
        return ""
    }

    private func addTag() {
        let tag = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        tagDraft = ""
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedURL = url
            importError = nil
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    @MainActor
    private func submitImport(allowDuplicate: Bool = false) async {
        guard !isImporting else { return }
        didAttemptSubmit = true
        guard validation.isValid else { return }
        isImporting = true
        do {
            let resource = try ResourceImportService.submit(
                draft: draft,
                existingResources: resources,
                modelContext: modelContext,
                fileStore: fileStore,
                allowDuplicate: allowDuplicate
            )
            onImported(resource)
            dismiss()
        } catch ResourceImportSubmitError.duplicate(let resourceID) {
            duplicateResource = resources.first { $0.id == resourceID }
            isImporting = false
        } catch ResourceImportSubmitError.invalid {
            isImporting = false
        } catch {
            importError = error.localizedDescription
            isImporting = false
        }
    }
}

struct CourseContentImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]

    let initialCourse: Course?
    let initialChapter: Chapter?
    let initialSession: ClassSession?

    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var selectedSessionID: UUID?
    @State private var rows: [CourseContentImportRow] = []
    @State private var isFileImporterPresented = false
    @State private var isImporting = false
    @State private var batchError: String?

    private let fileStore = AcademicFileStore()

    init(initialCourse: Course?, initialChapter: Chapter? = nil, initialSession: ClassSession? = nil) {
        self.initialCourse = initialCourse
        self.initialChapter = initialChapter
        self.initialSession = initialSession
        _selectedCourseID = State(initialValue: initialCourse?.id)
        _selectedChapterID = State(initialValue: initialChapter?.id)
        _selectedSessionID = State(initialValue: initialSession?.id)
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID } ?? initialCourse
    }

    private var chapters: [Chapter] {
        selectedCourse?.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order } ?? []
    }

    private var selectedChapter: Chapter? {
        chapters.first { $0.id == selectedChapterID } ?? initialChapter
    }

    private var sessions: [ClassSession] {
        let source = selectedCourse?.sessions.sorted { $0.startTime < $1.startTime } ?? []
        guard let selectedChapterID else { return source }
        return source.filter { $0.chapter?.id == selectedChapterID }
    }

    private var selectedSession: ClassSession? {
        sessions.first { $0.id == selectedSessionID } ?? initialSession
    }

    private var importableRows: [CourseContentImportRow] {
        rows.filter { $0.include && $0.status != .imported }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("Destination") {
                        Picker("Cours", selection: $selectedCourseID) {
                            Text("Non classé").tag(UUID?.none)
                            ForEach(courses.filter { !$0.isArchived }) { course in
                                Text(course.name).tag(Optional(course.id))
                            }
                        }
                        Picker("Chapitre", selection: $selectedChapterID) {
                            Text("Sans chapitre").tag(UUID?.none)
                            ForEach(chapters) { chapter in
                                Text(chapter.title).tag(Optional(chapter.id))
                            }
                        }
                        Picker("Séance", selection: $selectedSessionID) {
                            Text("Aucune séance").tag(UUID?.none)
                            ForEach(sessions) { session in
                                Text(session.title).tag(Optional(session.id))
                            }
                        }
                    }
                    Section("Fichiers") {
                        Button("Choisir des fichiers", systemImage: "square.and.arrow.down") {
                            isFileImporterPresented = true
                        }
                        if rows.isEmpty {
                            Text("PDF, images, documents et audio. Les fichiers seront prévisualisés avant import.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($rows) { $row in
                                CourseContentImportPreviewRow(
                                    row: $row,
                                    destination: destinationLabel(for: row)
                                )
                            }
                        }
                    }
                    if let batchError {
                        Section {
                            Text(batchError)
                                .foregroundStyle(.red)
                        }
                    }
                }
                HStack {
                    Text("\(importableRows.count) fichier(s) prêts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Annuler") { dismiss() }
                        .disabled(isImporting)
                    Button("Importer") {
                        Task { await importSelectedRows() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(importableRows.isEmpty || isImporting)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Importer du contenu")
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.pdf, .image, .audio, .movie, .text, .plainText, .data],
                allowsMultipleSelection: true
            ) { result in
                handleSelection(result)
            }
        }
        .frame(minWidth: 760, minHeight: 620)
    }

    private func handleSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            batchError = nil
            rows = urls.map { url in
                CourseContentImportRow(
                    url: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    kind: AcademicFileStore.resourceKind(for: url.pathExtension),
                    fileSize: fileSize(for: url),
                    isDuplicate: isDuplicate(url)
                )
            }
        case .failure(let error):
            batchError = error.localizedDescription
        }
    }

    @MainActor
    private func importSelectedRows() async {
        guard !isImporting else { return }
        isImporting = true
        batchError = nil
        var importedCount = 0
        for index in rows.indices where rows[index].include && rows[index].status != .imported {
            let url = rows[index].url
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let draft = ResourceImportDraft(
                    fileURL: url,
                    title: rows[index].title,
                    resourceDescription: "",
                    course: selectedCourse,
                    chapter: selectedChapter,
                    session: selectedSession,
                    tags: []
                )
                _ = try ResourceImportService.submit(
                    draft: draft,
                    existingResources: resources,
                    modelContext: modelContext,
                    fileStore: fileStore,
                    allowDuplicate: false
                )
                rows[index].status = .imported
                rows[index].errorMessage = nil
                importedCount += 1
            } catch ResourceImportSubmitError.duplicate {
                rows[index].status = .failed
                rows[index].errorMessage = "Doublon détecté pour cette destination."
            } catch {
                rows[index].status = .failed
                rows[index].errorMessage = error.localizedDescription
            }
        }
        isImporting = false
        if importedCount > 0 && rows.allSatisfy({ !$0.include || $0.status == .imported }) {
            dismiss()
        } else if importedCount > 0 {
            batchError = "\(importedCount) fichier(s) importé(s). Certains fichiers demandent une correction."
        }
    }

    private func destinationLabel(for row: CourseContentImportRow) -> String {
        [
            selectedCourse?.name ?? "Non classé",
            selectedChapter?.title,
            selectedSession?.title
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func fileSize(for url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func isDuplicate(_ url: URL) -> Bool {
        guard let hash = try? fileStore.fingerprint(for: url) else { return false }
        return resources.contains { resource in
            resource.contentHash == hash &&
            resource.course?.id == selectedCourse?.id &&
            resource.chapter?.id == selectedChapter?.id &&
            resource.session?.id == selectedSession?.id
        }
    }
}

private struct CourseContentImportRow: Identifiable {
    let id = UUID()
    let url: URL
    var title: String
    let kind: AcademicResourceKind
    let fileSize: Int64
    let isDuplicate: Bool
    var include = true
    var status: CourseContentImportStatus = .pending
    var errorMessage: String?
}

private enum CourseContentImportStatus {
    case pending
    case imported
    case failed
}

private struct CourseContentImportPreviewRow: View {
    @Binding var row: CourseContentImportRow
    let destination: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: $row.include)
                    .labelsHidden()
                Image(systemName: row.kind.systemImage)
                    .foregroundStyle(StudyDeskTheme.accentPrimary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Titre", text: $row.title)
                        .textFieldStyle(.roundedBorder)
                    Text("\(row.url.lastPathComponent) · \(row.kind.title) · \(ByteCountFormatter.string(fromByteCount: row.fileSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(destination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if row.isDuplicate {
                        Text("Doublon possible pour cette destination.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let errorMessage = row.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                switch row.status {
                case .pending:
                    EmptyView()
                case .imported:
                    Label("Importé", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Label("Échec", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
