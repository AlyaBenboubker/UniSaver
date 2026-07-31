import SwiftData
import SwiftUI

struct TaskFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]

    private let task: AcademicTask?
    @State private var title: String
    @State private var taskDescription: String
    @State private var dueDate: Date
    @State private var priority: AcademicTaskPriority
    @State private var status: AcademicTaskStatus
    @State private var estimatedMinutes: Double
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var errorMessage: String?

    init(task: AcademicTask? = nil, initialCourse: Course? = nil, initialChapter: Chapter? = nil, initialSession: ClassSession? = nil) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _taskDescription = State(initialValue: task?.taskDescription ?? "")
        _dueDate = State(initialValue: task?.dueDate ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        _priority = State(initialValue: task?.priority ?? .medium)
        _status = State(initialValue: task?.status ?? .todo)
        _estimatedMinutes = State(initialValue: (task?.estimatedDuration ?? 3600) / 60)
        _selectedCourseID = State(initialValue: task?.course?.id ?? initialCourse?.id ?? initialSession?.course?.id)
        _selectedChapterID = State(initialValue: task?.chapter?.id ?? initialChapter?.id ?? initialSession?.chapter?.id)
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    private var availableChapters: [Chapter] {
        selectedCourse?.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order } ?? []
    }

    private var selectedChapter: Chapter? {
        availableChapters.first { $0.id == selectedChapterID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $taskDescription, axis: .vertical)
                    DatePicker("Due", selection: $dueDate)
                    Picker("Priority", selection: $priority) {
                        ForEach(AcademicTaskPriority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(AcademicTaskStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Stepper("Estimated \(Int(estimatedMinutes)) min", value: $estimatedMinutes, in: 15...480, step: 15)
                }

                Section("Context") {
                    Picker("Course", selection: $selectedCourseID) {
                        Text("General").tag(UUID?.none)
                        ForEach(courses.filter { !$0.isArchived }) { course in
                            Text(course.name).tag(Optional(course.id))
                        }
                    }
                    Picker("Chapter", selection: $selectedChapterID) {
                        Text("No chapter").tag(UUID?.none)
                        ForEach(availableChapters) { chapter in
                            Text(chapter.title).tag(Optional(chapter.id))
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            let duration = estimatedMinutes * 60
            try AcademicValidationService.validateTask(title: title, estimatedDuration: duration, course: selectedCourse, chapter: selectedChapter)
            if let task {
                task.title = title
                task.taskDescription = taskDescription
                task.dueDate = dueDate
                task.priority = priority
                task.status = status
                task.estimatedDuration = duration
                task.course = selectedCourse
                task.chapter = selectedChapter
                task.updatedAt = .now
            } else {
                modelContext.insert(AcademicTask(title: title, taskDescription: taskDescription, dueDate: dueDate, priority: priority, status: status, estimatedDuration: duration, course: selectedCourse, chapter: selectedChapter))
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
