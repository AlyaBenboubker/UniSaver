import SwiftUI
import SwiftData

struct RevisionHistoryView: View {
    var onOpenSession: ((UUID, UUID) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @State private var records: [RevisionSessionRecord] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Text("Revision History is saved on this Mac, separately for each account. Revision answers are not included in account sync. Earlier unowned study data is preserved separately.")
                    .font(.callout).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                if records.isEmpty { Text("No revision sessions for this account yet.") }
                ForEach(records) { session in
                    NavigationLink {
                        List {
                            Text(session.course + (session.chapter.isEmpty ? "" : " → " + session.chapter)).font(.headline)
                            if let quizID = session.quizID, let onOpenSession {
                                Button(session.isCompleted == false ? "Resume attempt" : "Open results") { onOpenSession(quizID, session.id) }.buttonStyle(.borderedProminent).accessibilityIdentifier("historyOpenSession")
                            }
                            if let coaching = session.coaching {
                                Text(coaching.summary)
                                if let recommendation = coaching.recommendation { Text(recommendation.reason).font(.callout) }
                            }
                            ForEach(session.answers) { answer in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(answer.question.prompt).font(.headline)
                                    Text((answer.course ?? session.course) + " → " + (answer.chapter ?? session.chapter)).font(.caption)
                                    Text("Topics: " + answer.question.tags.joined(separator: ", "))
                                    Text("Your answer: " + (answer.submittedAnswer.isEmpty ? "—" : QuizScoringService.displayAnswer(question: answer.question.gradingQuestion(), answer: answer.submittedAnswer)))
                                    Text((session.isCompleted == false && answer.submittedAt == nil && !answer.submittedAnswer.isEmpty ? "Draft saved" : answer.result) + (answer.flaggedForReview ? " · Flagged for review" : ""))
                                    if answer.submittedAt != nil && answer.result != "Awaiting grading" {
                                        Text("Correction: " + QuizScoringService.displayAnswer(question: answer.question.gradingQuestion(), answer: answer.question.correctAnswers.joined(separator: ",")))
                                        Text(answer.question.explanation)
                                        if let rubric = answer.question.rubric { Text("Rubric: " + rubric) }
                                    }
                                    if answer.result == "Written response · needs review" { Text("Written marks pending review. AI feedback is provisional, not an official grade.").foregroundStyle(.secondary) }
                                    if let issue = answer.suspectedKeyIssue { Text("Suspected key issue · review requested: " + issue) }
                                    if let explanation = answer.coachingExplanation { Text(explanation) }
                                    if let detail = answer.gradingDetail { Text("Assessment: " + detail) }
                                    if let earned = answer.pointsEarned, let available = answer.pointsAvailable { Text("\(earned) / \(available) points") }
                                    Text("\(answer.gradingMethod) · \(Int(answer.activeSeconds)) active seconds · Hint: \(answer.hintRevealed ? "yes" : "no") · Model answer: \(answer.modelAnswerRevealed ? "yes" : "no")")
                                    Text("Question version: " + String(answer.questionVersion.prefix(12))).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 8).textSelection(.enabled)
                            }
                        }.navigationTitle(session.activity)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.activity).font(.headline)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened) + " · " + session.course)
                            if session.isCompleted == false { Text("Unfinished · \(session.answers.filter { !$0.submittedAnswer.isEmpty }.count) draft answers saved").foregroundStyle(.secondary) }
                            Text("\(session.answers.filter { $0.submittedAt != nil && $0.result != "Skipped" }.count) answered · \(session.answers.filter { $0.result.hasPrefix("Correct") }.count) correct · \(session.answers.filter { $0.result == "Incorrect" }.count) incorrect")
                        }
                    }
                }
            }.navigationTitle("Revision History")
        }
        .onAppear(perform: reload)
        .onChange(of: notes.map(\.updatedAt)) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .uniSaverConversationAccountChanged)) { _ in reload() }
    }
    private func reload() {
        do { records = try RevisionHistoryService.records(context: context); error = nil }
        catch { records = []; self.error = "History could not be read; saved data has been preserved. " + error.localizedDescription }
    }
}
