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

    init(initialCourse: Course? = nil, initialTask: AcademicTask? = nil, initialDate: Date? = nil) {
        self.initialTask = initialTask
        _selectedCourseID = State(initialValue: initialCourse?.id ?? initialTask?.course?.id)
        _title = State(initialValue: initialTask.map { "Work on \($0.title)" } ?? "")
        if let initialDate {
            let start = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: initialDate) ?? initialDate
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: start.addingTimeInterval(3600))
        }
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    var body: some View {
        CreationWindow(
            icon: "timer",
            title: "Planifier une révision",
            subtitle: "Choisis un créneau clair. Il apparaîtra dans Planner et comptera quand il sera terminé.",
            accent: CourseColor.rose.color,
            closeAction: { dismiss() }
        ) {
            CreationCard("Révision") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Titre", text: $title)
                        .textFieldStyle(.roundedBorder)
                    DatePicker("Début", selection: $startDate)
                    DatePicker("Fin", selection: $endDate)
                    Picker("État", selection: $status) {
                        ForEach(StudyBlockStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Picker("Matière", selection: $selectedCourseID) {
                        Text("Général").tag(UUID?.none)
                        ForEach(courses.filter { !$0.isArchived }) { course in
                            Text(course.name).tag(Optional(course.id))
                        }
                    }
                }
            }
            if let initialTask {
                CreationCard("Tâche liée") {
                    Label(initialTask.title, systemImage: "checklist")
                }
            }
            if let errorMessage {
                CreationErrorText(message: errorMessage)
            }
        } footer: {
            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.bordered)
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Titre requis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CreationPrimaryButton(title: "Enregistrer", systemImage: "checkmark.circle.fill", accent: CourseColor.rose.color, isDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: save)
            }
        }
        .frame(minWidth: 560, idealWidth: 660, minHeight: 480, idealHeight: 560)
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
