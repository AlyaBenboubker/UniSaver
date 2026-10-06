import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var editingSession: ClassSession?
    @State private var deleteSession: ClassSession?
    @State private var showsDeleteConfirmation = false
    @State private var searchText = ""

    private var sessions: [ClassSession] {
        course.sessions
            .filter { session in
                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || session.title.localizedCaseInsensitiveContains(searchText)
                    || session.room?.localizedCaseInsensitiveContains(searchText) == true
                    || session.chapter?.title.localizedCaseInsensitiveContains(searchText) == true
            }
            .sorted { $0.startTime < $1.startTime }
    }

    private var groupedSessions: [(Date, [ClassSession])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .weekOfYear, for: session.startTime)?.start ?? calendar.startOfDay(for: session.startTime)
        }
        return groups
            .map { ($0.key, $0.value.sorted { $0.startTime < $1.startTime }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Rechercher une séance, salle ou chapitre", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button("Effacer", systemImage: "xmark.circle.fill") {
                        searchText = ""
                    }
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                }
            }
            .padding(10)
            .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top])

            List {
                if sessions.isEmpty {
                    EmptyStateView(title: "Aucune séance", message: searchText.isEmpty ? "Ajoute une séance datée pour alimenter Today et Planner." : "Aucune séance ne correspond à cette recherche.", systemImage: "calendar.badge.plus", actionTitle: searchText.isEmpty ? "Nouvelle séance" : nil) {
                        if searchText.isEmpty {
                            quickAddTarget = .session(course, nil)
                        }
                    }
                } else {
                    ForEach(groupedSessions, id: \.0) { weekStart, weekSessions in
                        Section(weekTitle(for: weekStart)) {
                            ForEach(weekSessions) { session in
                                NavigationLink {
                                    SessionDetailView(session: session, quickAddTarget: $quickAddTarget)
                                } label: {
                                    SessionRow(session: session)
                                }
                                .swipeActions {
                                    Button("Supprimer", role: .destructive) {
                                        deleteSession = session
                                        showsDeleteConfirmation = true
                                    }
                                }
                                .contextMenu {
                                    Button("Modifier") { editingSession = session }
                                    Button("Avancer l’état") {
                                        session.progressStatus = session.progressStatus.advanced()
                                        session.updatedAt = .now
                                        try? modelContext.save()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Nouvelle séance", systemImage: "plus") { quickAddTarget = .session(course, nil) }
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

    private func weekTitle(for start: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(UniDateFormatters.dayMonth.string(from: start)) – \(UniDateFormatters.dayMonth.string(from: end))"
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
    @State private var importingAudio = false
    @State private var recordingLecture = false
    @State private var localeOptions: [SpeechLocaleOption] = []
    @State private var selectedLanguageIdentifier = Locale.current.identifier
    @State private var audioMessage: String?
    private let fileStore = AcademicFileStore()
    private let transcriptionService = NativeSpeechTranscriptionService()

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
                    if let sourceTimeZoneNote {
                        Label(sourceTimeZoneNote, systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                        ForEach(linkedRecordings.prefix(4)) { recording in
                            RecordingRow(recording: recording)
                        }
                    }
                    HStack {
                        Button("Import Resource", systemImage: "square.and.arrow.down") {
                            quickAddTarget = .resource(session.course, session.chapter, session)
                        }
                        Button("Import Audio", systemImage: "waveform.badge.plus") {
                            importingAudio = true
                        }
                        Button("New Note", systemImage: "note.text") {
                            quickAddTarget = .note(session.course, session.chapter, session, nil)
                        }
                        Button("Record Lecture", systemImage: "record.circle") {
                            recordingLecture = true
                        }
                    }
                    .buttonStyle(.bordered)
                    if !localeOptions.isEmpty {
                        Picker("Transcription language", selection: $selectedLanguageIdentifier) {
                            ForEach(localeOptions) { option in
                                Text(option.displayName).tag(option.identifier)
                            }
                        }
                        .frame(maxWidth: 280)
                    }
                    if let audioMessage {
                        Text(audioMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .sheet(isPresented: $recordingLecture) {
            SessionLectureRecorderView(
                session: session,
                languageIdentifier: selectedLanguageIdentifier
            )
        }
        .fileImporter(
            isPresented: $importingAudio,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleAudioImport(result)
        }
        .task {
            localeOptions = await transcriptionService.preferredLocaleOptions()
            if let first = localeOptions.first, !localeOptions.contains(where: { $0.identifier == selectedLanguageIdentifier }) {
                selectedLanguageIdentifier = first.identifier
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

    private var sourceTimeZoneNote: String? {
        session.sessionDescription
            .split(separator: "\n")
            .map(String.init)
            .first { $0.localizedCaseInsensitiveContains("source") && ($0.localizedCaseInsensitiveContains("fuseau") || $0.localizedCaseInsensitiveContains("calendrier")) }
    }

    private func handleAudioImport(_ result: Result<[URL], Error>) {
        guard let course = session.course else {
            audioMessage = "This session is not linked to a course."
            return
        }
        do {
            guard let url = try result.get().first else { return }
            let saved = try fileStore.importRecording(from: url)
            let recording = try RecordingPersistenceService.createRecording(
                title: saved.originalFileName,
                savedRecording: saved,
                course: course,
                chapter: session.chapter,
                session: session,
                note: nil,
                source: .imported,
                languageIdentifier: selectedLanguageIdentifier,
                in: modelContext,
                fileStore: fileStore
            )
            audioMessage = "Audio imported. Transcription started."
            Task {
                do {
                    try await transcriptionService.transcribe(
                        recording: recording,
                        in: modelContext,
                        fileStore: fileStore,
                        languageIdentifier: selectedLanguageIdentifier
                    )
                    audioMessage = "Transcription completed."
                } catch {
                    audioMessage = "Audio saved. Transcription failed: \(error.localizedDescription)"
                }
            }
        } catch {
            audioMessage = error.localizedDescription
        }
    }
}

private struct SessionLectureRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: ClassSession
    let languageIdentifier: String
    @State private var recorder = CourseAudioRecorder()
    @State private var title: String
    @State private var message: String?
    @State private var savedRecording: CourseRecording?
    @State private var isTranscribing = false
    private let fileStore = AcademicFileStore()
    private let transcriptionService = NativeSpeechTranscriptionService()

    init(session: ClassSession, languageIdentifier: String) {
        self.session = session
        self.languageIdentifier = languageIdentifier
        _title = State(initialValue: "\(session.title) recording")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Recording title", text: $title)
                        .textFieldStyle(.roundedBorder)
                    Text(permissionExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .deskCard()

                VStack(spacing: 16) {
                    HStack {
                        Label(statusTitle, systemImage: statusImage)
                            .font(.headline)
                        Spacer()
                        Text(formatDuration(recorder.elapsed))
                            .font(.title.monospacedDigit().weight(.bold))
                    }
                    ProgressView(value: normalizedLevel)
                        .tint(CourseColor.color(for: session.course?.colorIdentifier ?? "blueViolet"))
                    controls
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(message.localizedCaseInsensitiveContains("denied") ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .deskCard()

                if let savedRecording {
                    RecordingRow(recording: savedRecording)
                }

                Spacer()
            }
            .padding()
            .background(StudyDeskTheme.backgroundPrimary)
            .navigationTitle("Record Lecture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if savedRecording == nil {
                            recorder.cancel()
                        }
                        dismiss()
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                recorder.tick()
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            switch recorder.state {
            case .idle:
                Button("Start", systemImage: "record.circle") {
                    recorder.requestPermissionAndStart(title: title)
                }
                .buttonStyle(.borderedProminent)
            case .requestingPermission:
                Label("Requesting microphone access", systemImage: "mic")
                ProgressView()
            case .preparing:
                Label("Preparing recorder", systemImage: "waveform")
                ProgressView()
            case .recording:
                Button("Pause", systemImage: "pause.fill") { recorder.pause() }
                Button("Finish", systemImage: "stop.fill") { finishRecording() }
            case .paused:
                Button("Resume", systemImage: "play.fill") { recorder.resume() }
                Button("Finish", systemImage: "stop.fill") { finishRecording() }
            case .stopping:
                Label("Saving audio", systemImage: "externaldrive")
                ProgressView()
            case .saved:
                Label(isTranscribing ? "Transcribing" : "Audio saved", systemImage: isTranscribing ? "waveform.and.magnifyingglass" : "checkmark.circle.fill")
                if isTranscribing {
                    ProgressView()
                }
            case .denied(let deniedMessage), .failed(let deniedMessage):
                Text(deniedMessage)
                    .foregroundStyle(.red)
                Button("Try Again") { recorder.requestPermissionAndStart(title: title) }
            }
            if recorder.state.isActive {
                Button("Cancel", role: .destructive) {
                    recorder.cancel()
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var permissionExplanation: String {
        "UniSaver needs microphone access to record the lecture and Speech Recognition permission to transcribe it with Apple Speech. Audio is saved even if transcription fails."
    }

    private var normalizedLevel: Double {
        min(max(Double(recorder.level + 60) / 60, 0), 1)
    }

    private var statusTitle: String {
        switch recorder.state {
        case .idle: "Ready"
        case .requestingPermission: "Requesting Permission"
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .paused: "Paused"
        case .stopping: "Saving"
        case .saved: isTranscribing ? "Transcribing" : "Completed"
        case .denied: "Permission Denied"
        case .failed: "Failed"
        }
    }

    private var statusImage: String {
        switch recorder.state {
        case .idle: "record.circle"
        case .requestingPermission: "mic.badge.plus"
        case .preparing: "waveform"
        case .recording: "record.circle.fill"
        case .paused: "pause.circle"
        case .stopping: "externaldrive"
        case .saved: isTranscribing ? "waveform.and.magnifyingglass" : "checkmark.circle.fill"
        case .denied, .failed: "exclamationmark.triangle"
        }
    }

    private func finishRecording() {
        guard let course = session.course else {
            message = "This session is not linked to a course."
            return
        }
        recorder.stop()
        guard case .saved(let saved) = recorder.state else { return }
        do {
            let recording = try RecordingPersistenceService.createRecording(
                title: title,
                savedRecording: saved,
                course: course,
                chapter: session.chapter,
                session: session,
                note: nil,
                source: .recorded,
                languageIdentifier: languageIdentifier,
                in: modelContext,
                fileStore: fileStore
            )
            savedRecording = recording
            message = "Audio saved. Transcription started."
            isTranscribing = true
            Task {
                do {
                    try await transcriptionService.transcribe(
                        recording: recording,
                        in: modelContext,
                        fileStore: fileStore,
                        languageIdentifier: languageIdentifier
                    )
                    message = "Transcription completed."
                } catch {
                    message = "Audio saved. Transcription failed: \(error.localizedDescription)"
                }
                isTranscribing = false
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
