import SwiftUI
import SwiftData

/// Secondary coaching never owns a key, score or schedule. Only validated
/// annotations return to the already committed attempt.
struct QuizContextAssistance: View {
    @Environment(\.modelContext) private var context
    let question: BankQuestionSnapshot
    let submittedAnswer: String
    var courseID: UUID? = nil
    let courseName: String
    let chapterTitle: String
    var provisionalFeedback = false
    var onResponse: ((String) -> Void)? = nil
    var quizID: UUID? = nil
    var sessionID: UUID? = nil
    var onCoaching: ((RevisionErrorExplanation) -> Void)? = nil
    @State private var expanded = false
    @State private var similar = false
    @State private var request = "Explain my specific error and one way to check my reasoning."
    @State private var response: RevisionErrorExplanation?
    @State private var sources: [RevisionCoachingSourceReference] = []
    @State private var busy = false
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    @State private var sourceQuiz: Quiz?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Explain") { expanded = true; send() }.disabled(busy).accessibilityIdentifier("coachExplain")
                Button("Ask") { expanded.toggle() }.accessibilityIdentifier("coachAsk")
                if let sourceQuiz {
                    Button("Practise similar") { similar.toggle() }.accessibilityIdentifier("coachSimilarToggle")
                        .popover(isPresented: $similar) {
                            ScrollView { RevisionSimilarPracticeView(quiz: sourceQuiz, question: question, sessionID: sessionID).padding(20) }.frame(width: 620, height: 600)
                        }
                }
            }.buttonStyle(.bordered)
            if expanded {
                Text(provisionalFeedback ? "Provisional AI feedback · not an official grade" : "AI coaching · stored grading is unchanged").font(.caption).foregroundStyle(.secondary)
                TextField("Ask about this answer", text: $request)
                Button("Send") { send() }.disabled(busy)
                if busy { ProgressView() }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if let response {
                    Text(response.explanation).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if let issue = response.suspectedKeyIssue { Label("Suspected key issue · flagged for review", systemImage: "flag.fill"); Text(issue).font(.callout) }
                    DisclosureGroup("Sources") {
                        ForEach(sources.filter { response.sourceIDs.contains($0.id) }) { Text($0.reference).font(.caption) }
                    }
                }
            }
        }
        .onAppear { sourceQuiz = try? context.fetch(FetchDescriptor<Quiz>()).first { $0.id == quizID || $0.questions.contains { $0.id == question.id } } }
        .onChange(of: question.id) { _, _ in task?.cancel(); expanded = false; response = nil; message = nil; busy = false }
        .onDisappear { task?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .uniSaverConversationAccountChanged)) { _ in task?.cancel(); response = nil; expanded = false; similar = false; sourceQuiz = nil }
    }
    private func send() {
        guard let quiz = sourceQuiz else { message = "No saved source bank is available. The recorded correction remains available."; return }
        task?.cancel(); busy = true; message = nil
        let followup = request
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let evidence = try RevisionCoachingSources.build(quiz: quiz, question: question, sessionID: sessionID, context: context)
                let result = try await RevisionCoachingAI.explain(question: question, submittedAnswer: submittedAnswer, request: followup, context: evidence)
                try Task.checkCancellation()
                response = result; sources = evidence.references
                onResponse?(result.explanation); onCoaching?(result)
            } catch { if !Task.isCancelled { message = "AI coaching is unavailable. Your recorded correction, practice and review schedule still work." } }
        }
    }
}
