import AppKit
import Foundation
import SwiftData

/// Append-only snapshots deliberately have no relationships: deleting or editing a
/// course/question must never cascade into the student's answer history.
struct RevisionAnswer: Codable, Identifiable {
    var id: UUID
    var courseID: UUID? = nil
    var course: String? = nil
    var chapterID: UUID? = nil
    var chapter: String? = nil
    var question: BankQuestionSnapshot
    var questionVersion: String
    var submittedAnswer: String
    var submittedAt: Date?
    var result: String
    var pointsEarned: Int?
    var pointsAvailable: Int?
    var hintRevealed: Bool
    var modelAnswerRevealed: Bool
    var gradingMethod: String
    var gradingDetail: String? = nil
    var activeSeconds: TimeInterval
    var flaggedForReview: Bool
    var suspectedKeyIssue: String? = nil
    var coachingExplanation: String? = nil
}

struct RevisionSessionRecord: Codable, Identifiable {
    var formatVersion = 1
    var id: UUID
    var accountID: String
    var activity: String
    var courseID: UUID?
    var course: String
    var chapterID: UUID?
    var chapter: String
    var startedAt: Date
    var answers: [RevisionAnswer]
    var quizID: UUID? = nil
    var isCompleted: Bool? = nil
    var sessionKind: String? = nil
    var immediateRetryOf: UUID? = nil
    var reviewAfterAt: Date? = nil
    var coaching: RevisionCoachingReport? = nil
}

@MainActor enum RevisionHistoryService {
    static let marker = "UniSaverRevisionHistoryV1:\n"
    static var accountID: String { AccountSyncService().conversationAccountID() }
    static func version(_ question: BankQuestionSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return QuestionBankImportService.digest(String(decoding: try encoder.encode(question), as: UTF8.self))
    }
    static func records(context: ModelContext, owner: String? = nil) throws -> [RevisionSessionRecord] {
        let owner = owner ?? accountID
        return try context.fetch(FetchDescriptor<StudyNote>()).filter { $0.body.hasPrefix(marker) }.compactMap { note in
            let record = try JSONDecoder().decode(RevisionSessionRecord.self, from: Data(note.body.dropFirst(marker.count).utf8))
            return record.accountID == owner ? record : nil
        }.sorted { $0.startedAt > $1.startedAt }
    }
    /// Caller saves this together with the source event/ledger. A stable session
    /// key makes repeated submissions and refreshes idempotent.
    static func stage(_ record: RevisionSessionRecord, context: ModelContext) throws {
        guard record.accountID == accountID else { throw QuestionBankError.invalid("Account changed. Reopen practice before submitting.") }
        let title = "Revision history " + QuestionBankImportService.digest(record.accountID) + " " + record.id.uuidString
        let note = try context.fetch(FetchDescriptor<StudyNote>()).first { $0.title == title && $0.body.hasPrefix(marker) }
            ?? StudyNote(title: title)
        if note.modelContext == nil { context.insert(note) }
        var merged = record
        for i in merged.answers.indices {
            if merged.answers[i].course == nil {
                merged.answers[i].courseID = record.courseID; merged.answers[i].course = record.course
                merged.answers[i].chapterID = record.chapterID; merged.answers[i].chapter = record.chapter
            }
        }
        if note.body.hasPrefix(marker) {
            let previous = try JSONDecoder().decode(RevisionSessionRecord.self, from: Data(note.body.dropFirst(marker.count).utf8))
            // Once submitted, the answer/key/time cannot be overwritten by a stale view.
            for answer in previous.answers where answer.submittedAt != nil {
                if let index = merged.answers.firstIndex(where: { $0.id == answer.id }) {
                    if merged.answers[index].submittedAt == nil || answer.result != "Awaiting grading" {
                        let flag = merged.answers[index].flaggedForReview
                        let revealed = merged.answers[index].modelAnswerRevealed
                        merged.answers[index] = answer
                        merged.answers[index].flaggedForReview = flag
                        merged.answers[index].modelAnswerRevealed = answer.modelAnswerRevealed || revealed
                        let annotation = record.answers.first { $0.id == answer.id }
                        merged.answers[index].suspectedKeyIssue = annotation?.suspectedKeyIssue ?? answer.suspectedKeyIssue
                        merged.answers[index].coachingExplanation = annotation?.coachingExplanation ?? answer.coachingExplanation
                        if answer.result == "Written response · needs review" {
                            merged.answers[index].gradingDetail = record.answers.first { $0.id == answer.id }?.gradingDetail ?? answer.gradingDetail
                            if merged.answers[index].gradingDetail != nil { merged.answers[index].gradingMethod = "AI-assisted · provisional feedback only" }
                        }
                    }
                } else { merged.answers.append(answer) }
            }
        }
        note.body = marker + String(decoding: try JSONEncoder().encode(merged), as: UTF8.self)
        note.updatedAt = .now
    }
    static func stageBank(_ session: BankPracticeSession, quiz: Quiz, owner: String, context: ModelContext) throws {
        let answers = try session.questions.map { run in
            RevisionAnswer(id: run.id, question: run.question, questionVersion: try version(run.question),
                submittedAnswer: run.answer, submittedAt: run.submittedAt,
                result: run.resultTitle,
                pointsEarned: run.correct.map { $0 ? run.question.points : 0 }, pointsAvailable: run.question.points,
                hintRevealed: (run.hintsUsed ?? 0) > 0, modelAnswerRevealed: run.modelAnswerRevealed ?? false,
                gradingMethod: run.writtenResponse == true ? (run.aiFeedback == nil ? "Pending written review" : "AI-assisted · provisional feedback only") : "Automatic", gradingDetail: run.aiFeedback, activeSeconds: run.seconds, flaggedForReview: run.markedForReview ?? false, suspectedKeyIssue: run.suspectedKeyIssue, coachingExplanation: run.coachingExplanation)
        }
        try stage(RevisionSessionRecord(id: session.id, accountID: owner, activity: quiz.title + " · " + session.mode.title,
            courseID: quiz.course?.id, course: quiz.course?.name ?? "No course", chapterID: quiz.chapter?.id,
            chapter: quiz.chapter?.title ?? "", startedAt: session.startedAt, answers: answers, quizID: quiz.id, isCompleted: session.isCompleted, sessionKind: session.mode.rawValue, immediateRetryOf: session.immediateRetryOf, reviewAfterAt: session.reviewAfterAt, coaching: session.coaching), context: context)
    }
}

/// Monotonic time, sampled only while this practice view is visible, the app is
/// active and the student has not paused. Notifications close background spans.
@MainActor final class RevisionAnswerClock {
    private let now: () -> TimeInterval
    private let isActive: () -> Bool
    private var accumulated: TimeInterval = 0
    private var began: TimeInterval?
    private var paused = false
    private var visible = false
    private var observers: [NSObjectProtocol] = []
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, isActive: @escaping () -> Bool = { NSApp.isActive }) {
        self.now = now; self.isActive = isActive
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.willResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.update(active: notification.name == NSApplication.didBecomeActiveNotification)
                }
            })
        }
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private func close() {
        if let began { accumulated += max(0, now() - began) }
        began = nil
    }
    private func update(active: Bool) {
        close()
        if visible && !paused && active { began = now() }
    }
    func show() { visible = true; update(active: isActive()) }
    func hide() { visible = false; close() }
    func pause(_ value: Bool) { paused = value; update(active: isActive()) }
    func take() -> TimeInterval { close(); let result = accumulated; accumulated = 0; update(active: isActive()); return result }
}
