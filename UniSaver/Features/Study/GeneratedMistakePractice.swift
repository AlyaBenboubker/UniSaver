import SwiftUI
import SwiftData

/// Kept for older study surfaces. The real preview and save path is shared.
struct GeneratedMistakePractice: View {
    let quiz: Quiz
    let mistakes: [BankQuestionSnapshot]
    var body: some View {
        if let question = mistakes.first { RevisionSimilarPracticeView(quiz: quiz, question: question) }
    }
}

struct RevisionSimilarPracticeView: View {
    @Environment(\.modelContext) private var context
    let quiz: Quiz
    let question: BankQuestionSnapshot
    var sessionID: UUID? = nil
    @State private var preview: RevisionGenerationPreview?
    @State private var drafts: [RevisionGeneratedQuestion] = []
    @State private var reviewed = false
    @State private var busy = false
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    @State private var savedBank: Quiz?
    @State private var savedBankID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(busy ? "Preparing preview…" : "Practise similar") { generate() }
                .buttonStyle(.bordered).disabled(busy).accessibilityIdentifier("coachPractiseSimilar")
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let preview, !drafts.isEmpty {
                Text("AI practice preview · check the questions and keys").font(.headline)
                Text(preview.difficultyReason).font(.callout).foregroundStyle(.secondary)
                Text("Relative level \(preview.difficultyLevel)/5 · \(preview.provider) · \(preview.model)").font(.caption)
                ForEach($drafts) { $draft in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(draft.type.title + (draft.writtenResponse ? " · written review, no automatic grade" : "" )).font(.caption)
                        TextField("Question", text: $draft.prompt, axis: .vertical)
                        if !draft.choices.isEmpty { ForEach(draft.choices, id: \.self) { Text($0) } }
                        TextField("Answer key / model answer", text: Binding(get: { draft.correctAnswers.joined(separator: draft.type == .shortAnswer ? "\n" : ",") }, set: { draft.correctAnswers = draft.type == .shortAnswer ? [$0] : $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }), axis: .vertical)
                        TextField("Explanation", text: $draft.explanation, axis: .vertical)
                        if let rubric = draft.rubric { Text("Rubric: " + rubric) }
                        ForEach(preview.sources.filter { draft.sourceIDs.contains($0.id) }) { source in Text(source.reference).font(.caption).foregroundStyle(.secondary) }
                        Button("Discard", role: .destructive) { drafts.removeAll { $0.id == draft.id }; reviewed = false }
                    }.padding().deskCard()
                }
                Toggle("I reviewed these questions and their answer keys", isOn: $reviewed).accessibilityIdentifier("coachPreviewReviewed")
                Button("Save reviewed questions as AI practice") { save() }.disabled(!reviewed || savedBankID != nil).accessibilityIdentifier("coachSavePreview")
                if let savedBankID {
                    Button("Start similar practice") { savedBank = try? context.fetch(FetchDescriptor<Quiz>()).first { $0.id == savedBankID } }
                        .accessibilityIdentifier("coachStartSimilar")
                }
                DisclosureGroup("Generation sources and provenance") {
                    Text("Generated \(preview.generatedAt.formatted()) · \(preview.promptVersion)").font(.caption)
                    Text("Provided sources (a description is not a full document):").font(.caption)
                    ForEach(preview.sources) { Text($0.reference).font(.caption) }
                }
            }
        }
        .onChange(of: drafts) { _, _ in reviewed = false }
        .onDisappear { task?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .uniSaverConversationAccountChanged)) { _ in task?.cancel(); preview = nil; drafts = []; savedBank = nil; savedBankID = nil }
        .sheet(item: $savedBank) { QuizPracticeView(quiz: $0) }
    }
    private func generate() {
        task?.cancel(); busy = true; message = nil; savedBankID = nil; preview = nil; drafts = []; reviewed = false
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let sources = try RevisionCoachingSources.build(quiz: quiz, question: question, sessionID: sessionID, context: context)
                let result = try await RevisionGenerationService.generate(context: sources)
                try Task.checkCancellation()
                preview = result; drafts = result.questions
                message = "Nothing has been saved. Review before adding these to a separate AI practice bank."
            } catch { if !Task.isCancelled { message = "AI practice is unavailable. Your attempts and review schedule are saved; existing practice still works." } }
        }
    }
    private func save() {
        guard let preview else { return }
        do {
            savedBankID = try RevisionGenerationService.save(preview, reviewed: drafts, previewConfirmed: reviewed, context: context)
            message = "Saved separately from teacher mocks, with sources and generation provenance."
        } catch { message = error.localizedDescription }
    }
}
