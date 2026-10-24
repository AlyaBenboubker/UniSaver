import Foundation
import SwiftData
import Testing
@testable import UniSaver

private final class BankFixtureProvider: AIProvider {
    let id: AIRevisionProviderID = .openAI
    let model = "bank-fixture"
    var turns: [AgentProviderTurn]
    var requests: [[[String: Any]]] = []
    init(_ turns: [AgentProviderTurn]) { self.turns = turns }
    func complete(systemPrompt: String, userPrompt: String) async throws -> String { throw AIRevisionError.emptyResponse }
    func agentTurn(system: String, messages: [[String: Any]], tools: [[String: Any]], requiredTool: String?) async throws -> AgentProviderTurn {
        requests.append(messages)
        guard !turns.isEmpty else { throw AIRevisionError.emptyResponse }
        return turns.removeFirst()
    }
}

struct QuestionBankTests {
    @Test @MainActor func parsedQuestionRoundTripPreservesIdentityAndContent() throws {
        let question = try #require(QuizBulkParser.parse("QUESTION\nType: Multiple Choice\nPrompt: Synthetic identity check\nA: First\nB: Second\nCorrect: B\nExplanation: Second is the stored key.").first)
        let restored = try JSONDecoder().decode(ParsedQuizQuestion.self, from: JSONEncoder().encode(question))
        #expect(restored.id == question.id)
        #expect(restored == question)
    }

    private func bank() throws -> String {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ValidationFixtures/AccountingII-Synthetic.txt")
        return try String(contentsOf: file, encoding: .utf8)
    }
    @MainActor private func fixture() throws -> (ModelContainer, ModelContext, Course, Chapter) {
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let course = Course(name: "Accounting II", code: "ACC2")
        let chapter = Chapter(number: 1, title: "Consolidation", order: 0, course: course)
        context.insert(course); context.insert(chapter); try context.save()
        return (container, context, course, chapter)
    }
    @MainActor private func imported(_ context: ModelContext, course: Course, chapter: Chapter) throws -> Quiz {
        let id = try QuestionBankImportService.save(QuizBulkParser.parse(bank()), title: "Consolidation question bank", mode: .practice,
            courseID: course.id, chapterID: chapter.id, approvedAnswerChanges: [], context: context)
        return try #require(try ModelContext(context.container).fetch(FetchDescriptor<Quiz>()).first { $0.id == id })
    }

    @Test func syntheticBankParsesAll140WithoutChangingContent() throws {
        let original = try bank()
        let parsed = QuizBulkParser.parse(original)
        #expect(parsed.count == 140)
        #expect(parsed.allSatisfy { $0.isValid })
        #expect(parsed.filter { $0.type == .multipleChoice }.count == 69)
        #expect(parsed.filter { $0.type == .multipleSelect }.count == 11)
        #expect(parsed.filter { $0.type == .trueFalse }.count == 20)
        #expect(parsed.filter { $0.type == .shortAnswer }.count == 40)
        #expect(parsed.last?.correctAnswers == ["B"])
        #expect(parsed.contains { $0.correctAnswers == ["-16000"] })
        #expect(parsed.contains { $0.correctAnswers == ["1533.8"] })
        for question in parsed {
            #expect(original.contains(question.prompt))
            #expect(original.contains(question.explanation))
            #expect(question.tags.first == "Accounting II")
        }
    }
    @Test @MainActor func explicitlySharedTextFileImportsWholeBankInsteadOfRankedExcerpts() throws {
        let original = try bank()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SharedBank-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = root.appendingPathComponent("original.txt")
        try original.write(to: input, atomically: true, encoding: .utf8)
        let fileStore = AcademicFileStore(rootDirectory: root.appendingPathComponent("stored"))
        let stored = try fileStore.importFile(from: input)
        let resource = AcademicResource(title: "Shared original bank", resourceKind: stored.resourceKind,
            originalFileName: stored.originalFileName, storedRelativePath: stored.storedRelativePath,
            mimeType: stored.mimeType, fileExtension: stored.fileExtension, fileSize: stored.fileSize)
        let sources = try TaskWorkspaceService.sources(resources: [resource], fileStore: fileStore,
            query: "Import this question bank into my course and chapter.")
        #expect(sources.first?.text == original)
        #expect(QuizBulkParser.parse(sources.first?.text ?? "").count == 140)
        let advice = try TaskWorkspaceService.sources(resources: [resource], fileStore: fileStore, query: "Explain goodwill")
        #expect((advice.first?.text.count ?? 0) < original.count)
    }
    @Test func multilineAssumptionsAndColonLinesArePreserved() {
        let parsed = QuizBulkParser.parse("QUESTION\nType: Short Answer\nPrompt: First paragraph.\n\nAssumption: ignore tax.\nRound to 2 decimal places.\nCorrect: -12.50\nExplanation: First explanation.\n\nReason: preserves source.\nTags: Goodwill\n  ---  \nQUESTION\nType: True/False\nPrompt: Second?\nCorrect: False\nExplanation: No.")
        #expect(parsed.count == 2)
        #expect(parsed[0].prompt == "First paragraph.\n\nAssumption: ignore tax.\nRound to 2 decimal places.")
        #expect(parsed[0].explanation == "First explanation.\n\nReason: preserves source.")
        #expect(parsed[1].sourceLine > 1)
    }
    @Test func malformedBlocksKeepUsefulErrors() {
        let parsed = QuizBulkParser.parse("QUESTION\nType: Essay\nPrompt: Test\nCorrect: yes\n---\nQUESTION\nType: Multiple Choice\nPrompt: Test\nA: One\nB: Two\nCorrect: C\nExplanation: Wrong key\n---\nQUESTION\nType: True/False\nPrompt: Test\nCorrect: yes\nExplanation: Bad Boolean")
        #expect(parsed.count == 3)
        #expect(parsed.allSatisfy { !$0.isValid })
        #expect(parsed[0].sourceErrors.contains { $0.contains("Type") })
        #expect(parsed[0].errors.contains { $0.contains("Explanation") })
        #expect(parsed[1].errors.contains { $0.contains("existing options") })
        #expect(parsed[2].errors.contains { $0.contains("True/False") })
    }
    @Test func exactSetsAndSafeNumericalGrading() {
        let select = QuizQuestion(prompt: "Select", type: .multipleSelect, choices: ["A: One, two", "B: Three", "C: Four"], correctAnswers: ["A", "B"])
        #expect(QuizScoringService.isCorrect(question: select, answer: "B,A"))
        #expect(!QuizScoringService.isCorrect(question: select, answer: "A"))
        #expect(!QuizScoringService.isCorrect(question: select, answer: "A,B,C"))
        let negative = QuizQuestion(prompt: "Numbers only", type: .shortAnswer, correctAnswers: ["-16000"])
        #expect(QuizScoringService.isCorrect(question: negative, answer: " -16000.0 "))
        #expect(!QuizScoringService.isCorrect(question: negative, answer: "16000"))
        #expect(QuizScoringService.inputError(question: negative, answer: "-16,000") != nil)
        let decimal = QuizQuestion(prompt: "Use a decimal point", type: .shortAnswer, correctAnswers: ["1533.8"])
        #expect(QuizScoringService.isCorrect(question: decimal, answer: "1533.80"))
        #expect(!QuizScoringService.isCorrect(question: decimal, answer: "1533.81"))
        let rounded = QuizQuestion(prompt: "Round to 2 decimal places", type: .shortAnswer, correctAnswers: ["1.23"])
        #expect(QuizScoringService.isCorrect(question: rounded, answer: "1.234"))
        #expect(!QuizScoringService.isCorrect(question: rounded, answer: "1.24"))
        let text = QuizQuestion(prompt: "Name it", type: .shortAnswer, correctAnswers: ["Equity method"])
        #expect(QuizScoringService.isCorrect(question: text, answer: " equity METHOD "))
    }
    @Test @MainActor func duplicateImportReusesBankAndQuestionIDs() throws {
        let (_, context, course, chapter) = try fixture()
        let quiz = try imported(context, course: course, chapter: chapter)
        let ids = Set(quiz.questions.map(\.id))
        let second = try imported(context, course: course, chapter: chapter)
        #expect(second.id == quiz.id)
        #expect(second.questions.count == 140)
        #expect(Set(second.questions.map(\.id)) == ids)
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetch(FetchDescriptor<Quiz>()).count == 1)
        #expect(try fresh.fetch(FetchDescriptor<QuizQuestion>()).count == 140)
    }
    @Test @MainActor func differentImportTitleStillReusesOverlappingBank() throws {
        let (_, context, course, chapter) = try fixture()
        let quiz = try imported(context, course: course, chapter: chapter)
        let id = try QuestionBankImportService.save(QuizBulkParser.parse(bank()), title: "Another generated title",
            mode: .practice, courseID: course.id, chapterID: chapter.id, approvedAnswerChanges: [], context: context)
        #expect(id == quiz.id)
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<Quiz>()).count == 1)
    }
    @Test @MainActor func malformedImportDoesNotPartiallySaveValidBlocks() throws {
        let (_, context, course, chapter) = try fixture()
        var rows = QuizBulkParser.parse(try bank())
        rows[1].explanation = ""
        do {
            _ = try QuestionBankImportService.save(rows, title: "Must not save", mode: .practice,
                courseID: course.id, chapterID: chapter.id, approvedAnswerChanges: [], context: context)
            Issue.record("Expected atomic validation failure")
        } catch { #expect(error.localizedDescription.contains("malformed")) }
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<Quiz>()).isEmpty)
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<QuizQuestion>()).isEmpty)
    }
    @Test @MainActor func staleSessionSaveRetainsConfirmedAttemptsAndOtherSessions() throws {
        let (_, context, course, chapter) = try fixture()
        let quiz = try imported(context, course: course, chapter: chapter)
        var ledger = QuestionBankLedger(quizID: quiz.id)
        _ = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: Array(quiz.questions.prefix(1)), mode: .mixed, context: context)
        let stale = ledger
        ledger.sessions[0].questions[0].answer = ledger.sessions[0].questions[0].question.correctAnswers.joined(separator: ",")
        try QuestionBankSessionService.submit(&ledger.sessions[0].questions[0], mode: .mixed)
        try QuestionBankSessionService.finish(&ledger.sessions[0])
        ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        _ = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: Array(quiz.questions.suffix(1)), mode: .topic, context: context)
        let merged = try QuestionBankSessionService.save(stale, quiz: quiz, context: context)
        #expect(merged.sessions.count == 2)
        #expect(merged.sessions[0].isCompleted)
        #expect(merged.graded.count == 1)
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<QuizAttempt>()).count == 2)
    }
    @Test @MainActor func answerChangeRequiresReviewAndRetainsLearningSnapshots() throws {
        let (_, context, course, chapter) = try fixture()
        let quiz = try imported(context, course: course, chapter: chapter)
        let question = try #require(quiz.questions.first { $0.prompt.hasPrefix("Synthetic accounting exercise 1:") })
        var ledger = QuestionBankLedger(quizID: quiz.id)
        _ = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: [question], mode: .mixed, context: context)
        ledger.sessions[0].questions[0].answer = "B"
        try QuestionBankSessionService.submit(&ledger.sessions[0].questions[0], mode: .mixed)
        try QuestionBankSessionService.finish(&ledger.sessions[0])
        try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        var draft = QuizBulkParser.parse(try bank()).first!
        draft.correctAnswers = ["A"]
        do {
            _ = try QuestionBankImportService.save([draft], title: quiz.title, mode: .practice, courseID: course.id,
                chapterID: chapter.id, approvedAnswerChanges: [], context: context)
            Issue.record("Changed answer must require explicit review")
        } catch { #expect(error.localizedDescription.contains("answer")) }
        let row = try #require(QuestionBankImportService.preview([draft], existing: quiz.questions).first)
        _ = try QuestionBankImportService.save([draft], title: quiz.title, mode: .practice, courseID: course.id,
            chapterID: chapter.id, approvedAnswerChanges: [row.reviewKey], context: context)
        let loaded = try QuestionBankSessionService.load(quizID: quiz.id, context: ModelContext(context.container))
        #expect(loaded.graded.first?.question.correctAnswers == ["B"])
        #expect(loaded.graded.first?.correct == true)
        let fresh = try #require(try ModelContext(context.container).fetch(FetchDescriptor<QuizQuestion>()).first { $0.id == question.id })
        #expect(fresh.correctAnswers == ["A"])
    }
    @Test @MainActor func allModesHaveUniqueQuestionsAndExamDefersGrading() throws {
        let (_, context, course, chapter) = try fixture()
        let quiz = try imported(context, course: course, chapter: chapter)
        var ledger = QuestionBankLedger(quizID: quiz.id)
        for mode in [BankPracticeMode.topic, .mixed, .exam, .fullBank] {
            let candidates = QuestionBankSessionService.candidates(quiz: quiz, ledger: ledger, tags: mode == .topic ? ["Goodwill"] : [], type: nil, filter: "All questions", mode: mode)
            let selected = QuestionBankSessionService.select(candidates, mode: mode, count: 8)
            #expect(Set(selected.map(\.id)).count == selected.count)
            #expect(mode != .exam || selected.count == 5)
            #expect(mode != .exam || selected.allSatisfy { QuestionBankSessionService.isExamQuestion($0) })
            #expect(mode != .topic || selected.allSatisfy { $0.tags.contains("Goodwill") })
            #expect(mode != .fullBank || selected.count == 140)
        }
        let five = QuestionBankSessionService.select(quiz.questions, mode: .exam, count: 99)
        _ = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: five, mode: .exam, context: context)
        for index in ledger.sessions[0].questions.indices {
            ledger.sessions[0].questions[index].answer = five[index].correctAnswers.joined(separator: ",")
            try QuestionBankSessionService.submit(&ledger.sessions[0].questions[index], mode: .exam)
            #expect(ledger.sessions[0].questions[index].correct == nil)
        }
        #expect(ledger.attemptedIDs.count == 5)
        #expect(ledger.graded.isEmpty)
        try QuestionBankSessionService.finish(&ledger.sessions[0])
        #expect(ledger.sessions[0].score == ledger.sessions[0].maximum)
        ledger.sessions[0].questions[0].correct = false
        let mistakes = QuestionBankSessionService.candidates(quiz: quiz, ledger: ledger, tags: [], type: nil, filter: "All questions", mode: .mistakes)
        #expect(mistakes.map(\.id) == [five[0].id])
    }
    @Test @MainActor func diskReopenPreservesPlacementSessionsAndOneAttempt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BankRegression-\(UUID().uuidString).store")
        func config() -> ModelConfiguration { ModelConfiguration("BankRegression", schema: PersistenceController.schema, url: url) }
        var quizID = UUID(), sessionID = UUID()
        do {
            let container = try ModelContainer(for: PersistenceController.schema, configurations: [config()])
            let context = ModelContext(container)
            let course = Course(name: "Accounting II", code: "ACC2")
            let chapter = Chapter(number: 1, title: "Consolidation", order: 0, course: course)
            context.insert(course); context.insert(chapter); try context.save()
            let quiz = try imported(context, course: course, chapter: chapter); quizID = quiz.id
            var ledger = QuestionBankLedger(quizID: quiz.id)
            sessionID = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: Array(quiz.questions.prefix(3)), mode: .fullBank, context: context)
            ledger.sessions[0].questions[0].answer = "saved draft"
            ledger.sessions[0].index = 1
            try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
            try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        }
        let reopened = try ModelContainer(for: PersistenceController.schema, configurations: [config()])
        let context = ModelContext(reopened)
        let quiz = try #require(try context.fetch(FetchDescriptor<Quiz>()).first { $0.id == quizID })
        #expect(quiz.course?.name == "Accounting II" && quiz.chapter?.title == "Consolidation")
        #expect(quiz.questions.count == 140)
        let ledger = try QuestionBankSessionService.load(quizID: quizID, context: context)
        #expect(ledger.sessions.first?.id == sessionID)
        #expect(ledger.sessions.first?.index == 1)
        #expect(ledger.sessions.first?.questions.first?.answer == "saved draft")
        #expect(try context.fetch(FetchDescriptor<QuizAttempt>()).count == 1)
    }
    // Verified with user approval on 14 October; keep routine suites free of external calls.
    @Test(.disabled("Opt-in live provider regression; enable only for an explicitly requested network check.")) @MainActor func liveBankImportPreviewIfSecureConfigurationExists() async throws {
        let provider: AIProvider
        do { provider = try AIRevisionAssistantClient().conversationProvider() }
        catch AIRevisionError.missingAPIKey { throw QuestionBankError.invalid("Live preview was not run: no secure provider key is accessible.") }
        catch AIRevisionError.notConfigured { throw QuestionBankError.invalid("Live preview was not run: the provider is not configured.") }
        let (_, context, course, chapter) = try fixture()
        let original = try bank()
        var state = TodayConversationState()
        state.messages = [TodayConversationMessage(role: .student, text: "Import this question bank into Accounting II, Consolidation. Preserve all supplied answers and show the preview before saving.")]
        let source = AIRevisionSource(id: "shared-bank", title: "Original question bank", kind: .resource,
            detail: "user-supplied.txt", text: original, sourceReference: "user-supplied.txt")
        let service = ConversationProviderService(courses: [course], tasks: [], studyBlocks: [], page: "study",
            selectedCourseID: course.id, selectedTaskID: nil, selectedSources: [source])
        let result = try await service.respond(state: state, provider: provider)
        let action = try #require(result.proposal?.actions.first)
        #expect(action.kind == .importQuestionBank)
        #expect(action.sourceText == original)
        #expect(action.selectedCourseID == course.id && action.selectedChapterID == chapter.id)
        #expect(result.toolResults.joined().contains("140"))
        #expect(try context.fetch(FetchDescriptor<Quiz>()).isEmpty)
        let report: [String: Any] = ["provider": result.provider, "model": result.model,
            "prepared_questions": QuizBulkParser.parse(action.sourceText).count,
            "original_preserved": action.sourceText == original, "mutated_records": 0]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UniSaver-live-bank-import-preview.json")
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]).write(to: url)
    }
    @Test @MainActor func nativeAgentPreparesOriginalBankByReferenceWithoutGeneratingQuestions() async throws {
        let (_, _, course, chapter) = try fixture()
        var state = TodayConversationState()
        let sourceText = try bank()
        let message = TodayConversationMessage(role: .student, text: "Import this question bank into Accounting II, Consolidation.\n" + sourceText)
        state.messages = [message]
        let args = ["source_ref": "message:" + message.id.uuidString, "course_id": course.id.uuidString, "chapter_id": chapter.id.uuidString]
        let call = AgentToolCall(id: "import", name: "prepare_question_bank_import", arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
        let provider = BankFixtureProvider([AgentProviderTurn(text: "", calls: [call]), AgentProviderTurn(text: "Preview is ready; nothing saved.", calls: [])])
        let service = ConversationProviderService(courses: [course], tasks: [], studyBlocks: [], page: "study", selectedCourseID: course.id, selectedTaskID: nil)
        let result = try await service.respond(state: state, provider: provider)
        let action = try #require(result.proposal?.actions.first)
        #expect(action.kind == .importQuestionBank)
        #expect(action.sourceText == sourceText)
        #expect(action.selectedChapterID == chapter.id)
        #expect(result.toolResults.joined().contains("140"))
        #expect(!String(describing: provider.requests).contains("2813000")) // no answer bank sent for regeneration
    }
}
