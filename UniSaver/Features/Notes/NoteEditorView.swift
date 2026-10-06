import SwiftData
import SwiftUI

struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppNavigationState.self) private var navigation
    @Bindable var note: StudyNote
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]
    @State private var saveStatus = "Saved"
    @State private var saveError: String?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var deleteConfirmation = false
    @State private var recorder = CourseAudioRecorder()
    @State private var recordingTitle = ""
    @State private var editorMode: NoteEditorMode = .edit
    @State private var lastSavedRecording: CourseRecording?
    @State private var lastSavedTitle = ""
    @State private var lastSavedBody = ""
    @State private var pendingExit = NoteExitIntent.none
    @State private var showUnsavedExitDialog = false

    private var linkedRecordings: [CourseRecording] {
        recordings.filter { $0.note?.id == note.id }
    }

    private var hasUnsavedTextChanges: Bool {
        note.title != lastSavedTitle || note.body != lastSavedBody
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
        .onAppear {
            refreshSavedSnapshot()
            navigation.noteNavigationGuard = { section in
                requestSectionChange(section)
            }
        }
        .onDisappear {
            if !hasUnsavedTextChanges {
                saveNow()
            }
            navigation.noteNavigationGuard = nil
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
        .confirmationDialog("Leave this note?", isPresented: $showUnsavedExitDialog) {
            Button("Save") {
                completePendingExitAfterSave()
            }
            Button("Discard Changes", role: .destructive) {
                completePendingExitAfterDiscard()
            }
            Button("Cancel", role: .cancel) {
                pendingExit = .none
            }
        } message: {
            Text("Save changes before leaving this note, discard them, or cancel to keep editing.")
        }
    }

    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button("Back", systemImage: "chevron.left") { requestDismiss() }
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
                Picker("Mode", selection: $editorMode) {
                    ForEach(NoteEditorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
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
            case .idle, .saved, .denied, .failed:
                Button {
                    recordingTitle = "\(note.title.isEmpty ? "Note" : note.title) recording"
                    recorder.requestPermissionAndStart(title: recordingTitle)
                } label: {
                    Label("Record", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(minHeight: 44)
            case .requestingPermission, .preparing, .recording, .paused, .stopping:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var recordingBar: some View {
        switch recorder.state {
        case .requestingPermission:
            recordingStatusBar(systemImage: "mic", title: "Requesting microphone access...", tint: .blue) {
                ProgressView()
            }
        case .preparing:
            recordingStatusBar(systemImage: "waveform", title: "Preparing recorder...", tint: .blue) {
                ProgressView()
            }
        case .recording, .paused:
            HStack(spacing: 12) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text(formatDuration(recorder.elapsed))
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
        case .stopping:
            recordingStatusBar(systemImage: "stop.circle", title: "Saving recording...", tint: .orange) {
                ProgressView()
            }
        case .saved(let saved):
            HStack(spacing: 12) {
                Label("Recording saved · \(formatDuration(saved.duration))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Done") { recorder.resetAfterSave() }
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.green.opacity(0.08))
        case .denied(let message), .failed(let message):
            HStack(spacing: 12) {
                Label(message, systemImage: "mic.slash")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Open Settings", action: openAppSettings)
                    .buttonStyle(.bordered)
                Button("Try Again") {
                    recordingTitle = recordingTitle.isEmpty ? "\(note.title.isEmpty ? "Note" : note.title) recording" : recordingTitle
                    recorder.requestPermissionAndStart(title: recordingTitle)
                }
                .buttonStyle(.bordered)
                Button("Dismiss") { recorder.cancel() }
            }
            .font(.caption)
            .padding(12)
            .background(.red.opacity(0.08))
        default:
            EmptyView()
        }
    }

    private func recordingStatusBar<Accessory: View>(systemImage: String, title: String, tint: Color, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer()
            accessory()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08))
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
                if editorMode == .edit {
                    ZStack(alignment: .topLeading) {
                        if note.body.isEmpty {
                            Text("Start writing...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 12)
                                .padding(.leading, 8)
                        }
                        TextField("", text: $note.body, axis: .vertical)
                            .font(.body)
                            .lineSpacing(5)
                            .textFieldStyle(.plain)
                            .lineLimit(18...120)
                            .padding(8)
                            .accessibilityLabel("Note body")
                    }
                } else {
                    MarkdownPreviewView(markdown: note.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(24)
            .frame(maxWidth: 860, alignment: .topLeading)
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
            _ = await MainActor.run { saveNow() }
        }
    }

    @discardableResult
    private func saveNow() -> Bool {
        note.updatedAt = .now
        do {
            try modelContext.save()
            saveStatus = "Saved"
            saveError = nil
            refreshSavedSnapshot()
            return true
        } catch {
            saveStatus = "Save failed"
            saveError = error.localizedDescription
            return false
        }
    }

    private func refreshSavedSnapshot() {
        lastSavedTitle = note.title
        lastSavedBody = note.body
    }

    private func requestDismiss() {
        if hasUnsavedTextChanges {
            pendingExit = .dismiss
            showUnsavedExitDialog = true
        } else {
            saveNow()
            dismiss()
        }
    }

    private func requestSectionChange(_ section: AppSection) -> Bool {
        if hasUnsavedTextChanges {
            pendingExit = .section(section)
            showUnsavedExitDialog = true
            return false
        }
        saveNow()
        return true
    }

    private func completePendingExitAfterSave() {
        guard saveNow() else { return }
        completePendingExit()
    }

    private func completePendingExitAfterDiscard() {
        note.title = lastSavedTitle
        note.body = lastSavedBody
        note.updatedAt = .now
        _ = saveNow()
        completePendingExit()
    }

    private func completePendingExit() {
        let exit = pendingExit
        pendingExit = .none
        navigation.noteNavigationGuard = nil
        switch exit {
        case .none:
            break
        case .dismiss:
            dismiss()
        case .section(let section):
            navigation.select(section)
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
        guard case .saved(let saved) = recorder.state else { return }
        do {
            let recording = try RecordingPersistenceService.createRecording(
                title: recordingTitle,
                savedRecording: saved,
                course: note.course,
                chapter: note.chapter,
                session: note.session,
                note: note,
                in: modelContext
            )
            lastSavedRecording = recording
        } catch {
            saveStatus = "Recording save failed"
            saveError = error.localizedDescription
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func openAppSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

private enum NoteEditorMode: String, CaseIterable, Identifiable {
    case edit
    case preview

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private enum NoteExitIntent: Equatable {
    case none
    case dismiss
    case section(AppSection)
}

private struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Nothing to preview yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(markdown.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                    rendered(line)
                }
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private func rendered(_ rawLine: String) -> some View {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("# ") {
            Text(String(line.dropFirst(2))).font(.largeTitle.bold())
        } else if line.hasPrefix("## ") {
            Text(String(line.dropFirst(3))).font(.title2.bold())
        } else if line.hasPrefix("### ") {
            Text(String(line.dropFirst(4))).font(.title3.weight(.semibold))
        } else if line.hasPrefix("- [ ] ") {
            Label(String(line.dropFirst(6)), systemImage: "square")
        } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
            Label(String(line.dropFirst(6)), systemImage: "checkmark.square.fill")
        } else if line.hasPrefix("- ") {
            HStack(alignment: .top) {
                Text("•")
                Text(inline(line.dropFirst(2)))
            }
        } else if line.hasPrefix("1. ") {
            HStack(alignment: .top) {
                Text("1.")
                Text(inline(line.dropFirst(3)))
            }
        } else if line.hasPrefix("> ") {
            Text(inline(line.dropFirst(2)))
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(StudyDeskTheme.accentPrimary.opacity(0.45)).frame(width: 3)
                }
                .foregroundStyle(.secondary)
        } else if line == "---" {
            Divider()
        } else {
            Text(inline(line))
        }
    }

    private func inline<S: StringProtocol>(_ value: S) -> AttributedString {
        var attributed = AttributedString(String(value))
        let raw = String(value)
        applyMarkdown(marker: "**", raw: raw, to: &attributed, intent: .stronglyEmphasized)
        applyMarkdown(marker: "*", raw: raw, to: &attributed, intent: .emphasized)
        return attributed
    }

    private func applyMarkdown(marker: String, raw: String, to attributed: inout AttributedString, intent: InlinePresentationIntent) {
        var searchStart = raw.startIndex
        while let first = raw[searchStart...].range(of: marker),
              let second = raw[first.upperBound...].range(of: marker) {
            let textRange = first.upperBound..<second.lowerBound
            if let range = Range(textRange, in: attributed) {
                attributed[range].inlinePresentationIntent = intent
            }
            searchStart = second.upperBound
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
