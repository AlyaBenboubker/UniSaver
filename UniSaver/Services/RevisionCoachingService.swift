import Foundation
import SwiftData

struct RevisionEvidenceReference: Codable, Hashable {
    var sessionID: UUID
    var questionID: UUID
    var questionVersion: String
    var submittedAt: Date
    var id: String { "attempt:\(sessionID.uuidString):\(questionID.uuidString):\(questionVersion)" }
}

struct RevisionRecommendation: Codable, Identifiable {
    var id = UUID()
    var accountID: String
    var quizID: UUID
    var sourceSessionID: UUID
    var title: String
    var reason: String
    var topic: String?
    var questionVersions: [UUID: String]
    var evidence: [RevisionEvidenceReference]
    var difficultyLevel: Int
    var difficultyReason: String
}

struct RevisionCoachingReport: Codable {
    var createdAt: Date
    var summary: String
    var pattern: String
    var recommendation: RevisionRecommendation?
    var evidence: [RevisionEvidenceReference]
}

/// Summaries, counts, progression and the action to start are computed from
/// committed records. A language model cannot fabricate or change these facts.
@MainActor enum RevisionCoachingService {
    private struct Observation {
        var sessionID: UUID
        var answer: RevisionAnswer
        var reference: RevisionEvidenceReference
    }
    static func snapshot(_ question: QuizQuestion, paper: ExamLabPaperMetadata) -> BankQuestionSnapshot {
        var value = BankQuestionSnapshot(question)
        value.rubric = paper.rubrics[question.id]
        value.difficultyLevel = paper.difficultyLevels?[question.id]
        return value
    }
    static func includes(_ record: RevisionSessionRecord, quiz: Quiz) -> Bool {
        guard let courseID = quiz.course?.id else { return record.quizID == quiz.id }
        return record.courseID == courseID && (quiz.chapter == nil || record.chapterID == quiz.chapter?.id)
    }
    static func liveVersions(quiz: Quiz, context: ModelContext) throws -> [UUID: String] {
        let banks = try context.fetch(FetchDescriptor<Quiz>()).filter { bank in
            !bank.isArchived && (quiz.course == nil ? bank.id == quiz.id : bank.course?.id == quiz.course?.id && (quiz.chapter == nil || bank.chapter?.id == quiz.chapter?.id))
        }
        var versions: [UUID: String] = [:]
        for bank in banks {
            let paper = try ExamLabService.metadata(quizID: bank.id, context: context)
            for question in bank.questions { versions[question.id] = try RevisionHistoryService.version(snapshot(question, paper: paper)) }
        }
        return versions
    }
    static func report(session: BankPracticeSession, quiz: Quiz, ledger: QuestionBankLedger,
                       context: ModelContext, now: Date = .now) throws -> RevisionCoachingReport {
        guard ledger.accountID == RevisionHistoryService.accountID, session.isCompleted else {
            throw QuestionBankError.invalid("Finish and save this account’s session before requesting coaching.")
        }
        let paper = try ExamLabService.metadata(quizID: quiz.id, context: context)
        let versions = try liveVersions(quiz: quiz, context: context)
        let records = try RevisionHistoryService.records(context: context).filter { includes($0, quiz: quiz) && $0.immediateRetryOf == nil }
        var seen = Set<String>()
        let observations: [Observation] = records.flatMap { record in
            record.answers.compactMap { answer -> Observation? in
                guard let date = answer.submittedAt, versions[answer.id] == answer.questionVersion,
                      answer.suspectedKeyIssue == nil, answer.result == "Incorrect" || answer.result.hasPrefix("Correct"),
                      answer.gradingMethod == "Automatic" else { return nil }
                let reference = RevisionEvidenceReference(sessionID: record.id, questionID: answer.id, questionVersion: answer.questionVersion, submittedAt: date)
                guard seen.insert(reference.id).inserted else { return nil }
                return Observation(sessionID: record.id, answer: answer, reference: reference)
            }
        }.sorted { $0.reference.submittedAt < $1.reference.submittedAt }
        let excludedTags = Set([quiz.course?.name, quiz.chapter?.title, "AI-generated"].compactMap { $0 })
        func concepts(_ answer: RevisionAnswer) -> [String] { Array(Set(answer.question.tags.filter { !excludedTags.contains($0) })).sorted() }
        let errors = observations.filter { $0.answer.result == "Incorrect" }
        var groups: [String: [Observation]] = [:]
        for observation in errors {
            for topic in concepts(observation.answer) { groups[topic, default: []].append(observation) }
        }
        let repeated = groups.filter { $0.value.count >= 2 && Set($0.value.map { $0.answer.id }).count >= 2 }
            .sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }.first
        let pattern: String
        if let repeated {
            pattern = "Your repeated difficulty was \(repeated.key): \(repeated.value.count) recorded incorrect attempts across \(Set(repeated.value.map { $0.answer.id }).count) different questions in the saved course/chapter history."
        } else if errors.count == 1 {
            pattern = "One recorded mistake is not enough to establish a repeated difficulty."
        } else if errors.count > 1 {
            pattern = "There are \(errors.count) recorded mistakes, but no repeated difficulty across different questions in a shared topic is demonstrated."
        } else {
            pattern = "No repeated difficulty is demonstrated by the recorded objective attempts."
        }
        let targetTopic = repeated?.key ?? errors.last.flatMap { concepts($0.answer).first }
        let recent = Array(observations.filter { !$0.answer.hintRevealed && (targetTopic == nil || concepts($0.answer).contains(targetTopic!)) }.suffix(4))
        let distinct = Set(recent.map { $0.answer.id }).count
        let baseLevel = session.questions.compactMap(\.question.difficultyLevel).min() ?? 3
        var level = baseLevel
        var difficultyReason = "Keep the current relative level (\(baseLevel)/5), guided by supplied examples; there is not enough independent evidence to change it."
        if recent.count >= 2 && distinct >= 2 && recent.filter({ $0.answer.result == "Incorrect" }).count >= 2 {
            level = max(1, baseLevel - 1)
            difficultyReason = baseLevel == 1 ? "Recorded mistakes support keeping the most scaffolded level; the scale does not go below 1." : "Two independent recorded mistakes on different questions support one smaller, more scaffolded step."
        } else if recent.count == 4 && distinct >= 3 && Set(recent.map(\.sessionID)).count >= 2 && recent.allSatisfy({ $0.answer.result == "Correct without help" && ($0.answer.question.difficultyLevel ?? 3) >= baseLevel }) {
            level = min(5, baseLevel + 1)
            difficultyReason = baseLevel == 5 ? "Four unassisted correct attempts support retaining the highest relative level; the scale does not go above 5." : "Four unassisted correct attempts across at least three questions and two sessions support one step up. Immediate retries are excluded."
        }
        let writtenIDs = Set(session.questions.filter { $0.writtenResponse == true }.map(\.id)).union(paper.writtenQuestionIDs)
        let disputed = Set(ledger.sessions.flatMap(\.questions).filter { $0.suspectedKeyIssue != nil }.map(\.id))
        let eligible = quiz.questions.filter { !writtenIDs.contains($0.id) && !disputed.contains($0.id) && QuizScoringService.keyError(question: $0) == nil }
        let unresolved = ledger.mistakeIDs
        let due = ledger.dueIDs(now: now)
        let matchingTopic = targetTopic.map { topic in eligible.filter { $0.tags.contains(topic) } } ?? []
        let activityTopic = matchingTopic.isEmpty ? nil : targetTopic
        let pool = matchingTopic.isEmpty ? eligible : matchingTopic
        if targetTopic != nil && matchingTopic.isEmpty {
            level = baseLevel
            difficultyReason = "There are no eligible questions in the demonstrated topic in this bank; keep the current level while gathering evidence."
        }
        let selected = Array(pool.sorted { lhs, rhs in
            func priority(_ question: QuizQuestion) -> Int {
                (unresolved.contains(question.id) ? 100 : 0) + (due.contains(question.id) ? 20 : 0) + (targetTopic.map { question.tags.contains($0) ? 10 : 0 } ?? 0)
            }
            return priority(lhs) == priority(rhs) ? lhs.position < rhs.position : priority(lhs) > priority(rhs)
        }.prefix(3))
        let refs = observations.map(\.reference)
        let recommendation: RevisionRecommendation?
        if selected.isEmpty {
            recommendation = nil
        } else {
            let unresolvedCount = selected.filter { unresolved.contains($0.id) }.count
            let reason = unresolvedCount > 0 ? "\(unresolvedCount) selected question(s) still have unresolved recorded mistakes or skips. Immediate success will not clear the later recall check." : selected.contains(where: { due.contains($0.id) }) ? "These questions are due according to the saved review schedule." : "Use a short practice to gather more evidence; the recorded history does not justify claiming mastery."
            recommendation = RevisionRecommendation(accountID: RevisionHistoryService.accountID, quizID: quiz.id, sourceSessionID: session.id,
                title: "\(selected.count)-question practice" + (activityTopic.map { " · " + $0 } ?? ""), reason: reason, topic: activityTopic,
                questionVersions: try Dictionary(uniqueKeysWithValues: selected.map { ($0.id, try RevisionHistoryService.version(snapshot($0, paper: paper))) }),
                evidence: refs, difficultyLevel: level, difficultyReason: difficultyReason)
        }
        let answered = session.questions.filter { $0.submittedAt != nil && $0.skipped != true }.count
        let next = recommendation.map { "Next, do \($0.title)." } ?? "Next, review the saved written responses or flagged answer keys; no eligible objective practice is available."
        return RevisionCoachingReport(createdAt: now, summary: "You practised \(answered) question(s) in \(quiz.title). \(pattern) \(next)", pattern: pattern,
            recommendation: recommendation, evidence: refs)
    }

    /// Revalidate against the current store and account; never silently practise
    /// a newly edited version using the recommendation's old evidence.
    static func startRecommended(_ recommendation: RevisionRecommendation, context: ModelContext) throws -> (Quiz, QuestionBankLedger, UUID) {
        guard recommendation.accountID == RevisionHistoryService.accountID else { throw QuestionBankError.invalid("Account changed. Reopen the session.") }
        guard let quiz = try context.fetch(FetchDescriptor<Quiz>()).first(where: { $0.id == recommendation.quizID && !$0.isArchived }) else { throw QuestionBankError.invalid("The recommended bank is no longer available.") }
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        if let existing = ledger.sessions.first(where: { $0.coachingOriginID == recommendation.id }) { return (quiz, ledger, existing.id) }
        let paper = try ExamLabService.metadata(quizID: quiz.id, context: context)
        let selected = quiz.questions.filter { recommendation.questionVersions[$0.id] != nil }.sorted { $0.position < $1.position }
        guard selected.count == recommendation.questionVersions.count, !selected.isEmpty else { throw QuestionBankError.invalid("Recommended questions changed. Choose a new practice from setup.") }
        for question in selected {
            guard try RevisionHistoryService.version(snapshot(question, paper: paper)) == recommendation.questionVersions[question.id],
                  !ledger.sessions.flatMap(\.questions).contains(where: { $0.id == question.id && $0.suspectedKeyIssue != nil }) else {
                throw QuestionBankError.invalid("A recommended question changed or its key needs review. Choose a new practice from setup.")
            }
        }
        let source = try requireSession(recommendation.sourceSessionID, ledger: ledger)
        let hasJustSeenCorrection = selected.contains { question in source.questions.contains { $0.id == question.id } } && Date().timeIntervalSince(source.completedAt ?? .distantPast) < 86400
        let id = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: selected, mode: .mixed, context: context,
            immediateRetryOf: hasJustSeenCorrection ? source.id : nil, coachingOriginID: recommendation.id)
        return (quiz, ledger, id)
    }
    private static func requireSession(_ id: UUID, ledger: QuestionBankLedger) throws -> BankPracticeSession {
        guard let session = ledger.sessions.first(where: { $0.id == id && $0.isCompleted }) else { throw QuestionBankError.invalid("Save and finish the source session first.") }
        return session
    }
}
