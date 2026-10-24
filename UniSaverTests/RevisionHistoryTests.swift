import AppKit

import Foundation
import SwiftData
import Testing
@testable import UniSaver

struct RevisionHistoryTests {
    @MainActor private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = PersistenceController.schema
        let config = url.map { ModelConfiguration(schema: schema, url: $0) } ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
    @MainActor private func quiz(_ context: ModelContext) throws -> Quiz {
        let course = Course(name: "History", code: "H")
        let quiz = Quiz(title: "Revision", course: course)
        let question = QuizQuestion(prompt: "Capital?", type: .shortAnswer, correctAnswers: ["Paris"], explanation: "France", tags: ["Geography"], quiz: quiz)
        context.insert(course); context.insert(quiz); context.insert(question)
        try context.save()
        return quiz
    }
    @Test @MainActor func submissionIsDurableIdempotentAndRetriesKeepVersions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        var originalVersion = ""
        var quizID = UUID()
        do {
            let store = try container(url: url)
            let context = ModelContext(store)
            let quiz = try quiz(context); quizID = quiz.id
            var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
            _ = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: quiz.questions, mode: .mixed, context: context)
            let stale = ledger
            ledger.sessions[0].questions[0].answer = "Paris"
            ledger.sessions[0].questions[0].hintsUsed = 1
            ledger.sessions[0].questions[0].markedForReview = true
            ledger.sessions[0].questions[0].seconds = 7
            try QuestionBankSessionService.submit(&ledger.sessions[0].questions[0], mode: .mixed)
            let date = ledger.sessions[0].questions[0].submittedAt
            try QuestionBankSessionService.submit(&ledger.sessions[0].questions[0], mode: .mixed)
            #expect(ledger.sessions[0].questions[0].submittedAt == date)
            ledger = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
            _ = try QuestionBankSessionService.save(stale, quiz: quiz, context: context)
            let records = try RevisionHistoryService.records(context: ModelContext(store))
            #expect(records.count == 1)
            #expect(records[0].answers[0].result == "Correct with help")
            #expect(records[0].answers[0].activeSeconds == 7)
            originalVersion = records[0].answers[0].questionVersion
            // The live answer key changes while the old session's snapshot stays intact.
            quiz.questions[0].correctAnswers = ["Lyon"]
            try context.save()
            _ = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: quiz.questions, mode: .mixed, context: context)
            ledger.sessions[1].questions[0].answer = "Paris"
            try QuestionBankSessionService.submit(&ledger.sessions[1].questions[0], mode: .mixed)
            _ = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
            #expect(ledger.sessions[0].questions[0].correct == true)
            #expect(ledger.sessions[1].questions[0].correct == false)
        }
        do {
            let reopened = try container(url: url)
            let context = ModelContext(reopened)
            let records = try RevisionHistoryService.records(context: context)
            #expect(records.count == 2)
            #expect(Set(records.flatMap(\.answers).map(\.questionVersion)).count == 2)
            #expect(records.flatMap(\.answers).contains { $0.questionVersion == originalVersion && $0.question.correctAnswers == ["Paris"] })
            #expect(try QuestionBankSessionService.load(quizID: quizID, context: context).sessions.count == 2)
            #expect(try RevisionHistoryService.records(context: context, owner: "another-account").isEmpty)
            var foreign = records[0]; foreign.accountID = "another-account"
            #expect(throws: (any Error).self) { try RevisionHistoryService.stage(foreign, context: context) }
        }
    }
    @Test @MainActor func skippedUnansweredAndReviewFlagsAreIndependent() throws {
        let store = try container(); let context = ModelContext(store); let quiz = try quiz(context)
        var ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
        _ = try QuestionBankSessionService.start(quiz: quiz, ledger: &ledger, selected: quiz.questions, mode: .mixed, context: context)
        #expect(try RevisionHistoryService.records(context: ModelContext(store))[0].answers[0].result == "Unanswered")
        ledger.sessions[0].questions[0].skipped = true
        ledger.sessions[0].questions[0].submittedAt = .now
        ledger.sessions[0].questions[0].markedForReview = true
        try QuestionBankSessionService.finish(&ledger.sessions[0])
        _ = try QuestionBankSessionService.save(ledger, quiz: quiz, context: context)
        let answer = try RevisionHistoryService.records(context: ModelContext(store))[0].answers[0]
        #expect(answer.result == "Skipped")
        #expect(answer.flaggedForReview)
        #expect(answer.pointsEarned == nil)
    }
    @Test @MainActor func activeClockExcludesPauseBackgroundAndHiddenTime() {
        var now: TimeInterval = 0
        let clock = RevisionAnswerClock(now: { now }, isActive: { true })
        clock.show(); now = 5; clock.pause(true)
        now = 50; clock.pause(false); now = 54; clock.hide()
        now = 100
        #expect(clock.take() == 9)
        clock.show(); now = 102
        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)
        now = 200
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        now = 203
        #expect(clock.take() == 5)
    }
}
