import SwiftData
import SwiftUI

enum QuickAddTarget: Identifiable {
    case course(Semester?)
    case chapter(Course?)
    case session(Course?, Chapter?)
    case disabled(String)

    var id: String {
        switch self {
        case .course(let semester): "course-\(semester?.id.uuidString ?? "none")"
        case .chapter(let course): "chapter-\(course?.id.uuidString ?? "none")"
        case .session(let course, let chapter): "session-\(course?.id.uuidString ?? "none")-\(chapter?.id.uuidString ?? "none")"
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
            disabled("Upload PDF", "Documents arrive in Lot 1.")
            disabled("New Note", "Notes arrive in Lot 2.")
            disabled("New Task", "Planner tasks arrive in Lot 3.")
            disabled("New Exam", "Planner exams arrive in Lot 3.")
            disabled("Create Flashcards", "Study Studio arrives in Lot 4.")
            disabled("Create Quiz", "Study Studio arrives in Lot 4.")
        }
    }

    private func disabled(_ title: String, _ reason: String) -> some View {
        Label(title, systemImage: "lock")
            .foregroundStyle(.secondary)
            .help(reason)
    }
}
