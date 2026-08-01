import SwiftData
import SwiftUI

enum QuickAddTarget: Identifiable {
    case course(Semester?)
    case chapter(Course?)
    case session(Course?, Chapter?)
    case task(Course?, Chapter?, ClassSession?)
    case exam(Course?)
    case studyBlock(Course?, AcademicTask?)
    case resource(Course?, Chapter?, ClassSession?)
    case note(Course?, Chapter?, ClassSession?, AcademicResource?)
    case recording(Course?, Chapter?, ClassSession?)
    case disabled(String)

    var id: String {
        switch self {
        case .course(let semester): "course-\(semester?.id.uuidString ?? "none")"
        case .chapter(let course): "chapter-\(course?.id.uuidString ?? "none")"
        case .session(let course, let chapter): "session-\(course?.id.uuidString ?? "none")-\(chapter?.id.uuidString ?? "none")"
        case .task(let course, let chapter, let session): "task-\(course?.id.uuidString ?? "none")-\(chapter?.id.uuidString ?? "none")-\(session?.id.uuidString ?? "none")"
        case .exam(let course): "exam-\(course?.id.uuidString ?? "none")"
        case .studyBlock(let course, let task): "study-\(course?.id.uuidString ?? "none")-\(task?.id.uuidString ?? "none")"
        case .resource(let course, let chapter, let session): "resource-\(course?.id.uuidString ?? "none")-\(chapter?.id.uuidString ?? "none")-\(session?.id.uuidString ?? "none")"
        case .note(let course, let chapter, let session, let resource): "note-\(course?.id.uuidString ?? "none")-\(chapter?.id.uuidString ?? "none")-\(session?.id.uuidString ?? "none")-\(resource?.id.uuidString ?? "none")"
        case .recording(let course, let chapter, let session): "recording-\(course?.id.uuidString ?? "none")-\(chapter?.id.uuidString ?? "none")-\(session?.id.uuidString ?? "none")"
        case .disabled(let title): "disabled-\(title)"
        }
    }
}

struct QuickAddSheet: View {
    let target: QuickAddTarget

    var body: some View {
        switch target {
        case .course(let semester):
            CourseFormView(initialSemester: semester)
        case .chapter(let course):
            if let course {
                ChapterFormView(course: course)
            } else {
                MissingContextView(title: "Choose a course first", message: "A chapter must belong to a course.")
            }
        case .session(let course, let chapter):
            if let course {
                SessionFormView(course: course, initialChapter: chapter)
            } else {
                MissingContextView(title: "Choose a course first", message: "A session must belong to a course.")
            }
        case .task(let course, let chapter, let session):
            TaskFormView(initialCourse: course, initialChapter: chapter, initialSession: session)
        case .exam(let course):
            ExamFormView(initialCourse: course)
        case .studyBlock(let course, let task):
            StudyBlockFormView(initialCourse: course, initialTask: task)
        case .resource(let course, let chapter, let session):
            ResourceImportView(initialCourse: course, initialChapter: chapter, initialSession: session)
        case .note(let course, let chapter, let session, let resource):
            QuickNoteCreatorView(initialCourse: course, initialChapter: chapter, initialSession: session, initialResource: resource)
        case .recording(let course, let chapter, let session):
            RecordingFormView(initialCourse: course, initialChapter: chapter, initialSession: session)
        case .disabled(let title):
            MissingContextView(title: title, message: "This option is documented for a future lot and is intentionally disabled in this build.")
        }
    }
}

struct MissingContextView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(title: title, message: message, systemImage: "info.circle")
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 360, minHeight: 260)
    }
}

struct FutureQuickAddOptions: View {
    var body: some View {
        Section("Later lots") {
            disabled("Import PDF", "The real PDF reader arrives in the Documents lot.")
            disabled("New Note", "Notes arrive in Lot 2.")
            disabled("Create Flashcards", "Study Studio arrives in Lot 4.")
            disabled("Create Quiz", "Study Studio arrives in Lot 4.")
            disabled("Start Recording", "Recordings arrive in Lot 6.")
        }
    }

    private func disabled(_ title: String, _ reason: String) -> some View {
        Label(title, systemImage: "lock")
            .foregroundStyle(.secondary)
            .help(reason)
    }
}

struct QuickNoteCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let initialCourse: Course?
    let initialChapter: Chapter?
    let initialSession: ClassSession?
    let initialResource: AcademicResource?
    @State private var note: StudyNote?

    var body: some View {
        NavigationStack {
            Group {
                if let note {
                    NoteEditorView(note: note)
                } else {
                    ProgressView("Creating note...")
                        .task {
                            createNote()
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func createNote() {
        guard note == nil else { return }
        let created = StudyNote(
            title: initialResource.map { "Notes on \($0.title)" } ?? "Untitled note",
            course: initialCourse ?? initialResource?.course,
            chapter: initialChapter ?? initialResource?.chapter,
            session: initialSession ?? initialResource?.session,
            resource: initialResource
        )
        modelContext.insert(created)
        try? modelContext.save()
        note = created
    }
}

struct QuickAddMenu: View {
    @Query(sort: \Course.name) private var courses: [Course]
    @Binding var quickAddTarget: QuickAddTarget?

    private var defaultCourse: Course? {
        courses.first { !$0.isArchived } ?? courses.first
    }

    var body: some View {
        Menu {
            Button("New Course", systemImage: "books.vertical") {
                quickAddTarget = .course(nil)
            }
            Button("New Chapter", systemImage: "list.number") {
                quickAddTarget = .chapter(defaultCourse)
            }
            .disabled(defaultCourse == nil)
            .help(defaultCourse == nil ? "Create a course before adding chapters." : "Add a chapter to the current course.")
            Button("New Session", systemImage: "calendar.badge.plus") {
                quickAddTarget = .session(defaultCourse, nil)
            }
            .disabled(defaultCourse == nil)
            .help(defaultCourse == nil ? "Create a course before scheduling sessions." : "Schedule a session for the current course.")
            Divider()
            Button("New Task", systemImage: "checklist") {
                quickAddTarget = .task(defaultCourse, nil, nil)
            }
            Button("New Exam", systemImage: "graduationcap") {
                quickAddTarget = .exam(defaultCourse)
            }
            .disabled(defaultCourse == nil)
            .help(defaultCourse == nil ? "Create a course before adding an exam." : "Add an exam for the current course.")
            Button("New Study Block", systemImage: "timer") {
                quickAddTarget = .studyBlock(defaultCourse, nil)
            }
            Divider()
            Button("Import PDF/File", systemImage: "square.and.arrow.down") {
                quickAddTarget = .resource(defaultCourse, nil, nil)
            }
            Button("New Note", systemImage: "note.text") {
                quickAddTarget = .note(defaultCourse, nil, nil, nil)
            }
            Button("Start Recording", systemImage: "waveform") {
                quickAddTarget = .recording(defaultCourse, nil, nil)
            }
            .disabled(defaultCourse == nil)
            .help(defaultCourse == nil ? "Choose a course before recording." : "Record audio for the current course.")
            Divider()
            Label("Create Flashcards", systemImage: "lock")
                .foregroundStyle(.secondary)
            Label("Create Quiz", systemImage: "lock")
                .foregroundStyle(.secondary)
            if defaultCourse == nil {
                Divider()
                Text("Course-specific actions unlock after you create a course.")
            }
        } label: {
            Label("Quick Add", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: [.command])
    }
}
