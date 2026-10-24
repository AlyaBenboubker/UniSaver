import Foundation
import SwiftData

/// Additive paper annotations. Teacher wording and explanation stay in their
/// existing fields; rubrics and written-response overrides live alongside them.
struct ExamLabPaperMetadata: Codable {
    var quizID: UUID
    var rubrics: [UUID: String] = [:]
    var writtenQuestionIDs: Set<UUID> = []
    var difficultyLevels: [UUID: Int]? = nil
}

@MainActor enum ExamLabService {
    static let marker = "UniSaverExamLabPaperV1:\n"
    static func isAIGenerated(_ quiz: Quiz) -> Bool {
        quiz.quizDescription.hasPrefix("AI-generated") || quiz.questions.contains { $0.tags.contains("AI-generated") }
    }
    static func isImported(_ quiz: Quiz) -> Bool { quiz.quizDescription.hasPrefix("UniSaverQuestionBank") }
    static func canUseAsTeacherMock(_ quiz: Quiz) -> Bool { isImported(quiz) && !isAIGenerated(quiz) }
    static func metadata(quizID: UUID, context: ModelContext) throws -> ExamLabPaperMetadata {
        let title = "Exam Lab paper " + quizID.uuidString
        guard let note = try context.fetch(FetchDescriptor<StudyNote>()).first(where: { $0.title == title && $0.body.hasPrefix(marker) }) else {
            return ExamLabPaperMetadata(quizID: quizID)
        }
        return try JSONDecoder().decode(ExamLabPaperMetadata.self, from: Data(note.body.dropFirst(marker.count).utf8))
    }
    static func stage(_ metadata: ExamLabPaperMetadata, context: ModelContext) throws {
        let title = "Exam Lab paper " + metadata.quizID.uuidString
        let note = try context.fetch(FetchDescriptor<StudyNote>()).first { $0.title == title && $0.body.hasPrefix(marker) } ?? StudyNote(title: title)
        if note.modelContext == nil { context.insert(note) }
        note.body = marker + String(decoding: try JSONEncoder().encode(metadata), as: UTF8.self)
        note.updatedAt = .now
    }
    static func isWritten(_ question: BankQuestionSnapshot) -> Bool {
        question.type == .shortAnswer && (question.rubric != nil || question.correctAnswers.first.flatMap(QuizScoringService.decimal) == nil)
    }
    static func startMock(quiz: Quiz, ledger: inout QuestionBankLedger, minutes: Int?, context: ModelContext) throws -> UUID {
        guard canUseAsTeacherMock(quiz) else { throw QuestionBankError.invalid("Choose an imported teacher paper. AI practice cannot be used as a teacher mock.") }
        return try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger,
            selected: quiz.questions.sorted { $0.position < $1.position }, mode: .teacherMock,
            context: context, timeLimit: minutes.map { Double($0 * 60) })
    }
}

extension BankQuestionRun {
    var needsWrittenReview: Bool { writtenResponse == true && submittedAt != nil && skipped != true }
    var displayChoices: [(index: Int, key: String, text: String)] {
        let choices = question.type == .trueFalse && question.choices.isEmpty ? ["True", "False"] : question.choices
        let order = choiceOrder ?? Array(choices.indices)
        return order.filter { choices.indices.contains($0) }.map { index in
            let choice = choices[index]
            var key = QuizScoringService.optionKey(choice)
            if question.type == .trueFalse {
                let value = choice.split(separator: ":", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if value == "true" { key = "True" }
                if value == "false" { key = "False" }
            }
            return (index, key, choice)
        }
    }
    var resultTitle: String {
        if skipped == true { return "Skipped" }
        if submittedAt == nil { return "Unanswered" }
        if needsWrittenReview { return "Written response · needs review" }
        guard let correct else { return "Awaiting grading" }
        return correct ? ((hintsUsed ?? 0) > 0 ? "Correct with help" : "Correct without help") : "Incorrect"
    }
    @MainActor var correctAnswerText: String {
        QuizScoringService.displayAnswer(question: question.gradingQuestion(), answer: question.correctAnswers.joined(separator: ","))
    }
}

extension BankPracticeSession {
    var isTeacherMock: Bool { mode == .teacherMock }
    var hidesCorrections: Bool { (isTeacherMock || mode == .exam) && !isCompleted }
    var deadline: Date? { timeLimitSeconds.map { startedAt.addingTimeInterval($0) } }
    func timeExpired(at date: Date = .now) -> Bool { deadline.map { date >= $0 } ?? false }
    var objectivelyAvailable: Int { questions.filter { $0.writtenResponse != true }.reduce(0) { $0 + $1.question.points } }
    var writtenMarks: Int { questions.filter { $0.writtenResponse == true }.reduce(0) { $0 + $1.question.points } }
    var topicMistakes: [String: Int] {
        var counts: [String: Int] = [:]
        for run in questions where run.correct == false || run.skipped == true {
            for topic in run.question.tags.isEmpty ? ["General"] : run.question.tags { counts[topic, default: 0] += 1 }
        }
        return counts
    }
}
