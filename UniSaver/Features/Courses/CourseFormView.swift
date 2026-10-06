import SwiftData
import SwiftUI

enum CourseFormMode {
    case create(Semester?)
    case createPrefilled(CourseFormPrefill)
    case edit(Course)

    var course: Course? {
        if case .edit(let course) = self { return course }
        return nil
    }

    var initialSemester: Semester? {
        if case .create(let semester) = self { return semester }
        if case .createPrefilled(let prefill) = self { return prefill.semester }
        return nil
    }

    var title: String {
        course == nil ? "New Course" : "Edit Course"
    }

    var actionTitle: String {
        course == nil ? "Create Course" : "Save Changes"
    }
}

struct CourseFormPrefill {
    var name: String = ""
    var code: String = ""
    var professorName: String = ""
    var defaultRoom: String = ""
    var startDate: Date?
    var endDate: Date?
    var semester: Semester?
}

struct CourseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Semester.order) private var semesters: [Semester]
    @Query(sort: \Course.name) private var courses: [Course]

    private let mode: CourseFormMode

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
    @State private var hasStartDate: Bool
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var status: AcademicItemStatus
    @State private var selectedSemesterID: UUID?
    @State private var errorMessage: String?
    @State private var showsIconPicker = false
    @State private var showsTeachingDetails = false
    @State private var showsAppearance = false
    @State private var showsAcademicDetails = false

    init(mode: CourseFormMode) {
        self.mode = mode
        let course = mode.course
        let initialSemester = mode.initialSemester
        let prefill: CourseFormPrefill?
        if case .createPrefilled(let draft) = mode {
            prefill = draft
        } else {
            prefill = nil
        }
        _name = State(initialValue: course?.name ?? prefill?.name ?? "")
        _code = State(initialValue: course?.code ?? prefill?.code ?? "")
        _courseDescription = State(initialValue: course?.courseDescription ?? "")
        _professorName = State(initialValue: course?.professorName ?? prefill?.professorName ?? "")
        _professorEmail = State(initialValue: course?.professorEmail ?? "")
        _defaultRoom = State(initialValue: course?.defaultRoom ?? prefill?.defaultRoom ?? "")
        _colorIdentifier = State(initialValue: course?.colorIdentifier ?? CourseColor.blueViolet.rawValue)
        _symbolName = State(initialValue: CourseIconCatalog.sanitizedSymbolName(course?.symbolName))
        _credits = State(initialValue: course?.credits)
        _evaluationMethod = State(initialValue: course?.evaluationMethod ?? "")
        _hasStartDate = State(initialValue: course?.startDate != nil || prefill?.startDate != nil)
        _startDate = State(initialValue: course?.startDate ?? prefill?.startDate ?? Date())
        _hasEndDate = State(initialValue: course?.endDate != nil || prefill?.endDate != nil)
        _endDate = State(initialValue: course?.endDate ?? prefill?.endDate ?? Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date())
        _status = State(initialValue: course?.status ?? .notStarted)
        _selectedSemesterID = State(initialValue: course?.semester?.id ?? initialSemester?.id)
    }

    init(course: Course? = nil, initialSemester: Semester? = nil) {
        if let course {
            self.init(mode: .edit(course))
        } else {
            self.init(mode: .create(initialSemester))
        }
    }

    init(prefill: CourseFormPrefill) {
        self.init(mode: .createPrefilled(prefill))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CourseFormPreviewCard(
                        name: name,
                        code: code,
                        professorName: professorName,
                        symbolName: symbolName,
                        colorIdentifier: colorIdentifier
                    )

                    formSection("Essentiel") {
                        TextField("Nom du cours", text: $name)
                        TextField("Code", text: $code)
                        Picker("Semester", selection: $selectedSemesterID) {
                            Text("Current Semester").tag(UUID?.none)
                            ForEach(semesters) { semester in
                                Text(semester.name).tag(Optional(semester.id))
                            }
                        }
                    }

                    disclosureSection("Professeur et salle", isExpanded: $showsTeachingDetails) {
                        TextField("Professeur", text: $professorName)
                        TextField("Email", text: $professorEmail)
                            .textContentType(.emailAddress)
                        TextField("Salle par défaut", text: $defaultRoom)
                    }

                    disclosureSection("Apparence", isExpanded: $showsAppearance) {
                        Button {
                            showsIconPicker = true
                        } label: {
                            CourseAppearanceRow(symbolName: symbolName, colorIdentifier: colorIdentifier)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())

                        ColorSwatchPicker(selection: $colorIdentifier)
                    }

                    disclosureSection("Détails académiques", isExpanded: $showsAcademicDetails) {
                        Toggle("Date de début", isOn: $hasStartDate)
                        if hasStartDate {
                            DatePicker("Début", selection: $startDate, displayedComponents: .date)
                        }
                        Toggle("Date de fin", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("Fin", selection: $endDate, displayedComponents: .date)
                        }
                        Picker("Statut", selection: $status) {
                            ForEach(AcademicItemStatus.allCases) { status in
                                Text(status.title).tag(status)
                            }
                        }
                        TextField("Description", text: $courseDescription, axis: .vertical)
                            .lineLimit(3...6)
                        TextField("Méthode d’évaluation", text: $evaluationMethod, axis: .vertical)
                        TextField("Crédits", value: $credits, format: .number)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(20)
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
            }
            .background(StudyDeskTheme.backgroundPrimary)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.actionTitle) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .courseIconPickerPresentation(isPresented: $showsIconPicker) {
                CourseIconPickerView(selectedSymbolName: $symbolName, colorIdentifier: colorIdentifier)
            }
        }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .deskCard()
    }

    private func disclosureSection<Content: View>(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup(title, isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(.top, 10)
        }
        .font(.headline)
        .padding()
        .deskCard()
    }

    private func save() {
        do {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AcademicValidationError.emptyName
            }
            let selectedSemester = semesters.first { $0.id == selectedSemesterID }
            let targetSemester = selectedSemester ?? mode.course?.semester ?? mode.initialSemester ?? semesters.first(where: { $0.status == .active }) ?? createDefaultSemester()
            try validateUniqueCourseName(in: targetSemester)
            if hasStartDate && hasEndDate && endDate <= startDate {
                throw AcademicValidationError.invalidDateRange
            }

            let sanitizedSymbol = CourseIconCatalog.sanitizedSymbolName(symbolName)
            if let course = mode.course {
                course.name = name
                course.code = code
                course.courseDescription = courseDescription
                course.professorName = professorName
                course.professorEmail = professorEmail.emptyAsNil
                course.defaultRoom = defaultRoom.emptyAsNil
                course.colorIdentifier = colorIdentifier
                course.symbolName = sanitizedSymbol
                course.credits = credits
                course.evaluationMethod = evaluationMethod.emptyAsNil
                course.startDate = hasStartDate ? startDate : nil
                course.endDate = hasEndDate ? endDate : nil
                course.status = status
                course.semester = targetSemester
                course.updatedAt = .now
                try modelContext.save()
                NotificationCenter.default.post(name: .courseCreated, object: course)
            } else {
                let newCourse = Course(
                    name: name,
                    code: code,
                    courseDescription: courseDescription,
                    professorName: professorName,
                    professorEmail: professorEmail.emptyAsNil,
                    defaultRoom: defaultRoom.emptyAsNil,
                    colorIdentifier: colorIdentifier,
                    symbolName: sanitizedSymbol,
                    credits: credits,
                    evaluationMethod: evaluationMethod.emptyAsNil,
                    startDate: hasStartDate ? startDate : nil,
                    endDate: hasEndDate ? endDate : nil,
                    status: status,
                    semester: targetSemester
                )
                modelContext.insert(newCourse)
                try modelContext.save()
                NotificationCenter.default.post(name: .courseCreated, object: newCourse)
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

    private func validateUniqueCourseName(in semester: Semester) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let duplicate = courses.contains { candidate in
            guard candidate.id != mode.course?.id, candidate.semester?.id == semester.id else { return false }
            let sameName = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == normalizedName
            let sameCode = !normalizedCode.isEmpty && candidate.code.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == normalizedCode
            return sameName || sameCode
        }
        if duplicate {
            throw AcademicValidationError.duplicateCourse
        }
    }
}

private struct CourseAppearanceRow: View {
    let symbolName: String
    let colorIdentifier: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CourseColor.color(for: colorIdentifier).opacity(0.14))
                Image(systemName: CourseIconCatalog.sanitizedSymbolName(symbolName))
                    .foregroundStyle(CourseColor.color(for: colorIdentifier))
                    .font(.title3.weight(.semibold))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Course icon")
                    .font(.body.weight(.medium))
                Text(CourseIconCatalog.icon(for: CourseIconCatalog.sanitizedSymbolName(symbolName))?.title ?? "Default icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Course icon")
        .accessibilityValue(CourseIconCatalog.icon(for: CourseIconCatalog.sanitizedSymbolName(symbolName))?.title ?? "Default icon")
    }
}

private extension View {
    @ViewBuilder
    func courseIconPickerPresentation<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented) {
            content()
                .frame(minWidth: 760, minHeight: 620)
        }
        #endif
    }
}

private struct CourseFormPreviewCard: View {
    let name: String
    let code: String
    let professorName: String
    let symbolName: String
    let colorIdentifier: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CourseColor.color(for: colorIdentifier).opacity(0.14))
                Image(systemName: CourseIconCatalog.sanitizedSymbolName(symbolName))
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(CourseColor.color(for: colorIdentifier))
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Course name" : name)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                Text(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Course code" : code)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(CourseColor.color(for: colorIdentifier))
                Text(professorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Professor" : professorName)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .deskCard()
    }
}

private struct ColorSwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Course color")
                .font(.subheadline.weight(.medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                ForEach(CourseColor.allCases) { color in
                    Button {
                        selection = color.rawValue
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.color)
                                .frame(width: 34, height: 34)
                            if selection == color.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .overlay {
                            Circle()
                                .stroke(selection == color.rawValue ? StudyDeskTheme.textPrimary : StudyDeskTheme.borderSubtle, lineWidth: selection == color.rawValue ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.title)
                    .accessibilityValue(selection == color.rawValue ? "Selected" : "Not selected")
                }
            }
        }
    }
}

extension String {
    var emptyAsNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
