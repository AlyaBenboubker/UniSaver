import SwiftUI

struct PlaceholderFeatureView: View {
    let section: AppSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: section.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                        .frame(width: 44, height: 44)
                        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title3.weight(.bold))
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if section == .study {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Future capabilities")
                            .font(.headline)
                        Text("Flashcards, QCM, quizzes, spaced repetition, and error tracking will arrive in a later lot.")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))

                    Button("Back to Classes", systemImage: "books.vertical") {
                        NotificationCenter.default.post(name: .selectAppSection, object: AppSection.classes)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Back to Today", systemImage: "sun.max") {
                        NotificationCenter.default.post(name: .selectAppSection, object: AppSection.today)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .navigationTitle(section.title)
    }

    private var title: String {
        if section == .study {
            return "Study Studio arrives in a later lot"
        }
        return "\(section.title) is planned"
    }

    private var message: String {
        switch section {
        case .planner:
            "Tasks, assignments, exams, calendar planning, and notifications will be built from the dashboard models already in place."
        case .progress:
            "Progress will summarize structural workflow data without inventing academic mastery."
        case .library:
            "Documents, PDF reading, and resource organization arrive in the Documents lot."
        case .study:
            "The dashboard can show demo study counts, but the real study engine is not implemented yet."
        default:
            "This section is reserved for a later lot."
        }
    }
}
