import Foundation
import Testing
@testable import UniSaver

struct RevisionTopicTests {
    @Test @MainActor func tagsAreNotAutomaticallyTopics() {
        let course = Course(name: "Accounting II", code: "ACC2")
        let question = QuizQuestion(prompt: "Imported question", tags: ["Accounting II", "Acquisition", "Vague label"])
        let quiz = Quiz(title: "Consolidation", course: course, questions: [question])
        let profile = AdaptiveExamPrepStore.profile(for: course, notes: [], quizzes: [quiz])
        #expect(question.tags.count == 3)
        #expect(profile.concepts.isEmpty)
    }

    @Test @MainActor func aliasesAndExplicitAssignmentsPreserveQuestionIdentity() {
        let question = QuizQuestion(prompt: "Original question", tags: ["Goodwill", "Accounting II"])
        var topic = AdaptiveConcept(name: "Acquisition", mergedNames: ["Goodwill"])
        #expect(topic.matches(question))
        topic.name = "Acquisition and goodwill"
        topic.isHidden = true
        #expect(topic.matches(question))
        #expect(question.tags == ["Goodwill", "Accounting II"])
        topic.questionIDs = []
        #expect(!topic.matches(question))
        topic.questionIDs = [question.id]
        #expect(topic.matches(question))
    }

    @Test func renamedTopicKeepsHistoricalEvidence() {
        let record = AdaptiveQuestionEvidence(questionID: UUID(), prompt: "Question", concepts: ["Goodwill"], answer: "A", wasCorrect: false, hintsUsed: 0, attemptedAt: .now, responseTime: 1, sourceReference: "Teacher bank")
        let profile = AdaptiveExamProfile(courseID: UUID(), courseName: "Accounting II", concepts: [AdaptiveConcept(name: "Acquisition", mergedNames: ["Goodwill"])], evidence: [record])
        #expect(profile.evidence(for: "Acquisition").count == 1)
        #expect(profile.evidence.first?.answer == "A")
    }

    @Test @MainActor func focusAndHintsDoNotChangeSubmissionOrGrading() {
        let session = QuizPracticeSession()
        session.answers = ["A"]
        session.hinted.insert(0)
        #expect(session.submitCurrent())
        session.isFocused = true
        session.isFocused = false
        #expect(session.answers == ["A"])
        #expect(session.submitted == [0])
        #expect(!session.submitCurrent())
    }
}
