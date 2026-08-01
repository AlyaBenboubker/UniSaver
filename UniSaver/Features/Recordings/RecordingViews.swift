import SwiftData
import SwiftUI

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
    let recording: CourseRecording

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(CourseColor.color(for: recording.course?.colorIdentifier ?? "blueViolet"))
            VStack(alignment: .leading, spacing: 3) {
                Text(recording.title)
                    .font(.headline)
                Text([recording.course?.name, recording.chapter?.title, recording.session?.title].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(recording.duration, format: .number.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
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
                        .disabled(!canSave)
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
            Text(recorder.elapsed, format: .number.precision(.fractionLength(0)))
                .font(.largeTitle.monospacedDigit().weight(.bold))
            ProgressView(value: normalizedLevel)
                .tint(CourseColor.color(for: selectedCourse?.colorIdentifier ?? "blueViolet"))
            HStack {
                switch recorder.state {
                case .idle:
                    Button("Start", systemImage: "record.circle") { recorder.requestPermissionAndStart() }
                        .buttonStyle(.borderedProminent)
                case .recording:
                    Button("Pause", systemImage: "pause.fill") { recorder.pause() }
                    Button("Stop", systemImage: "stop.fill") { recorder.stop() }
                case .paused:
                    Button("Resume", systemImage: "play.fill") { recorder.resume() }
                    Button("Stop", systemImage: "stop.fill") { recorder.stop() }
                case .finished:
                    Label("Ready to save", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .unavailable(let message):
                    Text(message)
                        .foregroundStyle(.secondary)
                }
                Button("Cancel", role: .destructive) { recorder.cancel() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .deskCard()
    }

    private var normalizedLevel: Double {
        min(max(Double(recorder.level + 60) / 60, 0), 1)
    }

    private var canSave: Bool {
        guard selectedCourse != nil else { return false }
        if case .finished = recorder.state { return true }
        return false
    }

    private func saveRecording() {
        guard case .finished(let url, let duration) = recorder.state,
              let selectedCourse else { return }
        do {
            let stored = try fileStore.importFile(from: url)
            let recording = CourseRecording(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                storedRelativePath: stored.storedRelativePath,
                duration: duration,
                course: selectedCourse,
                chapter: initialChapter,
                session: initialSession
            )
            modelContext.insert(recording)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
