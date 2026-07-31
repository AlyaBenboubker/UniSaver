import SwiftData
import SwiftUI

struct StudyBlockFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]

    @State private var title = ""
    @State private var startDate = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: .now) ?? .now
    @State private var endDate = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now) ?? .now
    @State private var status: StudyBlockStatus = .planned
    @State private var selectedCourseID: UUID?
    @State private var errorMessage: String?
    private let initialTask: AcademicTask?

    init(initialCourse: Course? = nil, initialTask: AcademicTask? = nil) {
        self.initialTask = initialTask
        _selectedCourseID = State(initialValue: initialCourse?.id ?? initialTask?.course?.id)
        _title = State(initialValue: initialTask.map { "Work on \($0.title)" } ?? "")
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Study Block") {
                    TextField("Title", text: $title)
                    DatePicker("Start", selection: $startDate)
                    DatePicker("End", selection: $endDate)
                    Picker("Status", selection: $status) {
                        ForEach(StudyBlockStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Picker("Course", selection: $selectedCourseID) {
                        Text("General").tag(UUID?.none)
                        ForEach(courses.filter { !$0.isArchived }) { course in
                            Text(course.name).tag(Optional(course.id))
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Study Block")
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
            try AcademicValidationService.validateStudyBlock(title: title, startDate: startDate, endDate: endDate)
            modelContext.insert(StudyBlock(title: title, startDate: startDate, endDate: endDate, status: status, course: selectedCourse, task: initialTask))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
