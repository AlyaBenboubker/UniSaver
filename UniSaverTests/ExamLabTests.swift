import Foundation
import SwiftData
import Testing
@testable import UniSaver

struct ExamLabTests {
    @MainActor private func fixture(url: URL? = nil) throws -> (ModelContainer, ModelContext, Quiz) {
        let schema = PersistenceController.schema
        let config = url.map { ModelConfiguration(schema: schema, url: $0) } ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let store = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(store)
        let course = Course(name: "Biology", code: "BIO")
        let quiz = Quiz(title: "Teacher paper", quizDescription: "UniSaverQuestionBankV1: original imported paper", course: course)
        context.insert(course); context.insert(quiz)
        let definitions: [(QuizQuestionType, [String], [String], Int)] = [
            (.multipleChoice, ["A: Cell", "B: Tissue", "C: Organ"], ["B"], 2),
            (.multipleSelect, ["A: First", "B: Second", "C: Third"], ["A", "C"], 3),
            (.trueFalse, ["True", "False"], ["False"], 1),
            (.shortAnswer, [], ["The cell membrane regulates transport."], 8),
            (.shortAnswer, [], ["-2.5"], 4)
        ]
        for (index, definition) in definitions.enumerated() {
            context.insert(QuizQuestion(prompt: "Original prompt \(index)", type: definition.0, choices: definition.1, correctAnswers: definition.2,
                explanation: "Original explanation \(index)", hint: "Original hint", points: definition.3, position: index, tags: [index == 1 ? "Transport" : "Cells"], quiz: quiz))
        }
        try context.save()
        return (store, context, quiz)
    }
    @Test @MainActor func teacherMockPreservesWholePaperAndDefersEveryCorrection() throws {
        let (_, context, quiz) = try fixture()
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        _ = try ExamLabService.startMock(quiz: quiz, ledger: &ledger, minutes: 30, context: context)
        let paper = quiz.questions.sorted { $0.position < $1.position }
        #expect(ledger.sessions[0].questions.map(\.id) == paper.map(\.id))
        #expect(ledger.sessions[0].questions.map(\.question.prompt) == paper.map(\.prompt))
        #expect(ledger.sessions[0].questions.map(\.question.points) == [2, 3, 1, 8, 4])
        #expect(ledger.sessions[0].timeLimitSeconds == 1800)
        for i in ledger.sessions[0].questions.indices {
            #expect(ledger.sessions[0].questions[i].question.choices == paper[i].choices)
            ledger.sessions[0].questions[i].answer = paper[i].correctAnswers.joined(separator: ",")
            try QuestionBankSessionService.submit(&ledger.sessions[0].questions[i], mode: .teacherMock)
            #expect(ledger.sessions[0].questions[i].correct == nil)
            #expect(ledger.sessions[0].questions[i].submittedAt == nil)
        }
        #expect(ledger.sessions[0].hidesCorrections)
        try QuestionBankSessionService.finish(&ledger.sessions[0])
        #expect(!ledger.sessions[0].hidesCorrections)
        #expect(ledger.sessions[0].score == 10)
        #expect(ledger.sessions[0].objectivelyAvailable == 10)
        #expect(ledger.sessions[0].writtenMarks == 8)
        #expect(ledger.sessions[0].questions[3].correct == nil)
        #expect(ledger.sessions[0].questions[3].needsWrittenReview)
    }
    @Test @MainActor func skippedFlagsEditableDraftsAndStaleViewsCannotOverwriteFinalMock() throws {
        let (_, context, quiz) = try fixture()
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        _ = try ExamLabService.startMock(quiz: quiz, ledger: &ledger, minutes: nil, context: context)
        ledger.sessions[0].questions[0].answer = "A"
        try QuestionBankSessionService.submit(&ledger.sessions[0].questions[0], mode: .teacherMock)
        ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        let stale = ledger
        ledger.sessions[0].questions[0].answer = "B"
        ledger.sessions[0].questions[0].markedForReview = true
        ledger.sessions[0].index = 4
        ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        #expect(ledger.sessions[0].questions[0].answer == "B")
        try QuestionBankSessionService.finish(&ledger.sessions[0])
        ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        let restored = try QuestionBankSessionService.save(stale, quiz: quiz, context: context)
        #expect(restored.sessions[0].questions[0].answer == "B")
        #expect(restored.sessions[0].questions[0].correct == true)
        #expect(restored.sessions[0].questions[0].markedForReview == true)
        #expect(restored.sessions[0].questions.filter { $0.skipped == true }.count == 4)
        #expect(restored.sessions[0].deadline == nil)
    }
    @Test func immediateSuccessRemainsUnresolvedUntilDelayedUnassistedRecall() {
        let question = BankQuestionSnapshot(QuizQuestion(prompt: "Recall?", correctAnswers: ["A"]))
        let date = Date(timeIntervalSince1970: 1_000_000)
        var wrong = BankQuestionRun(question: question); wrong.answer = "B"; wrong.submittedAt = date; wrong.correct = false
        let first = BankPracticeSession(mode: .mixed, startedAt: date, questions: [wrong])
        var success = wrong; success.answer = "A"; success.correct = true; success.submittedAt = date.addingTimeInterval(30)
        var immediate = BankPracticeSession(mode: .mistakes, questions: [success]); immediate.immediateRetryOf = first.id
        var ledger = QuestionBankLedger(quizID: UUID(), sessions: [first, immediate])
        #expect(ledger.mistakeIDs == [question.id])
        #expect(ledger.dueIDs(now: date.addingTimeInterval(86401)).contains(question.id))
        #expect(!ledger.dueIDs(now: date.addingTimeInterval(3600)).contains(question.id))
        success.submittedAt = date.addingTimeInterval(90000); success.hintsUsed = 1
        ledger.sessions.append(BankPracticeSession(mode: .mistakes, questions: [success]))
        #expect(ledger.mistakeIDs.contains(question.id))
        success.submittedAt = date.addingTimeInterval(180000); success.hintsUsed = 0
        ledger.sessions.append(BankPracticeSession(mode: .mistakes, questions: [success]))
        #expect(ledger.mistakeIDs.isEmpty)
        #expect(ledger.sessions.count == 4)
    }
    @Test @MainActor func shuffledOptionsKeepOriginalKeysForAllAutomaticTypes() throws {
        let (_, context, quiz) = try fixture()
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        let selected = quiz.questions.filter { $0.position != 3 }.sorted { $0.position < $1.position }
        _ = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: selected, mode: .mixed, context: context, shuffleAnswers: true)
        for i in ledger.sessions[0].questions.indices {
            var run = ledger.sessions[0].questions[i]
            run.choiceOrder = Array(run.displayChoices.map(\.index).reversed())
            #expect(Set(run.displayChoices.map(\.key)) == Set((run.question.type == .trueFalse ? ["True", "False"] : run.question.choices).map(QuizScoringService.optionKey)))
            run.answer = run.question.correctAnswers.joined(separator: ",")
            try QuestionBankSessionService.submit(&run, mode: .mixed)
            #expect(run.correct == true)
            ledger.sessions[0].questions[i] = run
        }
        ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        let restored = try QuestionBankSessionService.load(quizID: quiz.id, context: ModelContext(context.container))
        #expect(restored.sessions[0].questions.map(\.choiceOrder) == ledger.sessions[0].questions.map(\.choiceOrder))
    }
    @Test @MainActor func unfinishedMockSurvivesReopenWithTimerNavigationAndFlags() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mock.store")
        var quizID = UUID(), attemptID = UUID(); var deadline = Date()
        do {
            let (_, context, quiz) = try fixture(url: url); quizID = quiz.id
            var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
            attemptID = try ExamLabService.startMock(quiz: quiz, ledger: &ledger, minutes: 1, context: context)
            ledger.sessions[0].questions[0].answer = "B"
            ledger.sessions[0].questions[3].answer = "My unfinished written response"
            ledger.sessions[0].questions[3].markedForReview = true
            ledger.sessions[0].index = 3
            deadline = try #require(ledger.sessions[0].deadline)
            _ = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        }
        let schema = PersistenceController.schema
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let loaded = try QuestionBankSessionService.load(quizID: quizID, context: ModelContext(reopened))
        #expect(loaded.sessions[0].id == attemptID)
        #expect(loaded.sessions[0].index == 3)
        #expect(loaded.sessions[0].questions[3].answer == "My unfinished written response")
        #expect(loaded.sessions[0].questions[3].markedForReview == true)
        #expect(loaded.sessions[0].deadline == deadline)
        #expect(!loaded.sessions[0].isCompleted)
        #expect(loaded.sessions[0].timeExpired(at: deadline.addingTimeInterval(1)))
    }
    @Test @MainActor func writtenRubricAndProvisionalFeedbackNeverBecomeAnOfficialGrade() throws {
        let (_, context, quiz) = try fixture()
        let question = try #require(quiz.questions.first { $0.position == 3 })
        try ExamLabService.stage(ExamLabPaperMetadata(quizID: quiz.id, rubrics: [question.id: "Describe selective permeability; justify transport."], writtenQuestionIDs: [question.id]), context: context)
        try context.save()
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        _ = try ExamLabService.startMock(quiz: quiz, ledger: &ledger, minutes: nil, context: context)
        ledger.sessions[0].questions[3].answer = "A membrane controls transport."
        try QuestionBankSessionService.finish(&ledger.sessions[0])
        ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        ledger.sessions[0].questions[3].aiFeedback = "Provisional: mention selective permeability."
        ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        #expect(ledger.sessions[0].questions[3].question.rubric?.contains("permeability") == true)
        #expect(ledger.sessions[0].questions[3].correct == nil)
        let record = try #require(try RevisionHistoryService.records(context: ModelContext(context.container)).first)
        let answer = try #require(record.answers.first { $0.id == question.id })
        #expect(answer.pointsEarned == nil)
        #expect(answer.result == "Written response · needs review")
        #expect(answer.gradingDetail?.contains("Provisional") == true)
        #expect(answer.gradingMethod.contains("provisional"))
    }
    @Test @MainActor func teacherMocksRejectGeneratedPracticeAndImportPreservesMarksAndRubric() throws {
        let (_, context, quiz) = try fixture()
        quiz.quizDescription = "AI-generated practice reviewed by student"
        try context.save()
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        #expect(throws: (any Error).self) { _ = try ExamLabService.startMock(quiz: quiz, ledger: &ledger, minutes: nil, context: context) }
        let parsed = QuizBulkParser.parse("""
        QUESTION
        Type: Short Answer
        Prompt: Explain transport.
        Correct: A membrane controls transport.
        Explanation: Model explanation remains unchanged.
        Marks: 9
        Rubric: Explain selective permeability.
        Tags: Transport
        """)
        #expect(parsed.count == 1)
        #expect(parsed[0].errors.isEmpty)
        let id = try QuestionBankImportService.save(parsed, title: "Written teacher paper", mode: .exam, courseID: quiz.course?.id, chapterID: nil, approvedAnswerChanges: [], context: context)
        let fresh = ModelContext(context.container)
        let imported = try #require(try fresh.fetch(FetchDescriptor<Quiz>()).first { $0.id == id })
        #expect(imported.questions[0].points == 9)
        #expect(imported.questions[0].explanation == "Model explanation remains unchanged.")
        #expect(try ExamLabService.metadata(quizID: id, context: fresh).rubrics[imported.questions[0].id] == "Explain selective permeability.")
    }
    @Test @MainActor func repeatedTeacherQuestionsKeepOrderAndNewPapersDoNotMergeByOverlap() throws {
        let (_, context, quiz) = try fixture()
        let text = """
        QUESTION
        Type: Multiple Choice
        Prompt: Repeat this teacher question.
        A: First
        B: Second
        Correct: B
        Explanation: The second option is correct.
        Points: 3
        Tags: Cells
        """
        let rows = QuizBulkParser.parse(text + "\n---\n" + text)
        let firstID = try QuestionBankImportService.save(rows, title: "Repeated teacher paper", mode: .exam, courseID: quiz.course?.id, chapterID: nil, approvedAnswerChanges: [], context: context)
        let fresh = ModelContext(context.container)
        let first = try #require(try fresh.fetch(FetchDescriptor<Quiz>()).first { $0.id == firstID })
        #expect(first.questions.count == 2)
        #expect(Set(first.questions.map(\.id)).count == 2)
        #expect(first.questions.sorted { $0.position < $1.position }.map(\.position) == [0, 1])
        let secondID = try QuestionBankImportService.save(rows, title: "Another teacher paper", mode: .exam, courseID: quiz.course?.id, chapterID: nil, approvedAnswerChanges: [], context: context)
        #expect(firstID != secondID)
        let repeatedImportID = try QuestionBankImportService.save(rows, title: "Repeated teacher paper", mode: .exam, courseID: quiz.course?.id, chapterID: nil, approvedAnswerChanges: [], context: context)
        #expect(repeatedImportID == firstID)
    }

    @Test func reviewLaterSchedulesSuccessfulQuestionsAndClearsAfterAnotherAttempt() {
        let snapshot = BankQuestionSnapshot(QuizQuestion(prompt: "Recall", type: .shortAnswer, correctAnswers: ["Answer"]))
        let date = Date(timeIntervalSince1970: 1_000_000)
        var answer = BankQuestionRun(question: snapshot); answer.answer = "Answer"; answer.correct = true; answer.submittedAt = date
        var first = BankPracticeSession(mode: .mixed, startedAt: date, completedAt: date.addingTimeInterval(1), questions: [answer])
        first.reviewAfterAt = date.addingTimeInterval(86400)
        var ledger = QuestionBankLedger(quizID: UUID(), sessions: [first])
        #expect(ledger.dueIDs(now: date.addingTimeInterval(90000)).contains(snapshot.id))
        answer.submittedAt = date.addingTimeInterval(90000)
        ledger.sessions.append(BankPracticeSession(mode: .mixed, startedAt: date.addingTimeInterval(90000), completedAt: date.addingTimeInterval(90001), questions: [answer]))
        #expect(!ledger.dueIDs(now: date.addingTimeInterval(90002)).contains(snapshot.id))
    }

    @Test @MainActor func teacherBooleanChoicesKeepWordingAndOrderWithCanonicalGrading() throws {
        let (_, context, quiz) = try fixture()
        let question = try #require(quiz.questions.first { $0.type == .trueFalse })
        question.choices = ["A: False", "B: True"]
        question.correctAnswers = ["False"]
        try context.save()
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        _ = try ExamLabService.startMock(quiz: quiz, ledger: &ledger, minutes: nil, context: context)
        let index = try #require(ledger.sessions[0].questions.firstIndex { $0.id == question.id })
        #expect(ledger.sessions[0].questions[index].displayChoices.map(\.text) == ["A: False", "B: True"])
        ledger.sessions[0].questions[index].answer = ledger.sessions[0].questions[index].displayChoices[0].key
        try QuestionBankSessionService.finish(&ledger.sessions[0])
        #expect(ledger.sessions[0].questions[index].correct == true)
    }

}
