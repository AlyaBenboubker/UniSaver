import SwiftData
import SwiftUI

struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var note: StudyNote
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]
    @State private var saveStatus = "Saved"
    @State private var saveError: String?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var deleteConfirmation = false
    @State private var recorder = CourseAudioRecorder()
    @State private var recordingTitle = ""

    private var linkedRecordings: [CourseRecording] {
        recordings.filter { $0.note?.id == note.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            noteHeader
            recordingBar
            formattingToolbar
            Divider()
            editorBody
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .navigationTitle(note.title.isEmpty ? "Note" : note.title)
        .navigationBarTitleDisplayModeInlineIfAvailable()
        .toolbar {
            ToolbarItemGroup {
                Button(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin") {
                    note.isPinned.toggle()
                    scheduleSave()
                }
                .help(note.isPinned ? "Unpin note" : "Pin note")
                Menu {
                    Button("Duplicate", systemImage: "doc.on.doc") { duplicateNote() }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .onChange(of: note.title) { _, _ in scheduleSave() }
        .onChange(of: note.body) { _, _ in scheduleSave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                saveNow()
            }
        }
        .onDisappear {
            saveNow()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                recorder.tick()
            }
        }
        .confirmationDialog("Delete note?", isPresented: $deleteConfirmation) {
            Button("Delete Note", role: .destructive) {
                modelContext.delete(note)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button("Back", systemImage: "chevron.left") { dismiss() }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Untitled note", text: $note.title)
                        .font(.title2.weight(.bold))
                        .textFieldStyle(.plain)
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                recordButton
            }
            HStack {
                Text(saveStatus)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(saveError == nil ? Color.secondary : Color.red)
                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(StudyDeskTheme.surfacePrimary)
    }

    private var recordButton: some View {
        Group {
            switch recorder.state {
            case .idle, .finished, .unavailable:
                Button {
                    recordingTitle = "\(note.title.isEmpty ? "Note" : note.title) recording"
                    recorder.requestPermissionAndStart()
                } label: {
                    Label("Record", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(minHeight: 44)
            case .recording, .paused:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var recordingBar: some View {
        switch recorder.state {
        case .recording, .paused:
            HStack(spacing: 12) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text(recorder.elapsed, format: .number.precision(.fractionLength(0)))
                    .font(.callout.monospacedDigit().weight(.semibold))
                ProgressView(value: min(max(Double(recorder.level + 60) / 60, 0), 1))
                    .tint(.red)
                if case .recording = recorder.state {
                    Button("Pause", systemImage: "pause.fill") { recorder.pause() }
                } else {
                    Button("Resume", systemImage: "play.fill") { recorder.resume() }
                }
                Button("Stop", systemImage: "stop.fill") { stopRecordingIntoNote() }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.red.opacity(0.06))
        case .unavailable(let message):
            HStack {
                Label(message, systemImage: "mic.slash")
                Spacer()
                Button("Dismiss") { recorder.cancel() }
            }
            .font(.caption)
            .padding(12)
            .background(.red.opacity(0.08))
        default:
            EmptyView()
        }
    }

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu("Body") {
                    Button("Title") { insert(prefix: "# ") }
                    Button("Heading") { insert(prefix: "## ") }
                    Button("Subheading") { insert(prefix: "### ") }
                    Button("Body") { insert(prefix: "") }
                }
                iconButton("Bold", "bold") { wrap("**") }
                iconButton("Italic", "italic") { wrap("*") }
                iconButton("Underline", "underline") { wrap("__") }
                iconButton("Bulleted list", "list.bullet") { insert(prefix: "- ") }
                iconButton("Numbered list", "list.number") { insert(prefix: "1. ") }
                iconButton("Checklist", "checklist") { insert(prefix: "- [ ] ") }
                iconButton("Quote", "quote.opening") { insert(prefix: "> ") }
                iconButton("Separator", "minus") { insert(prefix: "---") }
                iconButton("Link", "link") { note.body += " [link](https://)" }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(StudyDeskTheme.surfacePrimary)
    }

    private func iconButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
        .help(title)
    }

    private var editorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .topLeading) {
                    if note.body.isEmpty {
                        Text("Start writing...")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextField("", text: $note.body, axis: .vertical)
                        .font(.body)
                        .lineSpacing(4)
                        .textFieldStyle(.plain)
                        .lineLimit(18...80)
                        .accessibilityLabel("Note body")
                }

                if !linkedRecordings.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Audio")
                            .font(.headline)
                        ForEach(linkedRecordings) { recording in
                            RecordingAttachmentCard(recording: recording)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var metadataText: String {
        let context = [note.course?.name, note.chapter?.title, note.session?.title].compactMap { $0 }.joined(separator: " / ")
        let prefix = context.isEmpty ? "Loose note" : context
        return "\(prefix) / Updated \(UniDateFormatters.dayMonth.string(from: note.updatedAt))"
    }

    private func scheduleSave() {
        saveStatus = "Saving..."
        saveError = nil
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await MainActor.run { saveNow() }
        }
    }

    private func saveNow() {
        note.updatedAt = .now
        do {
            try modelContext.save()
            saveStatus = "Saved"
            saveError = nil
        } catch {
            saveStatus = "Save failed"
            saveError = error.localizedDescription
        }
    }

    private func insert(prefix: String) {
        note.body += note.body.isEmpty ? prefix : "\n\(prefix)"
        scheduleSave()
    }

    private func wrap(_ marker: String) {
        note.body += note.body.isEmpty ? "\(marker)text\(marker)" : " \(marker)text\(marker)"
        scheduleSave()
    }

    private func duplicateNote() {
        let duplicate = StudyNote(title: "\(note.title) copy", body: note.body, course: note.course, chapter: note.chapter, session: note.session, resource: note.resource)
        modelContext.insert(duplicate)
        try? modelContext.save()
    }

    private func stopRecordingIntoNote() {
        recorder.stop()
        guard case .finished(let tempURL, let duration) = recorder.state else { return }
        do {
            let stored = try AcademicFileStore().importFile(from: tempURL)
            let recording = CourseRecording(
                title: recordingTitle,
                storedRelativePath: stored.storedRelativePath,
                duration: duration,
                course: note.course,
                chapter: note.chapter,
                session: note.session,
                note: note
            )
            modelContext.insert(recording)
            try modelContext.save()
        } catch {
            saveStatus = "Recording save failed"
            saveError = error.localizedDescription
        }
    }
}

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    let notes: [StudyNote]
    let emptyTitle: String
    let createNote: () -> StudyNote
    @State private var searchText = ""
    @State private var sortMode = "Recent"
    @State private var selectedNote: StudyNote?

    private var filteredNotes: [StudyNote] {
        notes
            .filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) || $0.body.localizedCaseInsensitiveContains(searchText) }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                switch sortMode {
                case "Oldest": return $0.updatedAt < $1.updatedAt
                case "Title": return $0.title < $1.title
                default: return $0.updatedAt > $1.updatedAt
                }
            }
    }

    var body: some View {
        List {
            if notes.isEmpty {
                EmptyStateView(title: emptyTitle, message: "Create a note linked to this academic context.", systemImage: "note.text", actionTitle: "Create a note") {
                    selectedNote = createNote()
                }
            } else {
                Section {
                    ForEach(filteredNotes) { note in
                        NavigationLink {
                            NoteEditorView(note: note)
                        } label: {
                            NoteCardRow(note: note)
                        }
                        .contextMenu {
                            Button(note.isPinned ? "Unpin" : "Pin") {
                                note.isPinned.toggle()
                                note.updatedAt = .now
                                try? modelContext.save()
                            }
                            Button("Duplicate") {
                                let copy = StudyNote(title: "\(note.title) copy", body: note.body, course: note.course, chapter: note.chapter, session: note.session, resource: note.resource)
                                modelContext.insert(copy)
                                try? modelContext.save()
                            }
                            Button("Delete", role: .destructive) {
                                modelContext.delete(note)
                                try? modelContext.save()
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(filteredNotes[index])
                        }
                        try? modelContext.save()
                    }
                } header: {
                    controls
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("New Note", systemImage: "plus") {
                    selectedNote = createNote()
                }
            }
        }
        .navigationDestination(item: $selectedNote) { note in
            NoteEditorView(note: note)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            TextField("Search notes", text: $searchText)
            Picker("Sort", selection: $sortMode) {
                Text("Recent").tag("Recent")
                Text("Oldest").tag("Oldest")
                Text("Title").tag("Title")
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct NoteCardRow: View {
    let note: StudyNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title.isEmpty ? "Untitled note" : note.title)
                    .font(.headline)
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                }
                Spacer()
            }
            Text(note.body.isEmpty ? "No content yet." : note.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text([note.course?.name, note.chapter?.title, note.session?.title, UniDateFormatters.dayMonth.string(from: note.updatedAt)].compactMap { $0 }.joined(separator: " / "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

struct RecordingAttachmentCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var recording: CourseRecording
    @State private var deleteConfirmation = false
    @State private var playback = AudioPlaybackController()
    @State private var isPlaying = false
    @State private var speed: Float = 1
    private let fileStore = AcademicFileStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Recording title", text: $recording.title)
                    .font(.callout.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onSubmit(save)
                Spacer()
                Menu {
                    Button("Reveal in Library") {
                        NotificationCenter.default.post(name: .selectAppSection, object: AppSection.library)
                    }
                    Button("Unlink") {
                        recording.note = nil
                        save()
                    }
                    Button("Delete", role: .destructive) {
                        deleteConfirmation = true
                    }
                } label: {
                    Label("Recording actions", systemImage: "ellipsis.circle")
                }
            }
            HStack {
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    togglePlayback()
                }
                Picker("Speed", selection: $speed) {
                    Text("0.75x").tag(Float(0.75))
                    Text("1x").tag(Float(1))
                    Text("1.25x").tag(Float(1.25))
                    Text("1.5x").tag(Float(1.5))
                    Text("2x").tag(Float(2))
                }
                .pickerStyle(.menu)
                Spacer()
                Text(recording.duration, format: .number.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: 0.0)
        }
        .padding()
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
        .confirmationDialog("Delete recording?", isPresented: $deleteConfirmation) {
            Button("Delete Recording", role: .destructive) {
                try? fileStore.delete(relativePath: recording.storedRelativePath)
                modelContext.delete(recording)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the recording metadata and its stored audio file.")
        }
    }

    private func togglePlayback() {
        do {
            if isPlaying {
                playback.pause()
                isPlaying = false
            } else {
                try playback.load(url: fileStore.url(for: recording.storedRelativePath))
                playback.play(rate: speed)
                isPlaying = true
            }
        } catch {
            isPlaying = false
        }
    }

    private func save() {
        recording.updatedAt = .now
        try? modelContext.save()
    }
}

private extension View {
    func navigationBarTitleDisplayModeInlineIfAvailable() -> some View {
        #if os(iOS)
        return self.navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }
}
