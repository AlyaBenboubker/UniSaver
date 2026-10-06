import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RecordingListView: View {
    let recordings: [CourseRecording]

    var body: some View {
        List {
            if recordings.isEmpty {
                EmptyStateView(title: "No recordings", message: "Start a recording from Quick Add or a course workspace.", systemImage: "waveform")
            } else {
                ForEach(recordings) { recording in
                    RecordingRow(recording: recording)
                }
            }
        }
    }
}

struct RecordingRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var recording: CourseRecording
    @State private var playback = AudioPlaybackController()
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var speed: Float = 1
    @State private var fileMissing = false
    @State private var deleteConfirmation = false
    private let fileStore = AcademicFileStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(CourseColor.color(for: recording.course?.colorIdentifier ?? "blueViolet"))
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Recording title", text: $recording.title)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .onSubmit(save)
                    Text([recording.course?.name, recording.chapter?.title, recording.session?.title].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatDuration(recording.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Menu {
                    if recording.note != nil {
                        Button("Open Note", systemImage: "note.text") {
                            NotificationCenter.default.post(name: .selectAppSection, object: AppSection.library)
                        }
                    }
                    Button("Rename", systemImage: "pencil") { save() }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
                } label: {
                    Label("Recording actions", systemImage: "ellipsis.circle")
                }
            }
            if fileMissing {
                HStack {
                    Label("Audio file missing", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Remove Reference", role: .destructive) {
                        modelContext.delete(recording)
                        try? modelContext.save()
                    }
                }
                .font(.caption)
            } else {
                HStack {
                    Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                        togglePlayback()
                    }
                    Slider(value: $currentTime, in: 0...max(recording.duration, 1)) { editing in
                        if !editing {
                            playback.currentTime = currentTime
                        }
                    }
                    Text(formatDuration(currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Picker("Speed", selection: $speed) {
                        Text("0.75x").tag(Float(0.75))
                        Text("1x").tag(Float(1))
                        Text("1.25x").tag(Float(1.25))
                        Text("1.5x").tag(Float(1.5))
                        Text("2x").tag(Float(2))
                    }
                    .pickerStyle(.menu)
                }
            }
            RecordingTranscriptEditor(recording: recording)
        }
        .padding(.vertical, 6)
        .confirmationDialog("Delete recording?", isPresented: $deleteConfirmation) {
            Button("Delete Recording", role: .destructive) {
                RecordingPersistenceService.deleteRecording(recording, in: modelContext, fileStore: fileStore)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func togglePlayback() {
        do {
            if isPlaying {
                playback.pause()
                isPlaying = false
            } else {
                try playback.load(url: fileStore.url(for: recording.storedRelativePath))
                playback.currentTime = currentTime
                playback.play(rate: speed)
                isPlaying = true
            }
        } catch AcademicFileStoreError.fileMissing {
            fileMissing = true
            isPlaying = false
        } catch {
            isPlaying = false
        }
    }

    private func save() {
        recording.updatedAt = .now
        try? modelContext.save()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct RecordingTranscriptEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var recording: CourseRecording
    @State private var localeOptions: [SpeechLocaleOption] = []
    @State private var isLoadingLocales = false
    @State private var isTranscribing = false
    @State private var selectedLanguageIdentifier = Locale.current.identifier
    @State private var draftText = ""
    @State private var status: RecordingTranscriptionStatus = .ready
    @State private var message: String?
    private let fileStore = AcademicFileStore()
    private let transcriptionService = NativeSpeechTranscriptionService()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(status.title, systemImage: statusImage)
                    .font(.caption.weight(.semibold))
                Spacer()
                if localeOptions.isEmpty {
                    Text("No Apple Speech language available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Language", selection: languageBinding) {
                        ForEach(localeOptions) { option in
                            Text(option.displayName).tag(option.identifier)
                        }
                    }
                    .frame(maxWidth: 220)
                }
                Button("Retry", systemImage: "arrow.clockwise") {
                    startTranscription()
                }
                .disabled(isTranscribing || localeOptions.isEmpty)
            }
            TextEditor(text: $draftText)
            .frame(minHeight: 90)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
            }
            HStack {
                Button("Save correction", systemImage: "checkmark") {
                    recording.notes = draftText
                    recording.updatedAt = .now
                    status = draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .ready : .completed
                    message = "Transcription saved"
                    try? modelContext.save()
                }
                .buttonStyle(.bordered)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(status == .failed ? .red : .secondary)
                }
            }
        }
        .padding(12)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
        .task {
            draftText = recording.notes ?? ""
            status = draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .ready : .completed
            await loadLocales()
        }
    }

    private var statusImage: String {
        switch status {
        case .notStarted, .ready: "text.bubble"
        case .recording: "record.circle"
        case .transcribing: "waveform.and.magnifyingglass"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: {
                selectedLanguageIdentifier
            },
            set: { newValue in
                selectedLanguageIdentifier = newValue
            }
        )
    }

    private func loadLocales() async {
        guard !isLoadingLocales else { return }
        isLoadingLocales = true
        localeOptions = await transcriptionService.preferredLocaleOptions()
        if let first = localeOptions.first {
            selectedLanguageIdentifier = first.identifier
        }
        isLoadingLocales = false
    }

    private func startTranscription() {
        isTranscribing = true
        status = .transcribing
        message = "Transcription in progress"
        Task {
            do {
                try await transcriptionService.transcribe(
                    recording: recording,
                    in: modelContext,
                    fileStore: fileStore,
                    languageIdentifier: selectedLanguageIdentifier
                ) { partial in
                    draftText = partial
                }
                draftText = recording.notes ?? ""
                status = .completed
                message = "Transcription saved"
            } catch {
                status = .failed
                message = error.localizedDescription
            }
            isTranscribing = false
        }
    }
}

struct RecordingFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]

    let initialCourse: Course?
    let initialChapter: Chapter?
    let initialSession: ClassSession?

    @State private var title: String
    @State private var selectedCourseID: UUID?
    @State private var recorder = CourseAudioRecorder()
    @State private var errorMessage: String?
    @State private var importedRecording: SavedAcademicRecording?
    @State private var showingAudioImporter = false
    @State private var isSaving = false

    private let fileStore = AcademicFileStore()

    init(initialCourse: Course? = nil, initialChapter: Chapter? = nil, initialSession: ClassSession? = nil) {
        self.initialCourse = initialCourse
        self.initialChapter = initialChapter
        self.initialSession = initialSession
        _title = State(initialValue: initialSession?.title ?? initialCourse.map { "\($0.name) recording" } ?? "Course recording")
        _selectedCourseID = State(initialValue: initialCourse?.id)
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID } ?? initialCourse
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                formCard
                recorderCard
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .background(StudyDeskTheme.backgroundPrimary)
            .navigationTitle("Recording")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        recorder.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Recording") { saveRecording() }
                        .disabled(!canSave || isSaving)
                }
            }
        }
        .fileImporter(isPresented: $showingAudioImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            importAudio(result)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                recorder.tick()
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $title)
            Picker("Course", selection: $selectedCourseID) {
                Text("Choose course").tag(UUID?.none)
                ForEach(courses.filter { !$0.isArchived }) { course in
                    Text(course.name).tag(Optional(course.id))
                }
            }
        }
        .padding()
        .deskCard()
    }

    private var recorderCard: some View {
        VStack(spacing: 16) {
            Text(displayDuration, format: .number.precision(.fractionLength(0)))
                .font(.largeTitle.monospacedDigit().weight(.bold))
            Text(importedRecording == nil ? "Record with the microphone or import an existing audio file." : "Imported audio is ready to save.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: normalizedLevel)
                .tint(CourseColor.color(for: selectedCourse?.colorIdentifier ?? "blueViolet"))
            HStack {
                switch recorder.state {
                case .idle:
                    Button("Start", systemImage: "record.circle") { recorder.requestPermissionAndStart(title: title) }
                        .buttonStyle(.borderedProminent)
                case .requestingPermission:
                    Label("Requesting access...", systemImage: "mic")
                    ProgressView()
                case .preparing:
                    Label("Preparing...", systemImage: "waveform")
                    ProgressView()
                case .recording:
                    Button("Pause", systemImage: "pause.fill") { recorder.pause() }
                    Button("Stop", systemImage: "stop.fill") { recorder.stop() }
                case .paused:
                    Button("Resume", systemImage: "play.fill") { recorder.resume() }
                    Button("Stop", systemImage: "stop.fill") { recorder.stop() }
                case .stopping:
                    Label("Saving...", systemImage: "stop.circle")
                    ProgressView()
                case .saved:
                    Label("Ready to save", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .denied(let message), .failed(let message):
                    VStack(alignment: .leading) {
                        Text(message)
                            .foregroundStyle(.secondary)
                        Button("Try Again") { recorder.requestPermissionAndStart(title: title) }
                    }
                }
                Button("Import Audio", systemImage: "square.and.arrow.down") {
                    showingAudioImporter = true
                }
                .disabled(recorder.state.isActive)
                Button("Cancel", role: .destructive) { recorder.cancel() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .deskCard()
    }

    private var normalizedLevel: Double {
        if importedRecording != nil { return 1 }
        return min(max(Double(recorder.level + 60) / 60, 0), 1)
    }

    private var displayDuration: TimeInterval {
        importedRecording?.duration ?? recorder.elapsed
    }

    private var canSave: Bool {
        guard selectedCourse != nil else { return false }
        if importedRecording != nil { return true }
        if case .saved = recorder.state { return true }
        return false
    }

    private func saveRecording() {
        guard let selectedCourse else { return }
        guard let saved = importedRecording ?? recorderSavedRecording else { return }
        isSaving = true
        do {
            _ = try RecordingPersistenceService.createRecording(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                savedRecording: saved,
                course: selectedCourse,
                chapter: initialChapter,
                session: initialSession,
                note: nil,
                in: modelContext,
                fileStore: fileStore
            )
            recorder.resetAfterSave()
            importedRecording = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private var recorderSavedRecording: SavedAcademicRecording? {
        if case .saved(let saved) = recorder.state {
            return saved
        }
        return nil
    }

    private func importAudio(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            importedRecording = try fileStore.importRecording(from: url)
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title == "Course recording" {
                title = url.deletingPathExtension().lastPathComponent
            }
            errorMessage = nil
            recorder.cancel()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
