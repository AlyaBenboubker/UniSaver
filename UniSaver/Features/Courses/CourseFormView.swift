import SwiftData
import SwiftUI

struct CourseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Semester.order) private var semesters: [Semester]

    private let course: Course?
    private let initialSemester: Semester?

    @State private var name: String
    @State private var code: String
    @State private var courseDescription: String
    @State private var professorName: String
    @State private var professorEmail: String
    @State private var defaultRoom: String
    @State private var colorIdentifier: String
    @State private var symbolName: String
    @State private var credits: Double?
    @State private var evaluationMethod: String
    @State private var status: AcademicItemStatus
    @State private var errorMessage: String?

    init(course: Course? = nil, initialSemester: Semester? = nil) {
        self.course = course
        self.initialSemester = initialSemester
        _name = State(initialValue: course?.name ?? "")
        _code = State(initialValue: course?.code ?? "")
        _courseDescription = State(initialValue: course?.courseDescription ?? "")
        _professorName = State(initialValue: course?.professorName ?? "")
        _professorEmail = State(initialValue: course?.professorEmail ?? "")
        _defaultRoom = State(initialValue: course?.defaultRoom ?? "")
        _colorIdentifier = State(initialValue: course?.colorIdentifier ?? CourseColor.blueViolet.rawValue)
        _symbolName = State(initialValue: course?.symbolName ?? "book.closed")
        _credits = State(initialValue: course?.credits)
        _evaluationMethod = State(initialValue: course?.evaluationMethod ?? "")
        _status = State(initialValue: course?.status ?? .notStarted)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                    TextField("Code", text: $code)
                    TextField("Professor", text: $professorName)
                    TextField("Email", text: $professorEmail)
                        .textContentType(.emailAddress)
                    TextField("Default room", text: $defaultRoom)
                    TextField("Symbol", text: $symbolName)
                }

                Section("Details") {
                    TextField("Description", text: $courseDescription, axis: .vertical)
                    TextField("Evaluation method", text: $evaluationMethod, axis: .vertical)
                    Picker("Status", selection: $status) {
                        ForEach(AcademicItemStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Picker("Color", selection: $colorIdentifier) {
                        ForEach(CourseColor.allCases) { item in
                            HStack {
                                Circle().fill(item.color).frame(width: 12, height: 12)
                                Text(item.rawValue)
                            }
                            .tag(item.rawValue)
                        }
                    }
                    TextField("Credits", value: $credits, format: .number)
                }

                FutureQuickAddOptions()

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(course == nil ? "New Course" : "Edit Course")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            try AcademicValidationService.validateAcademicYear(name: name, startDate: .now, endDate: .now.addingTimeInterval(1))
            let targetSemester = course?.semester ?? initialSemester ?? semesters.first(where: { $0.status == .active }) ?? createDefaultSemester()

            if let course {
                course.name = name
                course.code = code
                course.courseDescription = courseDescription
                course.professorName = professorName
                course.professorEmail = professorEmail.emptyAsNil
                course.defaultRoom = defaultRoom.emptyAsNil
                course.colorIdentifier = colorIdentifier
                course.symbolName = symbolName.emptyAsNil
                course.credits = credits
                course.evaluationMethod = evaluationMethod.emptyAsNil
                course.status = status
                course.updatedAt = .now
            } else {
                let newCourse = Course(
                    name: name,
                    code: code,
                    courseDescription: courseDescription,
                    professorName: professorName,
                    professorEmail: professorEmail.emptyAsNil,
                    defaultRoom: defaultRoom.emptyAsNil,
                    colorIdentifier: colorIdentifier,
                    symbolName: symbolName.emptyAsNil,
                    credits: credits,
                    evaluationMethod: evaluationMethod.emptyAsNil,
                    status: status,
                    semester: targetSemester
                )
                modelContext.insert(newCourse)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createDefaultSemester() -> Semester {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let academicEnd = calendar.date(byAdding: .month, value: 10, to: start) ?? start.addingTimeInterval(30_000_000)
        let semesterEnd = calendar.date(byAdding: .month, value: 4, to: start) ?? academicEnd
        let year = AcademicYear(name: "Academic Year \(calendar.component(.year, from: start))", startDate: start, endDate: academicEnd)
        let semester = Semester(name: "Current Semester", order: 1, startDate: start, endDate: semesterEnd, academicYear: year)
        modelContext.insert(year)
        modelContext.insert(semester)
        return semester
    }
}

extension String {
    var emptyAsNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
