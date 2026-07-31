import SwiftData
import SwiftUI

struct ChapterFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let course: Course
    private let chapter: Chapter?

    @State private var title: String
    @State private var number: Int
    @State private var chapterDescription: String
    @State private var status: AcademicItemStatus
    @State private var objectivesText: String

    init(course: Course, chapter: Chapter? = nil) {
        self.course = course
        self.chapter = chapter
        let nextNumber = course.chapters.map(\.number).max().map { $0 + 1 } ?? 1
        _title = State(initialValue: chapter?.title ?? "")
        _number = State(initialValue: chapter?.number ?? nextNumber)
        _chapterDescription = State(initialValue: chapter?.chapterDescription ?? "")
        _status = State(initialValue: chapter?.status ?? .notStarted)
        _objectivesText = State(initialValue: chapter?.learningObjectives.joined(separator: "\n") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chapter") {
                    TextField("Title", text: $title)
                    Stepper("Number \(number)", value: $number, in: 1...200)
                    TextField("Description", text: $chapterDescription, axis: .vertical)
                    Picker("Status", selection: $status) {
                        ForEach(AcademicItemStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    TextField("Learning objectives, one per line", text: $objectivesText, axis: .vertical)
                }
            }
            .navigationTitle(chapter == nil ? "New Chapter" : "Edit Chapter")
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
        let objectives = objectivesText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let chapter {
            chapter.title = title
            chapter.number = number
            chapter.order = number
            chapter.chapterDescription = chapterDescription
            chapter.learningObjectives = objectives
            chapter.status = status
            chapter.updatedAt = .now
        } else {
            let chapter = Chapter(number: number, title: title, chapterDescription: chapterDescription, learningObjectives: objectives, order: number, status: status, course: course)
            modelContext.insert(chapter)
        }
        dismiss()
    }
}
