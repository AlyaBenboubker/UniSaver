import Foundation
import SwiftData
import CryptoKit

enum QuestionBankError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

struct QuestionImportRow: Identifiable {
    let question: ParsedQuizQuestion
    let duplicate: Bool
    let needsAnswerReview: Bool
    let reviewKey: String
    let savedAnswers: [String]
    var id: UUID { question.id }
}

@MainActor enum QuestionBankImportService {
    static func identity(type: QuizQuestionType, prompt: String, choices: [String]) -> String {
        digest([type.rawValue, prompt, choices.joined(separator: "\u{1F}")].joined(separator: "\u{1E}"))
    }
    static func identity(_ question: ParsedQuizQuestion) -> String {
        identity(type: question.type, prompt: question.prompt, choices: question.choices)
    }
    static func identity(_ question: QuizQuestion) -> String {
        identity(type: question.type, prompt: question.prompt, choices: question.choices)
    }
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func matchingBank(_ parsed: [ParsedQuizQuestion], title: String, quizzes: [Quiz], courseID: UUID?, chapterID: UUID?) throws -> Quiz? {
        let candidates = quizzes.filter { !$0.isArchived && !ExamLabService.isAIGenerated($0) && $0.course?.id == courseID && $0.chapter?.id == chapterID }
        let named = candidates.filter { $0.title == title }
        if named.count > 1 { throw QuestionBankError.invalid("Several banks match this name and destination. Choose a distinct name or resolve the existing duplicates.") }
        if let quiz = named.first { return quiz }
        let incoming = Set(parsed.map(identity))
        let overlaps = candidates.map { ($0, Set($0.questions.map(identity)).intersection(incoming).count) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        if overlaps.count > 1 && overlaps[0].1 == overlaps[1].1 { throw QuestionBankError.invalid("These questions occur in several banks. Select the existing bank name before importing.") }
        return overlaps.first?.0
    }
    static func preview(_ parsed: [ParsedQuizQuestion], existing: [QuizQuestion]) -> [QuestionImportRow] {
        var seen = Set<String>()
        return parsed.map { incoming in
            let key = identity(incoming)
            let saved = existing.first { identity($0) == key }
            let repeated = !seen.insert(key).inserted
            let changed = saved.map { Set($0.correctAnswers) != Set(incoming.correctAnswers) } ?? false
            let reviewKey = digest(key + (saved?.correctAnswers.joined(separator: "\u{1F}") ?? "") + incoming.correctAnswers.joined(separator: "\u{1F}"))
            return QuestionImportRow(question: incoming, duplicate: saved != nil || repeated,
                needsAnswerReview: changed, reviewKey: reviewKey, savedAnswers: saved?.correctAnswers ?? [])
        }
    }

    static func save(_ parsed: [ParsedQuizQuestion], title: String, mode: QuizMode,
                     courseID: UUID?, chapterID: UUID?, approvedAnswerChanges: Set<String>,
                     context: ModelContext) throws -> UUID {
        guard !parsed.isEmpty, parsed.allSatisfy({ $0.errors.isEmpty && QuizBulkParser.validationErrors($0).isEmpty }) else {
            throw QuestionBankError.invalid("Correct every malformed question before saving. No questions were imported.")
        }
        let grouped = Dictionary(grouping: parsed, by: identity)
        guard !grouped.values.contains(where: { rows in
            Set(rows.map { digest($0.correctAnswers.joined(separator: "\u{1F}") + $0.explanation + $0.tags.joined(separator: "\u{1F}") + String($0.points ?? 1) + ($0.rubric ?? "")) }).count > 1
        }) else { throw QuestionBankError.invalid("Conflicting duplicate blocks have different answers, explanations or tags. Review them before importing.") }
        let transaction = ModelContext(context.container)
        transaction.autosaveEnabled = false
        let courses = try transaction.fetch(FetchDescriptor<Course>())
        let chapters = try transaction.fetch(FetchDescriptor<Chapter>())
        let course = courses.first { $0.id == courseID }
        let chapter = chapters.first { $0.id == chapterID }
        guard courseID == nil || course != nil, chapterID == nil || (chapter != nil && chapter?.course?.id == courseID) else {
            throw QuestionBankError.invalid("The destination course or chapter no longer exists. Choose it again.")
        }
        let all = try transaction.fetch(FetchDescriptor<Quiz>())
        let matched: Quiz?
        if mode == .exam {
            let named = all.filter { $0.title == title && $0.course?.id == courseID && $0.chapter?.id == chapterID && !$0.isArchived && !ExamLabService.isAIGenerated($0) }
            let incomingOrder = parsed.map(identity)
            matched = named.first { $0.questions.sorted { $0.position < $1.position }.map(identity) == incomingOrder }
            // A revised paper with changed structure gets a separate bank. Keep
            // the earlier imported paper and every attempt intact.
        } else {
            matched = try matchingBank(parsed, title: title, quizzes: all, courseID: courseID, chapterID: chapterID)
        }
        let quiz = matched ?? Quiz(title: title, mode: mode, course: course, chapter: chapter)
        if matched == nil { transaction.insert(quiz) }
        let rows = preview(parsed, existing: quiz.questions)
        guard rows.filter(\.needsAnswerReview).allSatisfy({ approvedAnswerChanges.contains($0.reviewKey) }) else {
            throw QuestionBankError.invalid("A supplied answer differs from a saved question. Review and approve the answer change before saving; learning history will be retained.")
        }
        var paper = try ExamLabService.metadata(quizID: quiz.id, context: transaction)
        var existing = quiz.questions
        for (position, incoming) in parsed.enumerated() {
            if let question = existing.first(where: { identity($0) == identity(incoming) && (mode != .exam || $0.position == position) }) {
                question.correctAnswers = incoming.correctAnswers
                question.explanation = incoming.explanation
                question.tags = incoming.tags
                question.hint = incoming.hint
                if let points = incoming.points { question.points = points }
                if let rubric = incoming.rubric { paper.rubrics[question.id] = rubric; paper.writtenQuestionIDs.insert(question.id) }
            } else {
                let question = QuizQuestion(prompt: incoming.prompt, type: incoming.type, choices: incoming.choices,
                    correctAnswers: incoming.correctAnswers, explanation: incoming.explanation, hint: incoming.hint,
                    points: incoming.points ?? 1, position: mode == .exam ? position : (existing.map(\.position).max() ?? -1) + 1, tags: incoming.tags, quiz: quiz)
                transaction.insert(question); existing.append(question)
                if let rubric = incoming.rubric { paper.rubrics[question.id] = rubric; paper.writtenQuestionIDs.insert(question.id) }
            }
        }
        try ExamLabService.stage(paper, context: transaction)
        quiz.quizDescription = "UniSaverQuestionBankV1: imported original questions; practice progress is stored separately."
        quiz.updatedAt = .now
        do { try transaction.save() } catch { transaction.rollback(); throw error }
        return quiz.id
    }
}

enum BankPracticeMode: String, Codable, CaseIterable, Identifiable {
    case topic, mixed, exam, mistakes, fullBank, teacherMock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topic: "Topic practice"
        case .mixed: "Mixed practice"
        case .exam: "Five-question exam practice"
        case .teacherMock: "Teacher mock exam"
        case .mistakes: "Mistake review"
        case .fullBank: "Full-bank practice"
        }
    }
}

struct BankQuestionSnapshot: Codable, Identifiable {
    var id: UUID
    var prompt: String
    var type: QuizQuestionType
    var choices: [String]
    var correctAnswers: [String]
    var explanation: String
    var tags: [String]
    var points: Int
    var hint: String?
    var rubric: String? = nil
    var difficultyLevel: Int? = nil
    init(_ question: QuizQuestion) {
        hint = question.hint
        id = question.id; prompt = question.prompt; type = question.type; choices = question.choices
        correctAnswers = question.correctAnswers; explanation = question.explanation; tags = question.tags; points = question.points
    }
    @MainActor func gradingQuestion() -> QuizQuestion {
        QuizQuestion(id: id, prompt: prompt, type: type, choices: choices,
                     correctAnswers: correctAnswers, explanation: explanation, points: points, tags: tags)
    }
}

struct BankQuestionRun: Codable, Identifiable {
    var id: UUID { question.id }
    var question: BankQuestionSnapshot
    var answer = ""
    var submittedAt: Date?
    var correct: Bool?
    var seconds: TimeInterval = 0
    var hintsUsed: Int? = nil
    var markedForReview: Bool? = nil
    var skipped: Bool? = nil
    var modelAnswerRevealed: Bool? = nil
    var savedAt: Date? = nil
    var choiceOrder: [Int]? = nil
    var writtenResponse: Bool? = nil
    var aiFeedback: String? = nil
    var coachingExplanation: String? = nil
    var suspectedKeyIssue: String? = nil
    var coachingSourceIDs: [String]? = nil
}

struct BankPracticeSession: Codable, Identifiable {
    var id = UUID()
    var mode: BankPracticeMode
    var startedAt = Date()
    var completedAt: Date?
    var index = 0
    var questions: [BankQuestionRun]
    var timeLimitSeconds: TimeInterval? = nil
    var immediateRetryOf: UUID? = nil
    var reviewAfterAt: Date? = nil
    var coaching: RevisionCoachingReport? = nil
    var coachingOriginID: UUID? = nil
    var score: Int { questions.filter { $0.correct == true }.reduce(0) { $0 + $1.question.points } }
    var maximum: Int { questions.reduce(0) { $0 + $1.question.points } }
    var isCompleted: Bool { completedAt != nil }
}

struct QuestionBankLedger: Codable {
    var version = 1
    var quizID: UUID
    var accountID: String? = nil
    var sessions: [BankPracticeSession] = []
    var graded: [BankQuestionRun] { sessions.flatMap(\.questions).filter { $0.correct != nil } }
    var attemptedIDs: Set<UUID> { Set(sessions.flatMap(\.questions).filter { $0.submittedAt != nil }.map(\.id)) }
    // A correction followed by an immediate success is reinforcement, not
    // evidence of retained recall. Only a later, unassisted attempt resolves it.
    var unresolvedMistakes: [UUID: Date] {
        var unresolved: [UUID: Date] = [:]
        let observations = sessions.flatMap { session in session.questions.map { (session, $0) } }
            .sorted { ($0.1.submittedAt ?? .distantPast) < ($1.1.submittedAt ?? .distantPast) }
        for (session, run) in observations {
            guard let date = run.submittedAt else { continue }
            if run.correct == false || run.skipped == true { unresolved[run.id] = date }
            else if run.correct == true, (run.hintsUsed ?? 0) == 0, session.immediateRetryOf == nil,
                    let anchor = unresolved[run.id], date.timeIntervalSince(anchor) >= 86400 {
                unresolved.removeValue(forKey: run.id)
            }
        }
        return unresolved
    }
    var mistakeIDs: Set<UUID> { Set(unresolvedMistakes.keys) }
    func dueIDs(now: Date = .now) -> Set<UUID> {
        var result = Set(unresolvedMistakes.filter { $0.value.addingTimeInterval(86400) <= now }.keys)
        for (id, runs) in Dictionary(grouping: graded, by: \.id) where !mistakeIDs.contains(id) {
            if let latest = runs.max(by: { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }),
               let date = latest.submittedAt, date.addingTimeInterval(7 * 86400) <= now { result.insert(id) }
        }
        let latestSubmission = Dictionary(grouping: sessions.flatMap(\.questions).filter { $0.submittedAt != nil }, by: \.id)
            .mapValues { $0.compactMap(\.submittedAt).max() ?? .distantPast }
        for session in sessions where session.reviewAfterAt.map({ $0 <= now }) == true {
            for run in session.questions {
                if mistakeIDs.contains(run.id) || (latestSubmission[run.id] ?? .distantPast) <= (session.completedAt ?? session.startedAt) {
                    result.insert(run.id)
                }
            }
        }
        return result
    }
}

@MainActor enum QuestionBankSessionService {
    static let marker = "UniSaverQuestionBankV1:\n"
    static func progressTitle(_ quizID: UUID) -> String {
        "Question bank progress " + quizID.uuidString + " " + QuestionBankImportService.digest(RevisionHistoryService.accountID)
    }
    static func isProgressNote(_ note: StudyNote) -> Bool { (note.body.hasPrefix(marker) || note.body.hasPrefix(RevisionHistoryService.marker) || note.body.hasPrefix(ExamLabService.marker) || note.body.hasPrefix(RevisionGenerationService.marker)) }
    static func isExamQuestion(_ question: QuizQuestion) -> Bool {
        if question.type == .shortAnswer, let answer = question.correctAnswers.first,
           QuizScoringService.decimal(answer) != nil { return true }
        // Quantitative scenario selection is inferred; it does not modify question content.
        return question.prompt.range(of: "[€$]\\s*[-−]?[0-9]|[0-9][0-9,.]*\\s*%|\\b[0-9]{2,}\\b", options: .regularExpression) != nil
    }
    static func load(quizID: UUID, context: ModelContext) throws -> QuestionBankLedger {
        let notes = try context.fetch(FetchDescriptor<StudyNote>())
        let title = progressTitle(quizID)
        guard let note = notes.first(where: { $0.title == title && $0.body.hasPrefix(marker) }) else {
            return QuestionBankLedger(quizID: quizID, accountID: RevisionHistoryService.accountID)
        }
        do {
            let ledger = try JSONDecoder().decode(QuestionBankLedger.self, from: Data(note.body.dropFirst(marker.count).utf8))
            guard ledger.version == 1, ledger.quizID == quizID, ledger.accountID == RevisionHistoryService.accountID else { throw QuestionBankError.invalid("Unsupported progress format.") }
            return ledger
        } catch { throw QuestionBankError.invalid("Saved practice progress could not be read. It has been preserved: " + error.localizedDescription) }
    }

    static func candidates(quiz: Quiz, ledger: QuestionBankLedger, tags: Set<String>, type: QuizQuestionType?,
                           filter: String, mode: BankPracticeMode, context: ModelContext? = nil) -> [QuizQuestion] {
        var currentLedger = ledger
        let paper = context.flatMap { try? ExamLabService.metadata(quizID: quiz.id, context: $0) }
        let versions = try? Dictionary(uniqueKeysWithValues: quiz.questions.map { question in
            var snapshot = BankQuestionSnapshot(question)
            snapshot.rubric = paper?.rubrics[question.id]
            snapshot.difficultyLevel = paper?.difficultyLevels?[question.id]
            return (question.id, try RevisionHistoryService.version(snapshot))
        })
        for i in currentLedger.sessions.indices {
            currentLedger.sessions[i].questions = currentLedger.sessions[i].questions.filter { run in
                (try? RevisionHistoryService.version(run.question)) == versions?[run.id]
            }
        }
        let due = currentLedger.dueIDs()
        return quiz.questions.filter { question in
            (tags.isEmpty || !Set(question.tags).isDisjoint(with: tags)) &&
            (type == nil || question.type == type) &&
            (mode != .exam || isExamQuestion(question)) &&
            (mode != .mistakes || currentLedger.mistakeIDs.contains(question.id)) &&
            (filter != "Unanswered" || !currentLedger.attemptedIDs.contains(question.id)) &&
            (filter != "Previously incorrect" || currentLedger.graded.contains { $0.id == question.id && $0.correct == false }) &&
            (filter != "Due for review" || due.contains(question.id))
        }
    }

    static func select(_ candidates: [QuizQuestion], mode: BankPracticeMode, count: Int) -> [QuizQuestion] {
        let unique = Dictionary(grouping: candidates.filter { mode != .exam || isExamQuestion($0) }, by: \.id).compactMap { $0.value.first }
        if mode == .fullBank { return unique.shuffled() }
        let wanted = min(mode == .exam ? 5 : max(1, count), unique.count)
        // Round-robin across topic/type buckets. Original option order stays intact.
        let buckets = Dictionary(grouping: unique.shuffled()) { question in
            (question.tags.first(where: { ![question.quiz?.course?.name, question.quiz?.chapter?.title].compactMap({ $0 }).contains($0) }) ?? "General") + "|" + question.type.rawValue
        }
        var groups = buckets.values.map { $0 }.shuffled()
        var result: [QuizQuestion] = []
        while result.count < wanted && groups.contains(where: { !$0.isEmpty }) {
            for index in groups.indices where !groups[index].isEmpty && result.count < wanted { result.append(groups[index].removeLast()) }
        }
        return result.shuffled()
    }

    static func start(quiz: Quiz, ledger: inout QuestionBankLedger, selected: [QuizQuestion], mode: BankPracticeMode,
                      context: ModelContext, timeLimit: TimeInterval? = nil, shuffleAnswers: Bool = false, immediateRetryOf: UUID? = nil, snapshots: [UUID: BankQuestionSnapshot]? = nil, coachingOriginID: UUID? = nil) throws -> UUID {
        if ledger.accountID == nil && ledger.sessions.isEmpty { ledger.accountID = RevisionHistoryService.accountID }
        guard ledger.accountID == RevisionHistoryService.accountID else { throw QuestionBankError.invalid("Account changed. Reopen practice before submitting.") }
        guard !selected.isEmpty else { throw QuestionBankError.invalid("No questions match these filters.") }
        if mode == .exam && selected.count != 5 { throw QuestionBankError.invalid("Five-question exam practice requires at least five matching questions.") }
        if mode == .teacherMock && !ExamLabService.canUseAsTeacherMock(quiz) { throw QuestionBankError.invalid("AI and authored practice are separate from imported teacher mocks.") }
        let metadata = try ExamLabService.metadata(quizID: quiz.id, context: context)
        let ordered = mode == .teacherMock ? quiz.questions.sorted { $0.position < $1.position } : selected
        var session = BankPracticeSession(mode: mode, questions: ordered.map { question in
            var snapshot = snapshots?[question.id] ?? BankQuestionSnapshot(question)
            if snapshots?[question.id] == nil { snapshot.rubric = metadata.rubrics[question.id]; snapshot.difficultyLevel = metadata.difficultyLevels?[question.id] }
            var run = BankQuestionRun(question: snapshot)
            run.writtenResponse = (mode == .teacherMock && ExamLabService.isWritten(snapshot)) || metadata.writtenQuestionIDs.contains(question.id)
            let options = snapshot.type == .trueFalse && snapshot.choices.isEmpty ? ["True", "False"] : snapshot.choices
            run.choiceOrder = mode != .teacherMock && shuffleAnswers ? Array(options.indices).shuffled() : Array(options.indices)
            return run
        })
        session.timeLimitSeconds = timeLimit
        session.immediateRetryOf = immediateRetryOf
        session.coachingOriginID = coachingOriginID
        var next = ledger; next.sessions.append(session)
        ledger = try save(next, quiz: quiz, context: context)
        return session.id
    }

    static func submit(_ run: inout BankQuestionRun, mode: BankPracticeMode) throws {
        guard run.submittedAt == nil else { return }
        guard !run.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuestionBankError.invalid("Enter or select an answer before submitting.") }
        if mode == .teacherMock {
            run.savedAt = .now; run.skipped = false
            return
        }
        let question = run.question.gradingQuestion()
        if run.writtenResponse == true { run.submittedAt = .now; return }
        if let error = QuizScoringService.keyError(question: question) { throw QuestionBankError.invalid(error) }
        if let error = QuizScoringService.inputError(question: question, answer: run.answer) { throw QuestionBankError.invalid(error) }
        run.submittedAt = .now
        if mode != .exam { run.correct = QuizScoringService.isCorrect(question: question, answer: run.answer) }
    }

    static func finish(_ session: inout BankPracticeSession) throws {
        guard !session.isCompleted else { return }
        if session.isTeacherMock {
            for i in session.questions.indices {
                let blank = session.questions[i].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                session.questions[i].skipped = blank
                session.questions[i].submittedAt = session.questions[i].submittedAt ?? .now
            }
        } else {
            guard session.questions.allSatisfy({ $0.submittedAt != nil }) else { throw QuestionBankError.invalid("Submit or skip every question before completing the session.") }
        }
        for index in session.questions.indices {
            let run = session.questions[index]
            if run.skipped == true || run.writtenResponse == true { session.questions[index].correct = nil; continue }
            if let error = QuizScoringService.keyError(question: run.question.gradingQuestion()) { throw QuestionBankError.invalid(error) }
            session.questions[index].correct = QuizScoringService.isCorrect(question: run.question.gradingQuestion(), answer: run.answer)
        }
        session.completedAt = .now
    }

    @discardableResult static func save(_ ledger: QuestionBankLedger, quiz: Quiz, context: ModelContext) throws -> QuestionBankLedger {
        guard ledger.accountID == RevisionHistoryService.accountID else { throw QuestionBankError.invalid("Account changed. Reopen practice before submitting.") }
        let transaction = ModelContext(context.container)
        transaction.autosaveEnabled = false
        let quizzes = try transaction.fetch(FetchDescriptor<Quiz>())
        guard let savedQuiz = quizzes.first(where: { $0.id == quiz.id }) else { throw QuestionBankError.invalid("This bank is no longer saved. Close and reopen Study.") }
        var committed = try load(quizID: quiz.id, context: transaction)
        for incoming in ledger.sessions {
            if let index = committed.sessions.firstIndex(where: { $0.id == incoming.id }) {
                let saved = committed.sessions[index]
                if saved.isCompleted {
                    var annotated = saved
                    annotated.reviewAfterAt = incoming.reviewAfterAt ?? saved.reviewAfterAt
                    for i in annotated.questions.indices {
                        if let candidate = incoming.questions.first(where: { $0.id == annotated.questions[i].id }) {
                            annotated.questions[i].aiFeedback = candidate.aiFeedback ?? annotated.questions[i].aiFeedback
                            annotated.questions[i].coachingExplanation = candidate.coachingExplanation ?? annotated.questions[i].coachingExplanation
                            annotated.questions[i].coachingSourceIDs = candidate.coachingSourceIDs ?? annotated.questions[i].coachingSourceIDs
                            annotated.questions[i].suspectedKeyIssue = candidate.suspectedKeyIssue ?? annotated.questions[i].suspectedKeyIssue
                            if candidate.suspectedKeyIssue != nil { annotated.questions[i].markedForReview = true; annotated.coaching = nil }
                        }
                    }
                    committed.sessions[index] = annotated
                    continue
                }
                var merged = incoming
                merged.startedAt = saved.startedAt; merged.timeLimitSeconds = saved.timeLimitSeconds
                merged.mode = saved.mode; merged.immediateRetryOf = saved.immediateRetryOf
                for i in merged.questions.indices {
                    if let original = saved.questions.first(where: { $0.id == merged.questions[i].id }) {
                        merged.questions[i].question = original.question
                        merged.questions[i].choiceOrder = original.choiceOrder
                        merged.questions[i].writtenResponse = original.writtenResponse
                    }
                }
                for questionIndex in merged.questions.indices {
                    if let original = saved.questions.first(where: { $0.id == merged.questions[questionIndex].id }),
                       original.submittedAt != nil && (original.correct != nil || merged.questions[questionIndex].submittedAt == nil) {
                        let candidate = merged.questions[questionIndex]
                        let flag = candidate.markedForReview
                        merged.questions[questionIndex] = original
                        merged.questions[questionIndex].coachingExplanation = candidate.coachingExplanation ?? original.coachingExplanation
                        merged.questions[questionIndex].coachingSourceIDs = candidate.coachingSourceIDs ?? original.coachingSourceIDs
                        merged.questions[questionIndex].suspectedKeyIssue = candidate.suspectedKeyIssue ?? original.suspectedKeyIssue
                        merged.questions[questionIndex].markedForReview = flag
                    }
                }
                committed.sessions[index] = merged
            } else { committed.sessions.append(incoming) }
        }
        // A schedule update belongs to the same commit as the answer. Immediate
        // successes never replace the original unresolved-mistake reminder.
        for i in committed.sessions.indices where committed.sessions[i].reviewAfterAt == nil {
            if let first = committed.sessions[i].questions.filter({ $0.correct == false || $0.skipped == true }).compactMap(\.submittedAt).min() {
                committed.sessions[i].reviewAfterAt = first.addingTimeInterval(86400)
            }
        }
        let title = progressTitle(quiz.id)
        let allNotes = try transaction.fetch(FetchDescriptor<StudyNote>())
        let note = allNotes.first { $0.title == title && $0.body.hasPrefix(marker) } ?? StudyNote(title: title, course: savedQuiz.course, chapter: savedQuiz.chapter)
        if note.modelContext == nil { transaction.insert(note) }
        note.body = marker + String(decoding: try JSONEncoder().encode(committed), as: UTF8.self)
        note.updatedAt = .now
        let attempts = try transaction.fetch(FetchDescriptor<QuizAttempt>())
        for session in committed.sessions {
            try RevisionHistoryService.stageBank(session, quiz: savedQuiz, owner: RevisionHistoryService.accountID, context: transaction)
            let attempt = attempts.first { $0.id == session.id } ?? QuizAttempt(id: session.id, startedAt: session.startedAt, quiz: savedQuiz)
            if attempt.modelContext == nil { transaction.insert(attempt) }
            attempt.answers = session.questions.map(\.answer)
            attempt.score = Double(session.score); attempt.maximumScore = Double(session.objectivelyAvailable)
            attempt.completedAt = session.completedAt; attempt.isCompleted = session.isCompleted
            attempt.duration = session.questions.reduce(0) { $0 + $1.seconds }
        }
        let disputedIDs = Set(committed.sessions.flatMap(\.questions).filter { $0.suspectedKeyIssue != nil }.map(\.id))
        for i in committed.sessions.indices where committed.sessions[i].isCompleted {
            if committed.sessions[i].coaching?.evidence.contains(where: { disputedIDs.contains($0.questionID) }) == true { committed.sessions[i].coaching = nil }
            if committed.sessions[i].coaching == nil {
                // Coaching never calls a provider in this persistence path.
                committed.sessions[i].coaching = try? RevisionCoachingService.report(session: committed.sessions[i], quiz: savedQuiz, ledger: committed, context: transaction)
            }
            try RevisionHistoryService.stageBank(committed.sessions[i], quiz: savedQuiz, owner: RevisionHistoryService.accountID, context: transaction)
        }
        note.body = marker + String(decoding: try JSONEncoder().encode(committed), as: UTF8.self)
        do { try transaction.save() } catch { transaction.rollback(); throw error }
        return committed
    }
}
