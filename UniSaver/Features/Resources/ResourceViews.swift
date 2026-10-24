import AppKit
import PDFKit
import QuickLookUI
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
            Image(systemName: resource.effectiveResourceSystemImage)
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
            if resource.effectiveResourceKind == .pdf {
                Text(resource.readingProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text(resource.effectiveResourceKindTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ResourceDetailView: View {
    var readerOnly = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var resource: AcademicResource
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @State private var selectedStudyTab: ResourceStudyTab = .notes
    @State private var errorMessage: String?
    @State private var selectedNote: StudyNote?
    @State private var previewItem: ResourcePreviewItem?
    @State private var noteDraft = ""
    @State private var isReadingActive = false
    @State private var readingSeconds = 0
    @State private var zoom: Double = 1
    private let fileStore = AcademicFileStore()

    private var linkedNotes: [StudyNote] {
        notes.filter { $0.resource?.id == resource.id }
    }

    private var activeNote: StudyNote? {
        selectedNote ?? linkedNotes.first
    }

    private var readingTimeKey: String {
        "resource-reading-seconds-\(resource.id.uuidString)"
    }

    private var isPagesDocument: Bool {
        resource.fileExtension.localizedCaseInsensitiveCompare("pages") == .orderedSame
    }

    var body: some View {
        VStack(spacing: 0) {
            if !readerOnly { readerHeader; Divider() }
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    documentWorkspace
                        .frame(minWidth: min(480, max(proxy.size.width - 390, 240)), maxWidth: .infinity, maxHeight: .infinity)
                    if !readerOnly {
                        Divider()
                        studySidebar.frame(width: max(300, min(390, proxy.size.width * 0.34)))
                    }
                }
            }
        }
        .navigationTitle(resource.title)
        .sheet(item: $previewItem) { item in
            ResourceQuickLookPreview(url: item.url)
                .frame(minWidth: 760, minHeight: 560)
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .onAppear {
            readingSeconds = UserDefaults.standard.integer(forKey: readingTimeKey)
            isReadingActive = true
            resource.lastOpenedAt = .now
            selectedNote = activeNote
            noteDraft = activeNote?.body ?? ""
            try? modelContext.save()
        }
        .onDisappear {
            isReadingActive = false
            persistReadingSeconds()
        }
        .onChange(of: scenePhase) { _, newPhase in
            isReadingActive = newPhase == .active
            if newPhase != .active {
                persistReadingSeconds()
            }
        }
        .onChange(of: selectedNote?.id) { _, _ in
            noteDraft = activeNote?.body ?? ""
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard isReadingActive, scenePhase == .active else { continue }
                readingSeconds += 1
                if readingSeconds.isMultiple(of: 15) {
                    persistReadingSeconds()
                }
            }
        }
    }

    private var readerHeader: some View {
        HStack(spacing: 14) {
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
            Label(readingTimeLabel, systemImage: isReadingActive ? "timer" : "pause.circle")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("À revoir", systemImage: "bookmark") {
                markForReview()
            }
            Button("Prévisualiser", systemImage: "eye") {
                previewResource()
            }
            Button("Ouvrir", systemImage: "arrow.up.forward.app") {
                openInDefaultApp()
            }
            Button("Finder", systemImage: "folder") {
                revealInFinder()
            }
            Button("Favori", systemImage: resource.isFavorite ? "star.fill" : "star") {
                resource.isFavorite.toggle()
                resource.updatedAt = .now
                try? modelContext.save()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var documentWorkspace: some View {
        Group {
            if let url = try? storedFileURL() {
                switch resource.effectiveResourceKind {
                case .pdf:
                    pdfReader(url: url)
                case .image:
                    imageReader(url: url)
                default:
                    if isPagesDocument {
                        pagesFallback(url: url)
                    } else {
                        genericPreview(url: url)
                    }
                }
            } else {
                EmptyStateView(title: "Fichier introuvable", message: "La fiche existe, mais la copie privée conservée par UniSaver n’est plus accessible.", systemImage: "exclamationmark.triangle")
                    .padding()
            }
        }
    }

    private func pdfReader(url: URL) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("PDF")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(resource.readingProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            PDFKitReaderView(url: url, initialPage: resource.lastPage) { page, count in
                resource.lastPage = page
                resource.pageCount = count
                resource.readingProgress = Double(page) / Double(max(count, 1))
                resource.lastOpenedAt = .now
                resource.updatedAt = .now
                try? modelContext.save()
            }
        }
    }

    private func imageReader(url: URL) -> some View {
        ScrollView([.vertical, .horizontal]) {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                EmptyStateView(title: "Image illisible", message: "Le fichier existe, mais macOS ne peut pas charger cette image.", systemImage: "photo")
                    .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            zoomControls
        }
    }

    private func genericPreview(url: URL) -> some View {
        VStack(spacing: 0) {
            ResourceQuickLookPreview(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Aperçu Quick Look de la copie privée UniSaver. Si le rendu est incomplet, ouvre le fichier dans son application d’origine.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)
        }
    }

    private func pagesFallback(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Lecture Pages limitée sur ce Mac", systemImage: "doc.text.magnifyingglass")
                .font(.title2.weight(.bold))
            Text("Quick Look n’a pas fourni un rendu de lecture fiable pour ce fichier .pages. UniSaver conserve bien l’original, mais ne l’étire pas comme un faux document lisible.")
                .foregroundStyle(.secondary)
            Text("Pour étudier le contenu dans UniSaver, exporte ce document depuis Pages en PDF, puis importe ce PDF dans Library. Le fichier .pages original reste lié et ouvrable.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Ouvrir dans Pages", systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                Button("Afficher dans le Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var studySidebar: some View {
        VStack(spacing: 0) {
            Picker("Outils", selection: $selectedStudyTab) {
                ForEach(ResourceStudyTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            Divider()
            switch selectedStudyTab {
            case .notes:
                notesEditor
            case .questions:
                questionsPanel
            case .assistant:
                assistantPanel
            }
        }
        .background(StudyDeskTheme.backgroundSecondary)
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Note", selection: $selectedNote) {
                Text("Nouvelle note liée").tag(StudyNote?.none)
                ForEach(linkedNotes) { note in
                    Text(note.title).tag(Optional(note))
                }
            }
            TextEditor(text: $noteDraft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            HStack {
                Button("Enregistrer", systemImage: "square.and.arrow.down") {
                    saveLinkedNote()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                if let activeNote {
                    Text(activeNote.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private var questionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Questions de compréhension", systemImage: "questionmark.bubble")
                    .font(.headline)
                Text(documentTextStatus)
                    .foregroundStyle(.secondary)
                Text("Aucun fournisseur IA n’est configuré ici. Les questions automatiques seront activées seulement avec un service explicite et traçable ; UniSaver ne présente pas de questions simulées comme générées.")
                    .foregroundStyle(.secondary)
                Button("Marquer ce passage à revoir", systemImage: "bookmark") {
                    markForReview()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var assistantPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Assistant document", systemImage: "sparkles")
                    .font(.headline)
                Text("Assistant configurable non connecté.")
                    .font(.callout.weight(.semibold))
                Text(documentTextStatus)
                    .foregroundStyle(.secondary)
                Text("Pour un PDF avec texte extractible, l’assistant pourra citer les passages sources. Pour un fichier .pages dont Quick Look échoue, exporte un PDF ou du texte fiable avant de poser des questions.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var zoomControls: some View {
        HStack {
            Button("Réduire", systemImage: "minus.magnifyingglass") {
                zoom = max(0.5, zoom - 0.1)
            }
            Slider(value: $zoom, in: 0.5...2.5)
                .frame(maxWidth: 180)
            Button("Agrandir", systemImage: "plus.magnifyingglass") {
                zoom = min(2.5, zoom + 0.1)
            }
            Text(zoom, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.bar)
    }

    private var documentTextStatus: String {
        guard let url = try? storedFileURL() else {
            return "Le fichier local est introuvable : aucun texte ne peut être extrait."
        }
        if resource.effectiveResourceKind == .pdf {
            let count = PDFDocument(url: url)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
            return count > 0 ? "Texte PDF détecté : \(count) caractères extractibles." : "Ce PDF ne fournit pas de texte extractible fiable sur ce Mac."
        }
        if isPagesDocument {
            return "Le fichier .pages original est conservé, mais UniSaver ne dispose pas d’un texte source fiable pour générer ou vérifier des réponses."
        }
        return "Ce format n’a pas encore d’extraction de texte fiable dans UniSaver."
    }

    private var readingTimeLabel: String {
        let minutes = readingSeconds / 60
        let seconds = readingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func storedFileURL() throws -> URL {
        try fileStore.url(for: resource.storedRelativePath)
    }

    private func persistReadingSeconds() {
        UserDefaults.standard.set(readingSeconds, forKey: readingTimeKey)
    }

    private func saveLinkedNote() {
        do {
            let note = try LinkedNoteService.note(for: resource, existingNotes: notes, in: modelContext)
            note.body = noteDraft
            note.title = note.title.isEmpty ? "Notes — \(resource.title)" : note.title
            note.course = resource.course
            note.chapter = resource.chapter
            note.session = resource.session
            note.resource = resource
            note.updatedAt = .now
            selectedNote = note
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "La note liée n’a pas pu être enregistrée : \(error.localizedDescription)"
        }
    }

    private func markForReview() {
        let tag = resource.effectiveResourceKind == .pdf ? "review-page-\(max(resource.lastPage, 1))" : "review-document"
        if !resource.tags.contains(tag) {
            resource.tags.append(tag)
        }
        resource.updatedAt = .now
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "Le marque-page de révision n’a pas pu être enregistré."
        }
    }

    private func previewResource() {
        do {
            previewItem = ResourcePreviewItem(url: try storedFileURL())
            errorMessage = nil
        } catch {
            errorMessage = "Le fichier conservé par UniSaver est introuvable. Réimporte le document ou vérifie le stockage local."
        }
    }

    private func openInDefaultApp() {
        do {
            let url = try storedFileURL()
            NSWorkspace.shared.open(url)
            errorMessage = nil
        } catch {
            errorMessage = "Impossible d’ouvrir le fichier : \(error.localizedDescription)"
        }
    }

    private func revealInFinder() {
        do {
            let url = try storedFileURL()
            NSWorkspace.shared.activateFileViewerSelecting([url])
            errorMessage = nil
        } catch {
            errorMessage = "Impossible d’afficher le fichier dans le Finder : \(error.localizedDescription)"
        }
    }
}

private enum ResourceStudyTab: String, CaseIterable, Identifiable {
    case notes
    case questions
    case assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: "Notes"
        case .questions: "Questions"
        case .assistant: "Assistant"
        }
    }

    var systemImage: String {
        switch self {
        case .notes: "note.text"
        case .questions: "questionmark.bubble"
        case .assistant: "sparkles"
        }
    }
}

private struct ResourcePreviewItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ResourceQuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView(frame: .zero)
        view?.autostarts = true
        view?.previewItem = url as NSURL
        return view ?? QLPreviewView(frame: .zero)
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        let currentURL = (nsView.previewItem as? NSURL) as URL?
        guard currentURL != url else { return }
        nsView.previewItem = url as NSURL
    }
}
