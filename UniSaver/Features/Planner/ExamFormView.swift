import SwiftData
import SwiftUI

struct ExamFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]

    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 12, to: .now) ?? .now
    @State private var startTime = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var endTime = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
    @State private var hasTime = true
    @State private var room = ""
    @State private var examType: ExamType = .midterm
    @State private var notes = ""
    @State private var selectedCourseID: UUID?
    @State private var errorMessage: String?

    init(initialCourse: Course? = nil) {
        _selectedCourseID = State(initialValue: initialCourse?.id)
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID } ?? courses.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exam") {
                    TextField("Title", text: $title)
                    Picker("Course", selection: $selectedCourseID) {
                        ForEach(courses.filter { !$0.isArchived }) { course in
                            Text(course.name).tag(Optional(course.id))
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Set time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                    TextField("Room", text: $room)
                    Picker("Type", selection: $examType) {
                        ForEach(ExamType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Exam")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCourse == nil)
                }
            }
        }
    }

    private func save() {
        guard let course = selectedCourse else { return }
        do {
            let start = hasTime ? combined(date: date, time: startTime) : nil
            let end = hasTime ? combined(date: date, time: endTime) : nil
            try AcademicValidationService.validateExam(title: title, startTime: start, endTime: end, course: course, chapters: [])
            modelContext.insert(Exam(title: title, date: Calendar.current.startOfDay(for: date), startTime: start, endTime: end, room: room.emptyAsNil, examType: examType, notes: notes, course: course))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func combined(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(from: DateComponents(year: dateComponents.year, month: dateComponents.month, day: dateComponents.day, hour: timeComponents.hour, minute: timeComponents.minute)) ?? date
    }
}
