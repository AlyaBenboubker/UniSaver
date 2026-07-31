import SwiftData
import SwiftUI

struct SessionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let course: Course
    private let session: ClassSession?
    private let initialChapter: Chapter?

    @State private var title: String
    @State private var number: Int
    @State private var sessionDescription: String
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var room: String
    @State private var professorName: String
    @State private var attendanceStatus: AttendanceStatus
    @State private var progressStatus: SessionProgressStatus
    @State private var selectedChapterID: UUID?
    @State private var objectivesText: String
    @State private var conceptsText: String
    @State private var reviewTasksText: String
    @State private var errorMessage: String?

    init(course: Course, session: ClassSession? = nil, initialChapter: Chapter? = nil) {
        self.course = course
        self.session = session
        self.initialChapter = initialChapter
        let nextNumber = course.sessions.map(\.number).max().map { $0 + 1 } ?? 1
        let proposedStart = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        let proposedEnd = Calendar.current.date(byAdding: .minute, value: 90, to: proposedStart) ?? proposedStart.addingTimeInterval(5400)
        _title = State(initialValue: session?.title ?? "")
        _number = State(initialValue: session?.number ?? nextNumber)
        _sessionDescription = State(initialValue: session?.sessionDescription ?? "")
        _date = State(initialValue: session?.date ?? .now)
        _startTime = State(initialValue: session?.startTime ?? proposedStart)
        _endTime = State(initialValue: session?.endTime ?? proposedEnd)
        _room = State(initialValue: session?.room ?? course.defaultRoom ?? "")
        _professorName = State(initialValue: session?.professorName ?? course.professorName)
        _attendanceStatus = State(initialValue: session?.attendanceStatus ?? .planned)
        _progressStatus = State(initialValue: session?.progressStatus ?? .captured)
        _selectedChapterID = State(initialValue: session?.chapter?.id ?? initialChapter?.id)
        _objectivesText = State(initialValue: session?.learningObjectives.joined(separator: "\n") ?? "")
        _conceptsText = State(initialValue: session?.importantConcepts.joined(separator: "\n") ?? "")
        _reviewTasksText = State(initialValue: session?.reviewTasks.joined(separator: "\n") ?? "")
    }

    private var chapters: [Chapter] {
        course.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order }
    }

    private var selectedChapter: Chapter? {
        chapters.first { $0.id == selectedChapterID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Title", text: $title)
                    Stepper("Number \(number)", value: $number, in: 1...300)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    TextField("Room", text: $room)
                    TextField("Professor", text: $professorName)
                }

                Section("Academic context") {
                    Picker("Chapter", selection: $selectedChapterID) {
                        Text("No chapter").tag(UUID?.none)
                        ForEach(chapters) { chapter in
                            Text("\(chapter.number). \(chapter.title)").tag(Optional(chapter.id))
                        }
                    }
                    Picker("Attendance", selection: $attendanceStatus) {
                        ForEach(AttendanceStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Picker("Workflow progress", selection: $progressStatus) {
                        ForEach(SessionProgressStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                }

                Section("Notes for later") {
                    TextField("Description", text: $sessionDescription, axis: .vertical)
                    TextField("Learning objectives", text: $objectivesText, axis: .vertical)
                    TextField("Important concepts", text: $conceptsText, axis: .vertical)
                    TextField("Review tasks", text: $reviewTasksText, axis: .vertical)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(session == nil ? "New Session" : "Edit Session")
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
            let start = combined(date: date, time: startTime)
            let end = combined(date: date, time: endTime)
            try AcademicValidationService.validateSession(startTime: start, endTime: end, course: course, chapter: selectedChapter)
            if let session {
                session.title = title
                session.number = number
                session.sessionDescription = sessionDescription
                session.date = Calendar.current.startOfDay(for: date)
                session.startTime = start
                session.endTime = end
                session.room = room.emptyAsNil
                session.professorName = professorName.emptyAsNil
                session.attendanceStatus = attendanceStatus
                session.progressStatus = progressStatus
                session.chapter = selectedChapter
                session.learningObjectives = list(from: objectivesText)
                session.importantConcepts = list(from: conceptsText)
                session.reviewTasks = list(from: reviewTasksText)
                session.updatedAt = .now
            } else {
                let session = ClassSession(
                    number: number,
                    title: title,
                    sessionDescription: sessionDescription,
                    date: Calendar.current.startOfDay(for: date),
                    startTime: start,
                    endTime: end,
                    room: room.emptyAsNil,
                    professorName: professorName.emptyAsNil,
                    attendanceStatus: attendanceStatus,
                    learningObjectives: list(from: objectivesText),
                    importantConcepts: list(from: conceptsText),
                    reviewTasks: list(from: reviewTasksText),
                    progressStatus: progressStatus,
                    course: course,
                    chapter: selectedChapter
                )
                modelContext.insert(session)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func combined(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(from: DateComponents(
            year: dateComponents.year,
            month: dateComponents.month,
            day: dateComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute
        )) ?? date
    }

    private func list(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
