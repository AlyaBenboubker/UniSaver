import Foundation
import SwiftData
import Testing
@testable import UniSaver

@MainActor private final class CoachingFixtureProvider: RevisionCoachingProviding {
    var prompts: [String] = []
    var providedSources: [[AIRevisionSource]] = []
    var response: String
    var unavailable = false
    init(_ response: String = "") { self.response = response }
    func coaching(objective: String, courseName: String, chapterTitle: String, sources: [AIRevisionSource]) async throws -> AIRevisionResult {
        prompts.append(objective); providedSources.append(sources)
        if unavailable { throw AIRevisionError.notConfigured }
        return AIRevisionResult(content: response, provider: .openAI, model: "fixture-only", promptVersion: "fixture-v1")
    }
}

struct RevisionCoachingTests {
    @MainActor private func fixture() throws -> (ModelContext, Quiz) {
        let store = try ModelContainer(for: PersistenceController.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(store)
        let course = Course(name: "Biology", code: "BIO")
        let chapter = Chapter(number: 1, title: "Cells", order: 0, course: course)
        let quiz = Quiz(title: "Teacher transport paper", quizDescription: "UniSaverQuestionBankV1: original teacher paper", course: course, chapter: chapter)
        context.insert(course); context.insert(chapter); context.insert(quiz)
        for i in 0..<4 {
            context.insert(QuizQuestion(prompt: "Transport example \(i): choose the membrane.", choices: ["A: Membrane", "B: Nucleus"], correctAnswers: ["A"], explanation: "Membranes regulate transport; nuclei contain genetic material.", position: i, tags: ["Transport"], quiz: quiz))
        }
        try context.save()
        return (context, quiz)
    }
    @MainActor private func submit(_ positions: [Int], answers: [String], quiz: Quiz, context: ModelContext, immediate: UUID? = nil, hints: Bool = false) throws -> (QuestionBankLedger, UUID) {
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        let questions = quiz.questions.filter { positions.contains($0.position) }.sorted { $0.position < $1.position }
        let id = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: questions, mode: .mixed, context: context, immediateRetryOf: immediate)
        let i = try #require(ledger.sessions.firstIndex { $0.id == id })
        for j in ledger.sessions[i].questions.indices {
            ledger.sessions[i].questions[j].answer = answers[j]
            ledger.sessions[i].questions[j].hintsUsed = hints ? 1 : 0
            try QuestionBankSessionService.submit(&ledger.sessions[i].questions[j], mode: .mixed)
        }
        try QuestionBankSessionService.finish(&ledger.sessions[i])
        return (try QuestionBankSessionService.save(ledger, quiz: quiz, context: context), id)
    }
    @Test @MainActor func answerCommitSchedulesReviewRecommendsAndStartsRealPracticeIdempotently() throws {
        let (context, quiz) = try fixture()
        let (ledger, id) = try submit([0, 1], answers: ["B", "B"], quiz: quiz, context: context)
        let source = try #require(ledger.sessions.first { $0.id == id })
        #expect(source.reviewAfterAt != nil)
        let report = try #require(source.coaching)
        #expect(report.pattern.contains("2 recorded incorrect attempts across 2 different questions"))
        #expect(report.summary.hasPrefix("You practised 2 question(s)"))
        let recommendation = try #require(report.recommendation)
        #expect(recommendation.reason.contains("unresolved"))
        #expect(recommendation.difficultyLevel == 2)
        let (_, next, nextID) = try RevisionCoachingService.startRecommended(recommendation, context: context)
        #expect(nextID != id)
        #expect(next.sessions.last?.coachingOriginID == recommendation.id)
        #expect(next.sessions.last?.immediateRetryOf == id)
        #expect(next.sessions.last?.questions.contains { $0.id == source.questions[0].id } == true)
        let (_, same, sameID) = try RevisionCoachingService.startRecommended(recommendation, context: context)
        #expect(sameID == nextID)
        #expect(same.sessions.count == 2)
        #expect(same.dueIDs(now: Date().addingTimeInterval(86410)).contains(source.questions[0].id))
        let archived = try #require(try RevisionHistoryService.records(context: ModelContext(context.container)).first { $0.id == id })
        #expect(archived.coaching?.summary == report.summary)
        #expect(archived.reviewAfterAt == source.reviewAfterAt)
    }
    @Test @MainActor func singleMistakeAndRepeatedSameQuestionDoNotBecomeTopicWeaknesses() throws {
        let (context, quiz) = try fixture()
        let (one, first) = try submit([0], answers: ["B"], quiz: quiz, context: context)
        #expect(one.sessions.first { $0.id == first }?.coaching?.pattern.contains("One recorded mistake") == true)
        let (two, second) = try submit([0], answers: ["B"], quiz: quiz, context: context)
        #expect(two.sessions.first { $0.id == second }?.coaching?.pattern.contains("no repeated difficulty across different questions") == true)
        #expect(two.sessions.first { $0.id == second }?.coaching?.recommendation?.difficultyLevel == 3)
    }
    @Test @MainActor func difficultyRisesOnlyWithIndependentDemonstratedPerformance() throws {
        let (context, quiz) = try fixture()
        let (_, firstID) = try submit([0, 1], answers: ["A", "A"], quiz: quiz, context: context)
        let (immediate, immediateID) = try submit([2, 3], answers: ["A", "A"], quiz: quiz, context: context, immediate: firstID)
        #expect(immediate.sessions.first { $0.id == immediateID }?.coaching?.recommendation?.difficultyLevel == 3)
        let (helped, helpedID) = try submit([2, 3], answers: ["A", "A"], quiz: quiz, context: context, hints: true)
        #expect(helped.sessions.first { $0.id == helpedID }?.coaching?.recommendation?.difficultyLevel == 3)
        let (demonstrated, lastID) = try submit([2, 3], answers: ["A", "A"], quiz: quiz, context: context)
        let recommendation = try #require(demonstrated.sessions.first { $0.id == lastID }?.coaching?.recommendation)
        #expect(recommendation.difficultyLevel == 4)
        #expect(recommendation.difficultyReason.contains("Four unassisted"))
        // Harder material elsewhere in history must not make a scaffolded
        // current bank jump upward after mistakes.
        _ = try submit([0, 1], answers: ["B", "B"], quiz: quiz, context: context)
        let scaffolded = Quiz(title: "Scaffolded practice", quizDescription: "AI-generated practice", course: quiz.course, chapter: quiz.chapter)
        context.insert(scaffolded)
        let simple = QuizQuestion(prompt: "Choose a boundary.", choices: ["A: Membrane", "B: Nucleus"], correctAnswers: ["A"], explanation: "The membrane is the boundary.", tags: ["Transport", "AI-generated"], quiz: scaffolded)
        context.insert(simple)
        try ExamLabService.stage(ExamLabPaperMetadata(quizID: scaffolded.id, difficultyLevels: [simple.id: 1]), context: context)
        try context.save()
        let (lower, lowerID) = try submit([0], answers: ["B"], quiz: scaffolded, context: context)
        #expect(lower.sessions.first { $0.id == lowerID }?.coaching?.recommendation?.difficultyLevel == 1)
    }
    @Test @MainActor func questionEditsAndForeignAccountsRejectStaleRecommendations() throws {
        let (context, quiz) = try fixture()
        let (ledger, id) = try submit([0], answers: ["B"], quiz: quiz, context: context)
        let plan = try #require(ledger.sessions.first { $0.id == id }?.coaching?.recommendation)
        var foreign = plan; foreign.accountID = "another-account"
        #expect(throws: (any Error).self) { _ = try RevisionCoachingService.startRecommended(foreign, context: context) }
        let changed = try #require(quiz.questions.first { $0.position == 0 })
        changed.correctAnswers = ["B"]; try context.save()
        #expect(throws: (any Error).self) { _ = try RevisionCoachingService.startRecommended(plan, context: context) }
        let (_, nextID) = try submit([0], answers: ["B"], quiz: quiz, context: context)
        let record = try #require(try RevisionHistoryService.records(context: context).first { $0.id == nextID })
        #expect(record.coaching?.pattern.contains("No repeated difficulty") == true)
    }
    @Test @MainActor func suspectedKeyErrorsFlagReviewWithoutChangingGradingOrKeys() throws {
        let (context, quiz) = try fixture()
        var (ledger, id) = try submit([0, 1], answers: ["B", "B"], quiz: quiz, context: context)
        let i = try #require(ledger.sessions.firstIndex { $0.id == id })
        let plan = try #require(ledger.sessions[i].coaching?.recommendation)
        let questionID = ledger.sessions[i].questions[0].id
        ledger.sessions[i].questions[0].suspectedKeyIssue = "A supplied source appears to conflict; teacher review requested."
        ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        #expect(ledger.sessions[i].questions[0].correct == false)
        #expect(ledger.sessions[i].questions[0].question.correctAnswers == ["A"])
        #expect(ledger.sessions[i].questions[0].markedForReview == true)
        #expect(ledger.sessions[i].coaching?.evidence.contains { $0.questionID == questionID } == false)
        #expect(throws: (any Error).self) { _ = try RevisionCoachingService.startRecommended(plan, context: context) }
        let answer = try #require(try RevisionHistoryService.records(context: context).first { $0.id == id }?.answers.first { $0.id == questionID })
        #expect(answer.result == "Incorrect")
        #expect(answer.suspectedKeyIssue != nil)
    }
    @Test @MainActor func explanationUsesActualErrorLinkedMaterialsAndTeacherFormats() async throws {
        let (context, quiz) = try fixture()
        context.insert(StudyNote(title: "Transport notes", body: "The membrane regulates cell transport.", course: quiz.course, chapter: quiz.chapter))
        let other = Course(name: "Unrelated", code: "OTHER"); context.insert(other)
        context.insert(StudyNote(title: "Unrelated secret source", body: "Must not be sent.", course: other))
        context.insert(AcademicResource(title: "Teacher slides", resourceKind: .document, originalFileName: "slides.pdf", resourceDescription: "Transport slide description only.", storedRelativePath: "fixture.pdf", course: quiz.course, chapter: quiz.chapter))
        try context.save()
        let (ledger, id) = try submit([0], answers: ["B"], quiz: quiz, context: context)
        let run = try #require(ledger.sessions.first { $0.id == id }?.questions.first)
        let evidence = try RevisionCoachingSources.build(quiz: quiz, question: run.question, sessionID: id, context: context)
        #expect(evidence.sources.contains { $0.id.hasPrefix("note:") })
        #expect(evidence.sources.contains { $0.id.hasPrefix("teacher:") })
        #expect(evidence.sources.contains { $0.detail.contains("file contents were not loaded") })
        #expect(!evidence.sources.contains { $0.title == "Unrelated secret source" })
        let sourceID = try #require(evidence.sources.first?.id)
        let result = RevisionErrorExplanation(explanation: "You selected the nucleus, whose role differs from controlling membrane transport. Check which structure is the cell boundary.", sourceIDs: [sourceID], suspectedKeyIssue: nil)
        let provider = CoachingFixtureProvider(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
        let response = try await RevisionCoachingAI.explain(question: run.question, submittedAnswer: run.answer, request: "Explain", context: evidence, provider: provider)
        #expect(response.explanation.contains("selected the nucleus"))
        #expect(provider.prompts[0].contains("Submitted answer: B"))
        #expect(provider.prompts[0].contains("Never award marks"))
        #expect(provider.providedSources[0].contains { $0.id.hasPrefix("attempt:") && $0.text.contains("Submitted: B") })
    }
    @Test @MainActor func unavailableOrFabricatedAISourcesCannotBreakSavedPractice() async throws {
        let (context, quiz) = try fixture()
        let (ledger, id) = try submit([0], answers: ["B"], quiz: quiz, context: context)
        let run = try #require(ledger.sessions.first { $0.id == id }?.questions.first)
        let evidence = try RevisionCoachingSources.build(quiz: quiz, question: run.question, sessionID: id, context: context)
        let bad = RevisionErrorExplanation(explanation: "Unsupported", sourceIDs: ["invented-page-99"], suspectedKeyIssue: nil)
        let provider = CoachingFixtureProvider(String(decoding: try JSONEncoder().encode(bad), as: UTF8.self))
        await #expect(throws: (any Error).self) { _ = try await RevisionCoachingAI.explain(question: run.question, submittedAnswer: run.answer, request: "Explain", context: evidence, provider: provider) }
        provider.unavailable = true
        await #expect(throws: (any Error).self) { _ = try await RevisionGenerationService.generate(context: evidence, provider: provider) }
        let plan = try #require(ledger.sessions.first { $0.id == id }?.coaching?.recommendation)
        let (_, saved, nextID) = try RevisionCoachingService.startRecommended(plan, context: context)
        #expect(saved.sessions.contains { $0.id == nextID })
        #expect(try RevisionHistoryService.records(context: context).contains { $0.id == id })
    }
    @Test @MainActor func generationRequiresPreviewStoresProvenanceAndCannotOverwriteTeacherIDs() async throws {
        let (context, quiz) = try fixture()
        let (ledger, id) = try submit([0, 1], answers: ["B", "B"], quiz: quiz, context: context)
        let run = try #require(ledger.sessions.first { $0.id == id }?.questions.first)
        let evidence = try RevisionCoachingSources.build(quiz: quiz, question: run.question, sessionID: id, context: context)
        let sourceID = try #require(evidence.sources.first?.id)
        let drafts = (0..<3).map { index in
            RevisionGeneratedQuestion(id: index == 0 ? run.id : UUID(), prompt: "Similar transfer \(index)", type: .multipleChoice, choices: ["A: Boundary", "B: Centre"], correctAnswers: ["A"], explanation: "A cell boundary controls movement.", rubric: nil, writtenResponse: false, sourceIDs: [sourceID], difficultyLevel: evidence.difficultyLevel)
        }
        let provider = CoachingFixtureProvider(String(decoding: try JSONEncoder().encode(["questions": drafts]), as: UTF8.self))
        let preview = try await RevisionGenerationService.generate(context: evidence, provider: provider)
        let before = try context.fetch(FetchDescriptor<Quiz>()).count
        #expect(throws: (any Error).self) { _ = try RevisionGenerationService.save(preview, reviewed: drafts, previewConfirmed: false, context: context) }
        #expect(try context.fetch(FetchDescriptor<Quiz>()).count == before)
        let bankID = try RevisionGenerationService.save(preview, reviewed: drafts, previewConfirmed: true, context: context)
        #expect(try RevisionGenerationService.save(preview, reviewed: drafts, previewConfirmed: true, context: context) == bankID)
        let fresh = ModelContext(context.container)
        let bank = try #require(try fresh.fetch(FetchDescriptor<Quiz>()).first { $0.id == bankID })
        #expect(ExamLabService.isAIGenerated(bank))
        #expect(!ExamLabService.canUseAsTeacherMock(bank))
        #expect(!bank.questions.contains { $0.id == run.id })
        let teacherQuestion = try #require(try fresh.fetch(FetchDescriptor<QuizQuestion>()).first { $0.id == run.id })
        #expect(teacherQuestion.prompt == run.question.prompt)
        let provenance = try #require(try RevisionGenerationService.provenance(quizID: bankID, context: fresh))
        #expect(provenance.preview.model == "fixture-only")
        #expect(provenance.preview.sources == evidence.references)
        #expect(provenance.reviewedQuestions.count == 3)
        #expect(provenance.savedQuestionIDs.count == 3)
        #expect(provenance.preview.evidence.contains { $0.sessionID == id })
        #expect(try ExamLabService.metadata(quizID: bankID, context: fresh).difficultyLevels?.values.allSatisfy { $0 == 2 } == true)
        var practice = try QuestionBankSessionService.load(quizID: bankID, context: fresh)
        _ = try QuestionBankSessionService.start(quiz: bank, ledger: &practice, selected: bank.questions, mode: .mixed, context: fresh)
        #expect(practice.sessions.last?.questions.allSatisfy { $0.question.difficultyLevel == 2 } == true)
    }
    @Test @MainActor func mockCoachingStaysLockedUntilSubmission() throws {
        let (context, quiz) = try fixture()
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        let id = try ExamLabService.startMock(quiz: quiz, ledger: &ledger, minutes: nil, context: context)
        let question = try #require(ledger.sessions.first?.questions.first?.question)
        #expect(throws: (any Error).self) { _ = try RevisionCoachingSources.build(quiz: quiz, question: question, sessionID: id, context: context) }
        ledger.sessions[0].questions[0].answer = "B"
        try QuestionBankSessionService.finish(&ledger.sessions[0])
        ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        #expect(try RevisionCoachingSources.build(quiz: quiz, question: question, sessionID: id, context: context).evidence.contains { $0.sessionID == id })
    }
    @Test @MainActor func recurringConceptUsesActualAttemptsAcrossLinkedBanks() throws {
        let (context, quiz) = try fixture()
        _ = try submit([0], answers: ["B"], quiz: quiz, context: context)
        let another = Quiz(title: "More transport", course: quiz.course, chapter: quiz.chapter)
        context.insert(another)
        context.insert(QuizQuestion(prompt: "Choose the transport boundary.", choices: ["A: Membrane", "B: Nucleus"], correctAnswers: ["A"], explanation: "The membrane controls transport.", tags: ["Transport"], quiz: another))
        try context.save()
        let (ledger, id) = try submit([0], answers: ["B"], quiz: another, context: context)
        let report = try #require(ledger.sessions.first { $0.id == id }?.coaching)
        #expect(report.pattern.contains("2 recorded incorrect attempts across 2 different questions"))
        #expect(report.evidence.count == 2)
        #expect(report.recommendation?.quizID == another.id)
    }

    @Test @MainActor func similarQuestionFormatsAndWrittenReviewStaySafeAfterPreview() async throws {
        let (context, quiz) = try fixture()
        let (ledger, id) = try submit([0], answers: ["B"], quiz: quiz, context: context)
        let run = try #require(ledger.sessions.first { $0.id == id }?.questions.first)
        let evidence = try RevisionCoachingSources.build(quiz: quiz, question: run.question, sessionID: id, context: context)
        let sourceID = try #require(evidence.sources.first?.id)
        let drafts = [
            RevisionGeneratedQuestion(id: UUID(), prompt: "Select both boundaries.", type: .multipleSelect, choices: ["A: Boundary", "B: Boundary protein", "C: Centre"], correctAnswers: ["A", "B"], explanation: "Both chosen structures affect transport.", rubric: nil, writtenResponse: false, sourceIDs: [sourceID], difficultyLevel: 3),
            RevisionGeneratedQuestion(id: UUID(), prompt: "A membrane is a boundary. True or false?", type: .trueFalse, choices: ["True", "False"], correctAnswers: ["True"], explanation: "It forms the boundary.", rubric: nil, writtenResponse: false, sourceIDs: [sourceID], difficultyLevel: 3),
            RevisionGeneratedQuestion(id: UUID(), prompt: "Explain transport in your own words.", type: .shortAnswer, choices: [], correctAnswers: ["Explain selective permeability and give a transport example."], explanation: "Connect the structure and its role.", rubric: "Identify permeability and justify an example.", writtenResponse: true, sourceIDs: [sourceID], difficultyLevel: 3)
        ]
        var invalid = drafts[2]; invalid.writtenResponse = false
        #expect(throws: (any Error).self) { try RevisionGenerationService.validate(invalid, allowedSources: [sourceID], level: 3) }
        var invented = drafts[0]; invented.sourceIDs = ["question:invented"]
        #expect(throws: (any Error).self) { try RevisionGenerationService.validate(invented, allowedSources: [sourceID], level: 3) }
        let provider = CoachingFixtureProvider(String(decoding: try JSONEncoder().encode(["questions": drafts]), as: UTF8.self))
        let preview = try await RevisionGenerationService.generate(context: evidence, provider: provider)
        var foreign = preview; foreign.accountID = "another-account"
        #expect(throws: (any Error).self) { _ = try RevisionGenerationService.save(foreign, reviewed: drafts, previewConfirmed: true, context: context) }
        let savedID = try RevisionGenerationService.save(preview, reviewed: drafts, previewConfirmed: true, context: context)
        let fresh = ModelContext(context.container)
        let generated = try #require(try fresh.fetch(FetchDescriptor<Quiz>()).first { $0.id == savedID })
        var practice = try QuestionBankSessionService.load(quizID: savedID, context: fresh)
        _ = try QuestionBankSessionService.start(quiz: generated, ledger: &practice, selected: generated.questions.sorted { $0.position < $1.position }, mode: .mixed, context: fresh)
        for i in practice.sessions[0].questions.indices {
            practice.sessions[0].questions[i].answer = i == 0 ? "A,B" : i == 1 ? "True" : "My partial explanation."
            try QuestionBankSessionService.submit(&practice.sessions[0].questions[i], mode: .mixed)
        }
        try QuestionBankSessionService.finish(&practice.sessions[0])
        practice = try QuestionBankSessionService.save(practice, quiz: generated, context: fresh)
        #expect(practice.sessions[0].score == 2)
        #expect(practice.sessions[0].objectivelyAvailable == 2)
        #expect(practice.sessions[0].questions[2].needsWrittenReview)
        #expect(practice.sessions[0].questions[2].correct == nil)
    }

    @Test @MainActor func readableLinkedMaterialUsesActualPassagesRatherThanInventedFileContents() throws {
        let (context, quiz) = try fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("teacher-transport.txt")
        try "Teacher passage: a selectively permeable membrane controls movement.\n\nTerminology: passive transport.".write(to: sourceURL, atomically: true, encoding: .utf8)
        let fileStore = AcademicFileStore(rootDirectory: directory.appendingPathComponent("stored"))
        let stored = try fileStore.importFile(from: sourceURL)
        context.insert(AcademicResource(title: "Teacher transport text", resourceKind: stored.resourceKind, originalFileName: stored.originalFileName,
            storedRelativePath: stored.storedRelativePath, fileExtension: stored.fileExtension, fileSize: stored.fileSize, course: quiz.course, chapter: quiz.chapter))
        try context.save()
        let (ledger, id) = try submit([0], answers: ["B"], quiz: quiz, context: context)
        let question = try #require(ledger.sessions.first { $0.id == id }?.questions.first?.question)
        let evidence = try RevisionCoachingSources.build(quiz: quiz, question: question, sessionID: id, context: context, fileStore: fileStore)
        let resource = try #require(evidence.sources.first { $0.title == "Teacher transport text" })
        #expect(resource.text.contains("Teacher passage: a selectively permeable membrane"))
        #expect(resource.text.contains("[section 1]"))
        #expect(resource.detail.contains("retrieved passages"))
        #expect(resource.sourceReference.contains("teacher-transport.txt"))
    }

}
