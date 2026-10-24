#if DEBUG
import SwiftUI
import SwiftData

/// An isolated visual fixture, never connected to the student's persistent store.
struct RevisionValidationView: View {
    private let container: ModelContainer
    private let course: Course
    init() {
        container = try! ModelContainer(for: PersistenceController.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        course = Course(name: "Accounting II", code: "VISUAL")
        context.insert(course)
        let quiz = Quiz(title: "Consolidation – Test 2", course: course)
        context.insert(quiz)
        let question = QuizQuestion(prompt: "What do consolidated financial statements aim to show?", choices: ["A: The parent company’s financial position without its investments", "B: The group’s financial position and performance as if it were one economic entity", "C: Only transactions between companies belonging to the group", "D: The combined market value of all companies in which the parent owns shares"], correctAnswers: ["B"], explanation: "Consolidation presents the parent and its subsidiaries as one economic entity, eliminating internal balances and transactions.", hint: "Consider the reporting entity rather than the legal entities.", tags: ["Accounting II", "Control", "Group structure"], quiz: quiz)
        context.insert(question)
        context.insert(QuizQuestion(prompt: "A parent acquires an interest in a subsidiary during the reporting year. When preparing consolidated statements, consider the acquisition date, the fair value of identifiable net assets, the non-controlling interest and subsequent intragroup transactions. Which accounting principle determines the date from which the subsidiary’s results are included in the consolidated financial statements? Explain how the existence of control affects the reporting boundary.", choices: ["A: The date control is obtained", "B: The end of the financial year", "C: The date of the next dividend", "D: The date of the first intragroup sale"], correctAnswers: ["A"], explanation: "Consolidation begins when the parent obtains control.", position: 1, tags: ["Acquisition", "Control"], quiz: quiz))
        let profile = AdaptiveExamProfile(courseID: course.id, courseName: course.name, concepts: [
            AdaptiveConcept(name: "Control and group structure", mergedNames: ["Control", "Group structure"]),
            AdaptiveConcept(name: "Acquisition and goodwill", mergedNames: ["Acquisition", "Goodwill"]),
            AdaptiveConcept(name: "Full consolidation and non-controlling interests", mergedNames: ["NCI", "Full consolidation"]),
            AdaptiveConcept(name: "Intragroup transactions", mergedNames: ["Intragroup"]),
            AdaptiveConcept(name: "Equity method", mergedNames: ["Equity method"])
        ])
        AdaptiveExamPrepStore.save(profile, course: course, notes: [], context: context)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Visual verification · isolated sample data").font(.caption).foregroundStyle(.secondary).padding(10)
            CourseStudyView(course: course)
        }.modelContainer(container).frame(minWidth: 1100, minHeight: 780)
    }
}
#endif
