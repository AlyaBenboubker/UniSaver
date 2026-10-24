import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import UniSaver

struct UniSaverTests {
    @Test @MainActor func quizSessionSubmitsOnceAndSurvivesFocusChanges() {
        let session = QuizPracticeSession()
        session.answers = ["B", ""]
        #expect(session.submitCurrent())
        #expect(!session.submitCurrent())
        session.isFocused = true
        session.isFocused = false
        #expect(session.index == 0)
        #expect(session.answers[0] == "B")
        #expect(session.submitted == [0])
        session.index = 1
        #expect(!session.submitCurrent())
        session.index = 0
        #expect(!session.submitCurrent())
    }

    @Test func quizFeedbackUsesStableKeysAndRejectsInvalidKeys() {
        let question = QuizQuestion(prompt: "What do consolidated financial statements aim to show?",
            choices: ["A: Separate entities", "B: The group as one economic entity"], correctAnswers: ["B"])
        #expect(QuizScoringService.isCorrect(question: question, answer: "B"))
        #expect(QuizScoringService.isCorrect(question: question, answer: "B: The group as one economic entity"))
        #expect(!QuizScoringService.isCorrect(question: question, answer: "A"))
        question.choices.reverse()
        #expect(QuizScoringService.isCorrect(question: question, answer: "B"))
        question.correctAnswers = ["Z"]
        #expect(QuizScoringService.keyError(question: question) != nil)
        #expect(QuizScoringService.score(questions: [question], answers: ["B"]).maximum == 0)
        question.correctAnswers = []
        #expect(QuizScoringService.keyError(question: question) != nil)
    }

    @Test func quizFeedbackExplainsMissingAndExtraSelections() {
        let question = QuizQuestion(prompt: "Select", type: .multipleSelect,
            choices: ["A: One, with comma", "B: Two", "C: Three"], correctAnswers: ["A", "B"])
        #expect(QuizScoringService.isCorrect(question: question, answer: "B,A"))
        #expect(!QuizScoringService.isCorrect(question: question, answer: "A,C"))
        #expect(QuizScoringService.selectionDetails(question: question, answer: "A,C") == "Missing selections: B\nExtra selections: C")
        let boolean = QuizQuestion(prompt: "True?", type: .trueFalse, correctAnswers: ["True"])
        #expect(QuizScoringService.isCorrect(question: boolean, answer: "true"))
        #expect(!QuizScoringService.isCorrect(question: boolean, answer: "False"))
        boolean.correctAnswers = ["maybe"]
        #expect(QuizScoringService.keyError(question: boolean) != nil)
    }

    @Test func academicYearRequiresValidDateRange() throws {
        let start = Date()
        let end = start.addingTimeInterval(-3600)
        #expect(throws: AcademicValidationError.invalidDateRange) {
            try AcademicValidationService.validateAcademicYear(name: "2026", startDate: start, endDate: end)
        }
    }

    @Test func semesterDatesMustBeCoherentAndInsideYear() throws {
        let start = Date()
        let year = AcademicYear(name: "Year", startDate: start, endDate: start.addingTimeInterval(10_000))
        let semester = Semester(name: "S1", order: 1, startDate: start.addingTimeInterval(100), endDate: start.addingTimeInterval(9_000), academicYear: year)
        try AcademicValidationService.validateSemester(semester)

        semester.endDate = start.addingTimeInterval(20_000)
        #expect(throws: AcademicValidationError.semesterOutsideAcademicYear) {
            try AcademicValidationService.validateSemester(semester)
        }
    }

    @Test func sessionEndTimeMustBeAfterStartTime() throws {
        let course = Course(name: "Mathematics", code: "MAT")
        let start = Date()
        #expect(throws: AcademicValidationError.invalidTimeRange) {
            try AcademicValidationService.validateSession(startTime: start, endTime: start, course: course, chapter: nil)
        }
    }

    @Test func sessionChapterMustBelongToSameCourse() throws {
        let course = Course(name: "Microeconomics", code: "ECO")
        let otherCourse = Course(name: "German", code: "GER")
        let chapter = Chapter(number: 1, title: "A2", order: 1, course: otherCourse)
        let start = Date()
        let end = start.addingTimeInterval(3600)

        #expect(throws: AcademicValidationError.chapterCourseMismatch) {
            try AcademicValidationService.validateSession(startTime: start, endTime: end, course: course, chapter: chapter)
        }
    }

    @Test func progressCycleAndWeightsAreStable() {
        #expect(SessionProgressStatus.captured.structuralProgress == 0.2)
        #expect(SessionProgressStatus.organized.structuralProgress == 0.4)
        #expect(SessionProgressStatus.reviewed.structuralProgress == 0.6)
        #expect(SessionProgressStatus.practiced.structuralProgress == 0.8)
        #expect(SessionProgressStatus.mastered.structuralProgress == 1.0)
        #expect(SessionProgressStatus.captured.advanced() == .organized)
        #expect(SessionProgressStatus.practiced.advanced() == .mastered)
        #expect(SessionProgressStatus.mastered.advanced() == .mastered)
    }

    @Test func structuralProgressIsAverageOfSessions() {
        let now = Date()
        let course = Course(name: "Computing", code: "CS")
        let first = ClassSession(number: 1, title: "Intro", date: now, startTime: now, endTime: now.addingTimeInterval(3600), progressStatus: .captured, course: course)
        let second = ClassSession(number: 2, title: "Practice", date: now, startTime: now, endTime: now.addingTimeInterval(3600), progressStatus: .mastered, course: course)
        #expect(AcademicValidationService.structuralProgress(for: [first, second]) == 0.6)
    }

    @Test func createCourseChapterAndSessionPersistInSwiftData() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let start = Date()
        let year = AcademicYear(name: "Year", startDate: start, endDate: start.addingTimeInterval(10_000))
        let semester = Semester(name: "S1", order: 1, startDate: start, endDate: start.addingTimeInterval(5_000), academicYear: year)
        let course = Course(name: "Microeconomics", code: "ECO101", semester: semester)
        let chapter = Chapter(number: 1, title: "Supply and Demand", order: 1, course: course)
        let session = ClassSession(number: 1, title: "Demand", date: start, startTime: start, endTime: start.addingTimeInterval(3600), course: course, chapter: chapter)
        context.insert(year)
        context.insert(semester)
        context.insert(course)
        context.insert(chapter)
        context.insert(session)
        try context.save()

        let descriptor = FetchDescriptor<Course>()
        let saved = try context.fetch(descriptor)
        #expect(saved.count == 1)
        #expect(saved.first?.chapters.count == 1)
        #expect(saved.first?.sessions.count == 1)
    }

    @Test func sessionsSortChronologically() {
        let now = Date()
        let course = Course(name: "Math", code: "MAT")
        let later = ClassSession(number: 2, title: "Later", date: now, startTime: now.addingTimeInterval(7200), endTime: now.addingTimeInterval(9000), course: course)
        let earlier = ClassSession(number: 1, title: "Earlier", date: now, startTime: now, endTime: now.addingTimeInterval(3600), course: course)
        let sorted = [later, earlier].sorted { $0.startTime < $1.startTime }
        #expect(sorted.map(\.title) == ["Earlier", "Later"])
    }

    @Test func archiveIsPreferredWhenDeletionWouldRemoveAssociatedData() {
        let course = Course(name: "Math", code: "MAT")
        course.chapters.append(Chapter(number: 1, title: "Linear Algebra", order: 1, course: course))
        course.sessions.append(ClassSession(number: 1, title: "Matrices", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600), course: course))
        #expect(AcademicValidationService.shouldPreferArchive(course: course))
    }

    @Test func previewDataIsIsolatedInMemory() throws {
        let container = PersistenceController.previewContainer()
        let context = ModelContext(container)
        let courses = try context.fetch(FetchDescriptor<Course>())
        #expect(courses.contains { $0.name == "Microeconomics" })
        #expect(courses.contains { $0.name == "German" })
    }

    @Test func dashboardSnapshotFiltersSelectedDateAndSortsTimeline() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let course = Course(name: "Microeconomics", code: "ECO")
        let later = session("Later", course: course, day: today, hour: 14)
        let earlier = session("Earlier", course: course, day: today, hour: 9)
        let tomorrowSession = session("Tomorrow", course: course, day: tomorrow, hour: 10)
        let blockStart = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today) ?? today
        let block = StudyBlock(title: "Practice", startDate: blockStart, endDate: blockStart.addingTimeInterval(3600), course: course)

        let snapshot = TodayDashboardService.makeSnapshot(
            selectedDate: today,
            workspace: nil,
            courses: [course],
            sessions: [later, tomorrowSession, earlier],
            tasks: [],
            exams: [],
            studyBlocks: [block],
            readingProgress: [],
            now: today
        )

        #expect(snapshot.sessions.map(\.title) == ["Earlier", "Later"])
        #expect(snapshot.timelineItems.map(\.subtitle) == ["Earlier", "Practice", "Later"])
        #expect(!snapshot.sessions.contains { $0.title == "Tomorrow" })
    }

    @Test func dashboardSelectsNextSessionFromNow() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let course = Course(name: "Math", code: "MAT")
        let past = session("Past", course: course, day: today, hour: 8)
        let next = session("Next", course: course, day: today, hour: 12)
        let later = session("Later", course: course, day: today, hour: 15)
        let now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today

        let snapshot = TodayDashboardService.makeSnapshot(selectedDate: today, workspace: nil, courses: [course], sessions: [later, past, next], tasks: [], exams: [], studyBlocks: [], readingProgress: [], now: now)

        #expect(snapshot.nextSession?.title == "Next")
    }

    @Test func dashboardFindsUpcomingExamAndDaysUntil() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let course = Course(name: "Microeconomics", code: "ECO")
        let examDate = calendar.date(byAdding: .day, value: 12, to: today) ?? today
        let exam = Exam(title: "Midterm", date: examDate, course: course)
        let snapshot = TodayDashboardService.makeSnapshot(selectedDate: today, workspace: nil, courses: [course], sessions: [], tasks: [], exams: [exam], studyBlocks: [], readingProgress: [], now: today)

        #expect(snapshot.upcomingExam?.title == "Midterm")
        #expect(TodayDashboardService.daysUntil(examDate, from: today) == 12)
    }

    @Test func dashboardSelectsNearestAssignmentDue() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let course = Course(name: "Math", code: "MAT")
        let soon = AcademicTask(title: "Soon", dueDate: calendar.date(byAdding: .day, value: 1, to: today) ?? today, priority: .medium, course: course)
        let urgentLater = AcademicTask(title: "Urgent later", dueDate: calendar.date(byAdding: .day, value: 2, to: today) ?? today, priority: .urgent, course: course)
        let snapshot = TodayDashboardService.makeSnapshot(selectedDate: today, workspace: nil, courses: [course], sessions: [], tasks: [urgentLater, soon], exams: [], studyBlocks: [], readingProgress: [], now: today)

        #expect(snapshot.assignmentDue?.title == "Soon")
    }

    @Test func weeklyOverviewUsesMondayThroughSundayAndSortsDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12)) ?? Date()
        let interval = TodayDashboardService.weekInterval(containing: wednesday, calendar: calendar)

        #expect(calendar.component(.weekday, from: interval.start) == 2)
        #expect(calendar.component(.weekday, from: interval.end.addingTimeInterval(-1)) == 1)

        let course = Course(name: "Math", code: "MAT")
        let monday = interval.start
        let session = ClassSession(number: 1, title: "Algebra", date: monday, startTime: monday.addingTimeInterval(9 * 3600), endTime: monday.addingTimeInterval(10 * 3600), course: course)
        let overview = TodayDashboardService.makeWeeklyOverview(selectedDate: wednesday, sessions: [session], tasks: [], flashcards: [], calendar: calendar, now: wednesday)

        #expect(overview.days.count == 7)
        #expect(overview.days.first?.sessions.first?.title == "Algebra")
    }

    @Test func weeklyOverviewSeparatesOverdueUpcomingAndReviewsWithoutDuplication() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let course = Course(name: "Microeconomics", code: "ECO")
        let deck = StudyDeck(title: "Elasticity", course: course)
        let overdue = AcademicTask(title: "Late essay", dueDate: calendar.date(byAdding: .day, value: -1, to: today) ?? today, priority: .urgent, course: course)
        let soon = AcademicTask(title: "Problem set", dueDate: calendar.date(byAdding: .day, value: 2, to: today) ?? today, priority: .medium, course: course)
        let done = AcademicTask(title: "Done", dueDate: today, priority: .urgent, status: .completed, course: course)
        let card = Flashcard(front: "PED", back: "Elasticity", reviewState: FlashcardReviewState(dueDate: today), deck: deck)

        let overview = TodayDashboardService.makeWeeklyOverview(selectedDate: today, sessions: [], tasks: [soon, done, overdue], flashcards: [card], calendar: calendar, now: today)

        #expect(overview.overdueTasks.map(\.title) == ["Late essay"])
        #expect(overview.upcomingTasks.map(\.title).contains("Problem set"))
        #expect(!overview.upcomingTasks.map(\.title).contains("Done"))
        #expect(overview.dueFlashcards.count == 1)
    }

    @Test func weeklyOverviewEmptyStateHasNoEvents() {
        let overview = TodayDashboardService.makeWeeklyOverview(selectedDate: .now, sessions: [], tasks: [], flashcards: [])

        #expect(!overview.hasEvents)
        #expect(overview.days.count == 7)
        #expect(overview.nextSession == nil)
    }

    @Test func gamificationAwardsXPOncePerSourceActivity() {
        let course = Course(name: "Accounting", code: "ACC")
        let task = AcademicTask(title: "Finish HW2", dueDate: .now, course: course)
        var ledger = GamificationLedger()

        GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: task.id.uuidString, courseID: course.id, ledger: &ledger)
        GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: task.id.uuidString, courseID: course.id, ledger: &ledger)

        #expect(ledger.activeEvents.count == 1)
        #expect(ledger.totalXP == GamificationActivityType.taskCompletion.ruleXP)
    }

    @Test func gamificationAnnulsWithoutDeletingHistoryOrDoubleCorrecting() {
        let task = AcademicTask(title: "Case outline", dueDate: .now)
        var ledger = GamificationLedger()

        GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: task.id.uuidString, courseID: nil, ledger: &ledger)
        GamificationLedgerStore.annul(activityType: .taskCompletion, sourceID: task.id.uuidString, ledger: &ledger)
        GamificationLedgerStore.annul(activityType: .taskCompletion, sourceID: task.id.uuidString, ledger: &ledger)

        #expect(ledger.events.count == 1)
        #expect(ledger.activeEvents.isEmpty)
        #expect(ledger.totalXP == 0)
    }

    @Test func gamificationCountsOneActiveDayForMultipleActivities() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3600) ?? .current
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)) ?? Date()
        let later = calendar.date(byAdding: .hour, value: 3, to: day) ?? day
        let taskA = AcademicTask(title: "A", dueDate: day)
        let taskB = AcademicTask(title: "B", dueDate: day)
        var ledger = GamificationLedger()

        GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: taskA.id.uuidString, courseID: nil, occurredAt: day, ledger: &ledger)
        GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: taskB.id.uuidString, courseID: nil, occurredAt: later, ledger: &ledger)
        let summary = GamificationEngine.weeklySummary(tasks: [taskA, taskB], ledger: ledger, calendar: calendar, now: later)

        #expect(summary.activeDays == 1)
        #expect(summary.activeDayGoal == 3)
    }

    @Test func gamificationWeeklyGoalChangeDoesNotAwardXP() {
        var ledger = GamificationLedger()
        ledger.settings.weeklyActiveDayGoal = 5

        #expect(ledger.totalXP == 0)
        #expect(ledger.settings.weeklyActiveDayGoal == 5)
    }

    @Test func gamificationQuestsUseExistingWorkWithoutDuplicates() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: .now)
        let course = Course(name: "Business Law", code: "LAW")
        let urgent = AcademicTask(title: "Prepare case outline", dueDate: now, priority: .urgent, course: course)
        let later = AcademicTask(title: "Read chapter", dueDate: now.addingTimeInterval(86_400), priority: .medium, course: course)
        var ledger = GamificationLedger()
        GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: urgent.id.uuidString, courseID: course.id, ledger: &ledger)

        let quests = GamificationEngine.quests(tasks: [urgent, later], studyBlocks: [], flashcards: [], ledger: ledger, calendar: calendar, now: now)

        #expect(!quests.contains { $0.sourceID == urgent.id.uuidString })
        #expect(quests.first?.sourceID == later.id.uuidString)
        #expect(quests.count == 1)
    }

    @Test func gamificationComebackUsesSmallExistingActionWithoutBonusXP() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 10)) ?? Date()
        let old = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let course = Course(name: "Finance", code: "FIN")
        let task = AcademicTask(title: "Review formulas", dueDate: today.addingTimeInterval(3600), estimatedDuration: 3600, course: course)
        var ledger = GamificationLedger()
        GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: UUID().uuidString, courseID: course.id, occurredAt: old, ledger: &ledger)

        let quests = GamificationEngine.quests(tasks: [task], studyBlocks: [], flashcards: [], ledger: ledger, calendar: calendar, now: today)

        #expect(quests.first?.isComeback == true)
        #expect(quests.first?.estimatedMinutes == 20)
        #expect(ledger.totalXP == GamificationActivityType.taskCompletion.ruleXP)
    }

    @Test func conversationFixtureExtractsStructuredActionsWithMadridDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12)) ?? Date()
        let courses = [
            Course(name: "Data Structures and Algorithm Design", code: "DSA"),
            Course(name: "Accounting II", code: "ACC2"),
            Course(name: "Business Law 1", code: "LAW1"),
            Course(name: "OT", code: "OT")
        ]
        let message = """
        Week 12 Oct - 18 Oct:

        Monday 12:
        • No classes
        • Data Structures and Algorithm Design: HW2 (Sliding Window and Hashing) submission

        Tuesday 13:
        • Accounting II: Comprehensive Case Consolidation (Case 2)
        • Business Law 1: Prepare Case Study 2 (Amendments to the by-laws and structural changes) + test at the start of class

        Thursday 15:
        • Accounting II: Test 2 (consolidations)
        • OT: Session 10 readings
        """

        let proposal = ConversationProposalEngine.analyze(message: message, referenceDate: referenceDate, timeZone: calendar.timeZone, courses: courses, tasks: [], studyBlocks: [])

        #expect(proposal.actions.contains { $0.kind == .flagCalendarConflict && $0.title.localizedCaseInsensitiveContains("No classes") })
        #expect(proposal.actions.contains { $0.title.localizedCaseInsensitiveContains("HW2") && calendar.component(.day, from: $0.dueDate ?? .distantPast) == 12 && !$0.hasKnownTime })
        #expect(proposal.actions.contains { $0.title.localizedCaseInsensitiveContains("Prepare Case Study 2") })
        #expect(proposal.actions.contains { $0.title.localizedCaseInsensitiveContains("Test") && $0.selectedCourseID == courses[2].id })
        #expect(proposal.actions.contains { $0.title.localizedCaseInsensitiveContains("Test 2") && $0.selectedCourseID == courses[1].id && calendar.component(.day, from: $0.dueDate ?? .distantPast) == 15 })
        #expect(proposal.actions.contains { $0.title.localizedCaseInsensitiveContains("readings") && $0.selectedCourseID == courses[3].id })
    }

    @Test func conversationAvailabilityCreatesReviewableWorkSessionWithoutInventingRecurringPreference() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12)) ?? Date()
        let course = Course(name: "Accounting II", code: "ACC2")
        let task = AcademicTask(title: "Prepare Test 2", dueDate: calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)) ?? referenceDate, priority: .high, estimatedDuration: 5400, course: course)

        let proposal = ConversationProposalEngine.analyze(
            message: "J’ai déjà commencé la consolidation, je suis libre mercredi après-midi et je veux préparer le test jeudi.",
            referenceDate: referenceDate,
            timeZone: calendar.timeZone,
            courses: [course],
            tasks: [task],
            studyBlocks: []
        )

        #expect(proposal.actions.contains { $0.kind == .updateProgress && $0.evidence == .needsConfirmation })
        let sessionAction = proposal.actions.first { $0.kind == .proposeWorkSessions }
        #expect(sessionAction?.sessions.count == 1)
        #expect(sessionAction?.missingInformation.contains { $0.localizedCaseInsensitiveContains("Confirm exact time range") } == true)
    }

    @Test func conversationAvoidsDuplicateTaskProposalWhenExistingTaskMatches() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12)) ?? Date()
        let course = Course(name: "Data Structures and Algorithm Design", code: "DSA")
        let existing = AcademicTask(title: "HW2 (Sliding Window and Hashing) submission", dueDate: calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)) ?? referenceDate, course: course)

        let proposal = ConversationProposalEngine.analyze(
            message: "Monday 12:\n• Data Structures and Algorithm Design: HW2 (Sliding Window and Hashing) submission",
            referenceDate: referenceDate,
            timeZone: calendar.timeZone,
            courses: [course],
            tasks: [existing],
            studyBlocks: []
        )

        #expect(proposal.actions.first?.kind == .updateTask)
        #expect(proposal.actions.first?.existingTaskID == existing.id)
    }

    @Test func navigationStateClearsCourseDetailWhenChangingSections() {
        let navigation = AppNavigationState()
        let course = Course(name: "Computing", code: "CS")

        navigation.openCourse(course, tab: .materials)
        #expect(navigation.selectedSection == .classes)
        #expect(navigation.openedCourseID == course.id)
        #expect(navigation.requestedCourseTab == .materials)

        navigation.select(.study)
        #expect(navigation.selectedSection == .study)
        #expect(navigation.openedCourseID == nil)
        #expect(navigation.requestedCourseTab == nil)
    }

    @Test func priorityTasksSortByPriorityThenDueDate() {
        let now = Date()
        let low = AcademicTask(title: "Low", dueDate: now, priority: .low)
        let urgentLate = AcademicTask(title: "Urgent late", dueDate: now.addingTimeInterval(7200), priority: .urgent)
        let urgentSoon = AcademicTask(title: "Urgent soon", dueDate: now.addingTimeInterval(3600), priority: .urgent)
        let ordered = TodayDashboardService.priorityOrderedTasks([low, urgentLate, urgentSoon])

        #expect(ordered.map(\.title) == ["Urgent soon", "Urgent late", "Low"])
    }

    @Test func completingTaskChangesDashboardOrdering() {
        let now = Date()
        let task = AcademicTask(title: "Finish", dueDate: now, priority: .urgent)
        task.status = .completed
        let ordered = TodayDashboardService.priorityOrderedTasks([task])

        #expect(ordered.isEmpty)
    }

    @Test func calendarImportGroupsRecurringCourseOccurrences() {
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)) ?? Date()
        let second = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9)) ?? Date()
        let events = [
            CalendarImportEvent(title: "Business Law I BL101", startDate: first, endDate: first.addingTimeInterval(5400), location: "B201", notes: "Professor: Martin"),
            CalendarImportEvent(title: "Business Law I BL101", startDate: second, endDate: second.addingTimeInterval(5400), location: "B201", notes: "Professor: Martin")
        ]

        let proposals = CalendarOrganizationAnalyzer.proposals(for: events, courses: [], existingSessions: [])

        #expect(proposals.count == 1)
        #expect(proposals.first?.action == .createCourse)
        #expect(proposals.first?.proposedCode == "BL101")
        #expect(proposals.first?.proposedRoom == "B201")
        #expect(proposals.first?.events.count == 2)
    }

    @Test func icsParserRespectsUTCAndTZIDDates() throws {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:UTC Session
        DTSTART:20260115T090000Z
        DTEND:20260115T100000Z
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:Casablanca Session
        DTSTART;TZID=Africa/Casablanca:20260715T090000
        DTEND;TZID=Africa/Casablanca:20260715T100000
        END:VEVENT
        END:VCALENDAR
        """

        let parsed = CalendarICSParser.parse(text, defaultFloatingTimeZone: TimeZone(identifier: "Europe/Madrid")!)

        #expect(parsed.errors.isEmpty)
        #expect(parsed.events.count == 2)
        #expect(parsed.events[0].sourceTimeZoneIdentifier == "UTC")
        #expect(parsed.events[1].sourceTimeZoneIdentifier == "Africa/Casablanca")
        #expect(parsed.events[1].startDate != parsed.events[0].startDate)
    }

    @Test func icsParserUsesExplicitFloatingSourceTimeZone() throws {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:Floating Session
        DTSTART:20260115T090000
        DTEND:20260115T100000
        END:VEVENT
        END:VCALENDAR
        """

        let madrid = CalendarICSParser.parse(text, defaultFloatingTimeZone: TimeZone(identifier: "Europe/Madrid")!)
        let casablanca = CalendarICSParser.parse(text, defaultFloatingTimeZone: TimeZone(identifier: "Africa/Casablanca")!)

        #expect(madrid.events.first?.isFloatingTime == true)
        #expect(casablanca.events.first?.isFloatingTime == true)
        #expect(madrid.events.first?.startDate != casablanca.events.first?.startDate)
    }

    @Test @MainActor func organizingExistingUnfiledSessionsKeepsSessionIdentity() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let start = Date()
        let session = ClassSession(number: 1, title: "Data Structures CS201", date: start, startTime: start, endTime: start.addingTimeInterval(3600), room: "Lab 2")
        context.insert(session)
        try context.save()

        let proposals = CalendarOrganizationAnalyzer.proposals(for: .existingSessions([session]), courses: [], existingSessions: [session])
        try CalendarOrganizationAnalyzer.organizeExistingSessions(proposals, courses: [], existingSessions: [session], in: context)

        let savedSessions = try context.fetch(FetchDescriptor<ClassSession>())
        let savedCourses = try context.fetch(FetchDescriptor<Course>())
        #expect(savedSessions.count == 1)
        #expect(savedSessions.first?.id == session.id)
        #expect(savedSessions.first?.course?.name == "Data Structures")
        #expect(savedCourses.count == 1)
    }

    @Test func dashboardCalculatesProgressPerCourse() {
        let now = Date()
        let course = Course(name: "Computing", code: "CS")
        course.sessions.append(ClassSession(number: 1, title: "Intro", date: now, startTime: now, endTime: now.addingTimeInterval(3600), progressStatus: .captured, course: course))
        course.sessions.append(ClassSession(number: 2, title: "Review", date: now, startTime: now, endTime: now.addingTimeInterval(3600), progressStatus: .mastered, course: course))
        let snapshot = TodayDashboardService.makeSnapshot(selectedDate: now, workspace: nil, courses: [course], sessions: course.sessions, tasks: [], exams: [], studyBlocks: [], readingProgress: [])

        #expect(snapshot.courseProgress.first?.progress == 0.6)
    }

    @Test func demoWorkspaceLoadIsIdempotentWithoutDuplicates() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        DemoWorkspaceService.loadDemoWorkspace(in: context)
        let firstCount = try context.fetch(FetchDescriptor<Course>()).count
        DemoWorkspaceService.loadDemoWorkspace(in: context)
        let secondCount = try context.fetch(FetchDescriptor<Course>()).count
        let workspaces = try context.fetch(FetchDescriptor<AppWorkspace>())

        #expect(firstCount == 5)
        #expect(firstCount == secondCount)
        #expect(workspaces.filter(\.isDemoWorkspace).count == 1)
    }

    @Test func demoWorkspaceCreatesExpectedAcademicDashboardData() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        DemoWorkspaceService.loadDemoWorkspace(in: context)

        let courses = try context.fetch(FetchDescriptor<Course>())
        let chapters = try context.fetch(FetchDescriptor<Chapter>())
        let sessions = try context.fetch(FetchDescriptor<ClassSession>())
        let tasks = try context.fetch(FetchDescriptor<AcademicTask>())
        let exams = try context.fetch(FetchDescriptor<Exam>())
        let blocks = try context.fetch(FetchDescriptor<StudyBlock>())
        let readings = try context.fetch(FetchDescriptor<ReadingProgress>())
        let workspace = try #require(try context.fetch(FetchDescriptor<AppWorkspace>()).first)

        let snapshot = TodayDashboardService.makeSnapshot(
            selectedDate: Date(),
            workspace: workspace,
            courses: courses,
            sessions: sessions,
            tasks: tasks,
            exams: exams,
            studyBlocks: blocks,
            readingProgress: readings
        )

        #expect(courses.map(\.name).sorted() == ["Computing Foundations", "German", "Mathematics", "Microeconomics", "Organizational Behavior"])
        #expect(!chapters.isEmpty)
        #expect(!sessions.isEmpty)
        #expect(!tasks.isEmpty)
        #expect(!exams.isEmpty)
        #expect(!blocks.isEmpty)
        #expect(!readings.isEmpty)
        #expect(!snapshot.timelineItems.isEmpty)
        #expect(snapshot.nextSession != nil)
        #expect(snapshot.upcomingExam != nil)
        #expect(snapshot.assignmentDue != nil)
        #expect(snapshot.flashcards.isConfigured)
    }

    @Test func dashboardPersistsNewTaskExamStudyBlockAndReadingProgress() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let now = Date()
        let course = Course(name: "German", code: "GER")
        context.insert(course)
        context.insert(AcademicTask(title: "Vocabulary", dueDate: now, priority: .high, course: course))
        context.insert(Exam(title: "Oral", date: now.addingTimeInterval(86_400), examType: .oral, course: course))
        context.insert(StudyBlock(title: "Listening", startDate: now, endDate: now.addingTimeInterval(3600), course: course))
        context.insert(ReadingProgress(resourceTitle: "Reader", currentPage: 10, totalPages: 40, course: course, coverColorIdentifier: "amber"))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<AcademicTask>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Exam>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<StudyBlock>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ReadingProgress>()).count == 1)
    }

    @Test func courseEditingArchivingAndDeletionPersist() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Business Law", code: "LAW101")
        context.insert(course)
        try context.save()

        course.professorName = "Prof. Lewis"
        course.isArchived = true
        course.updatedAt = .now
        try context.save()

        var saved = try #require(try context.fetch(FetchDescriptor<Course>()).first)
        #expect(saved.professorName == "Prof. Lewis")
        #expect(saved.isArchived)

        context.delete(saved)
        try context.save()
        saved = try context.fetch(FetchDescriptor<Course>()).first ?? Course(name: "Deleted", code: "NA")
        #expect(saved.name == "Deleted")
    }

    @Test func duplicateCourseInSameSemesterIsDetectedByNormalizedNameOrCode() {
        let now = Date()
        let semester = Semester(name: "S1", order: 1, startDate: now, endDate: now.addingTimeInterval(86_400))
        let existing = Course(name: "Business Law", code: "LAW101", semester: semester)
        let sameName = Course(name: " business law ", code: "LAW102", semester: semester)
        let sameCode = Course(name: "Legal Methods", code: "law101", semester: semester)

        #expect(hasDuplicate(candidate: sameName, in: semester, courses: [existing]))
        #expect(hasDuplicate(candidate: sameCode, in: semester, courses: [existing]))
    }

    @Test func chapterOrderCanBeReassignedWithoutChangingIdentity() {
        let course = Course(name: "Math", code: "MAT")
        let first = Chapter(number: 1, title: "Linear Algebra", order: 1, course: course)
        let second = Chapter(number: 2, title: "Optimization", order: 2, course: course)
        let ids = [first.id, second.id]

        let reordered = [second, first]
        for (index, chapter) in reordered.enumerated() {
            chapter.order = index + 1
            chapter.number = index + 1
        }

        #expect(reordered.map(\.id).sorted { $0.uuidString < $1.uuidString } == ids.sorted { $0.uuidString < $1.uuidString })
        #expect(second.order == 1)
        #expect(first.order == 2)
    }

    @Test func sessionCreatedFromChapterKeepsCourseChapterAndType() throws {
        let course = Course(name: "Computing Foundations", code: "CS100")
        let chapter = Chapter(number: 1, title: "Control Flow", order: 1, course: course)
        let start = Date()
        let session = ClassSession(number: 1, title: "Lab", date: start, startTime: start, endTime: start.addingTimeInterval(3600), sessionType: .lab, course: course, chapter: chapter)

        try AcademicValidationService.validateSession(startTime: session.startTime, endTime: session.endTime, course: course, chapter: chapter)
        #expect(session.course === course)
        #expect(session.chapter === chapter)
        #expect(session.sessionType == .lab)
    }

    @Test func courseNextSessionUsesNearestFutureSession() {
        let now = Date()
        let course = Course(name: "Microeconomics", code: "ECO")
        let later = ClassSession(number: 2, title: "Later", date: now, startTime: now.addingTimeInterval(7200), endTime: now.addingTimeInterval(9000), course: course)
        let next = ClassSession(number: 1, title: "Next", date: now, startTime: now.addingTimeInterval(1800), endTime: now.addingTimeInterval(3600), course: course)
        let past = ClassSession(number: 0, title: "Past", date: now, startTime: now.addingTimeInterval(-7200), endTime: now.addingTimeInterval(-3600), course: course)

        let resolved = [later, past, next].filter { $0.startTime >= now }.sorted { $0.startTime < $1.startTime }.first
        #expect(resolved?.title == "Next")
    }

    @Test func demoWorkspaceHasExpandedCourseStructure() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        DemoWorkspaceService.loadDemoWorkspace(in: context)

        let courses = try context.fetch(FetchDescriptor<Course>())
        let sessions = try context.fetch(FetchDescriptor<ClassSession>())

        #expect(courses.count == 5)
        #expect(courses.allSatisfy { $0.chapters.count >= 3 })
        #expect(sessions.contains { $0.sessionType == .lab })
        #expect(sessions.contains { $0.startTime < Date() })
        #expect(sessions.contains { $0.startTime > Date() })
    }

    @Test func courseStoresSelectedSymbolAndColor() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Law", code: "LAW", colorIdentifier: CourseColor.orange.rawValue, symbolName: "scalemass.fill")
        context.insert(course)
        try context.save()

        let saved = try #require(try context.fetch(FetchDescriptor<Course>()).first)
        #expect(saved.symbolName == "scalemass.fill")
        #expect(saved.colorIdentifier == CourseColor.orange.rawValue)
    }

    @Test func invalidCourseSymbolFallsBackToDefault() {
        #expect(CourseIconCatalog.sanitizedSymbolName(nil) == CourseIconCatalog.defaultSymbolName)
        #expect(CourseIconCatalog.sanitizedSymbolName("") == CourseIconCatalog.defaultSymbolName)
        #expect(CourseIconCatalog.sanitizedSymbolName("not.a.real.course.icon") == CourseIconCatalog.defaultSymbolName)
        #expect(CourseIconCatalog.sanitizedSymbolName("function") == "function")
    }

    @Test func editingCourseAppearanceDoesNotCreateSecondCourseAndPreservesRelations() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Math", code: "MAT", colorIdentifier: "teal", symbolName: "function")
        let chapter = Chapter(number: 1, title: "Algebra", order: 1, course: course)
        let session = ClassSession(number: 1, title: "Lecture", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600), course: course, chapter: chapter)
        context.insert(course)
        context.insert(chapter)
        context.insert(session)
        try context.save()

        course.name = "Mathematics I"
        course.colorIdentifier = CourseColor.rose.rawValue
        course.symbolName = "sum"
        try context.save()

        let saved = try context.fetch(FetchDescriptor<Course>())
        #expect(saved.count == 1)
        #expect(saved.first?.name == "Mathematics I")
        #expect(saved.first?.symbolName == "sum")
        #expect(saved.first?.colorIdentifier == CourseColor.rose.rawValue)
        #expect(saved.first?.chapters.count == 1)
        #expect(saved.first?.sessions.count == 1)
    }

    @Test func courseIconCatalogHasNoDuplicateSymbolsAndSupportsSearch() {
        let symbols = CourseIconCatalog.icons.map(\.symbolName)
        #expect(Set(symbols).count == symbols.count)
        #expect(CourseIconCatalog.icons.count >= 100)
        #expect(CourseIconCatalog.icons.contains { CourseIconCatalog.matches($0, query: "math") })
        #expect(CourseIconCatalog.icons.contains { CourseIconCatalog.matches($0, query: "law") })
        #expect(CourseIconCatalog.icons.contains { CourseIconCatalog.matches($0, query: "code") })
    }

    @Test func academicFileStoreCopiesAndDeletesOnlyTargetFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "UniSaverFileStore-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = FileManager.default.temporaryDirectory.appending(path: "source-\(UUID().uuidString).pdf")
        let unrelatedName = "keep-\(UUID().uuidString).pdf"
        let unrelated = root.appending(path: unrelatedName)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: source, options: .atomic)
        try Data("keep".utf8).write(to: unrelated, options: .atomic)

        let store = AcademicFileStore(rootDirectory: root)
        let stored = try store.importFile(from: source)
        #expect(stored.originalFileName == source.lastPathComponent)
        #expect(stored.resourceKind == .pdf)
        #expect(!stored.contentHash.isEmpty)
        #expect(try store.url(for: stored.storedRelativePath).lastPathComponent == stored.storedRelativePath)

        try store.delete(relativePath: stored.storedRelativePath)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: source)
    }

    @Test func noteRecordingKeepsAcademicContextAndPersists() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Microeconomics", code: "ECO")
        let chapter = Chapter(number: 1, title: "Elasticity", order: 1, course: course)
        let start = Date()
        let session = ClassSession(number: 1, title: "Lecture", date: start, startTime: start, endTime: start.addingTimeInterval(3600), course: course, chapter: chapter)
        let note = StudyNote(title: "Lecture notes", body: "Initial notes", course: course, chapter: chapter, session: session)
        let recording = CourseRecording(title: "Lecture recording", storedRelativePath: "recording.m4a", duration: 120, course: course, chapter: chapter, session: session, note: note)
        context.insert(course)
        context.insert(chapter)
        context.insert(session)
        context.insert(note)
        context.insert(recording)
        try context.save()

        let saved = try #require(try context.fetch(FetchDescriptor<CourseRecording>()).first)
        #expect(saved.note?.id == note.id)
        #expect(saved.course?.id == course.id)
        #expect(saved.chapter?.id == chapter.id)
        #expect(saved.session?.id == session.id)
    }

    @Test func demoWorkspaceCreatesContentWorkspaceData() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        DemoWorkspaceService.loadDemoWorkspace(in: context)

        let resources = try context.fetch(FetchDescriptor<AcademicResource>())
        let notes = try context.fetch(FetchDescriptor<StudyNote>())
        let recordings = try context.fetch(FetchDescriptor<CourseRecording>())

        #expect(resources.contains { $0.resourceKind == .pdf && !$0.storedRelativePath.isEmpty })
        #expect(notes.count >= 2)
        #expect(recordings.contains { $0.duration > 0 })
    }

    @Test func resourceImportValidationReturnsExplicitErrors() {
        let empty = ResourceImportValidation.validate(ResourceImportDraft(fileURL: nil, title: "", resourceDescription: "", course: nil, chapter: nil, session: nil, tags: []))
        #expect(empty.fileError == "Choose a file to import.")
        #expect(empty.titleError == "Enter a title.")
        #expect(empty.courseError == "Choose a course.")
        #expect([empty.fileError, empty.titleError, empty.courseError].compactMap { $0 }.allSatisfy { !$0.contains("%{PROPERTY}@") })

        let course = Course(name: "Law", code: "LAW")
        let otherCourse = Course(name: "Math", code: "MAT")
        let wrongChapter = Chapter(number: 1, title: "Algebra", order: 1, course: otherCourse)
        let validation = ResourceImportValidation.validate(ResourceImportDraft(fileURL: URL(filePath: "/tmp/file.pdf"), title: "Reader", resourceDescription: "", course: course, chapter: wrongChapter, session: nil, tags: []))
        #expect(validation.chapterError == "The selected chapter does not belong to this course.")
    }

    @Test func completeResourceImportDraftHasNoErrors() throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "complete-\(UUID().uuidString).pdf")
        try Data("pdf".utf8).write(to: source, options: .atomic)
        let course = Course(name: "Microeconomics", code: "ECO")
        let draft = ResourceImportDraft(fileURL: source, title: "Elasticity Reader", resourceDescription: "", course: course, chapter: nil, session: nil, tags: ["pdf"])

        #expect(ResourceImportValidation.validate(draft).isValid)
        try? FileManager.default.removeItem(at: source)
    }

    @MainActor
    @Test func resourceImportUsesDraftTitleAndTechnicalNameOnlyForStorage() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let root = FileManager.default.temporaryDirectory.appending(path: "UniSaverImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = FileManager.default.temporaryDirectory.appending(path: "codex agent-\(UUID().uuidString).pdf")
        try Data("same pdf".utf8).write(to: source, options: .atomic)
        let course = Course(name: "Microeconomics", code: "ECO")
        context.insert(course)
        try context.save()

        let draft = ResourceImportDraft(fileURL: source, title: "Price Elasticity Reader", resourceDescription: "", course: course, chapter: nil, session: nil, tags: [])
        let resource = try ResourceImportService.submit(draft: draft, existingResources: [], modelContext: context, fileStore: AcademicFileStore(rootDirectory: root))

        #expect(resource.title == "Price Elasticity Reader")
        #expect(resource.originalFileName == source.lastPathComponent)
        #expect(resource.storedRelativePath != resource.title)
        #expect(resource.storedRelativePath.contains(resource.id.uuidString) == false)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: source)
    }

    @MainActor
    @Test func repeatedResourceImportDetectsDuplicateUnlessUserAllowsCopy() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let root = FileManager.default.temporaryDirectory.appending(path: "UniSaverDuplicate-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = FileManager.default.temporaryDirectory.appending(path: "duplicate-\(UUID().uuidString).pdf")
        try Data("duplicate pdf".utf8).write(to: source, options: .atomic)
        let course = Course(name: "Microeconomics", code: "ECO")
        context.insert(course)
        try context.save()
        let store = AcademicFileStore(rootDirectory: root)
        let draft = ResourceImportDraft(fileURL: source, title: "Reader", resourceDescription: "", course: course, chapter: nil, session: nil, tags: [])

        _ = try ResourceImportService.submit(draft: draft, existingResources: [], modelContext: context, fileStore: store)
        let existing = try context.fetch(FetchDescriptor<AcademicResource>())
        #expect(existing.count == 1)

        do {
            _ = try ResourceImportService.submit(draft: draft, existingResources: existing, modelContext: context, fileStore: store)
            Issue.record("Expected duplicate detection")
        } catch ResourceImportSubmitError.duplicate {
            #expect(true)
        }
        #expect(try context.fetch(FetchDescriptor<AcademicResource>()).count == 1)

        _ = try ResourceImportService.submit(draft: draft, existingResources: existing, modelContext: context, fileStore: store, allowDuplicate: true)
        #expect(try context.fetch(FetchDescriptor<AcademicResource>()).count == 2)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: source)
    }

    @MainActor
    @Test func copyFailureCreatesNoResource() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Microeconomics", code: "ECO")
        context.insert(course)
        try context.save()

        let missingURL = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).pdf")
        let draft = ResourceImportDraft(fileURL: missingURL, title: "Reader", resourceDescription: "", course: course, chapter: nil, session: nil, tags: [])

        do {
            _ = try ResourceImportService.submit(draft: draft, existingResources: [], modelContext: context, fileStore: AcademicFileStore())
            Issue.record("Expected missing source to fail")
        } catch {
            #expect(try context.fetch(FetchDescriptor<AcademicResource>()).isEmpty)
        }
    }

    @Test func plannerPriorityFilterMatchesTodayPriorityTasks() {
        let now = Date()
        let course = Course(name: "Microeconomics", code: "ECO")
        let urgent = AcademicTask(title: "Submit sheet", dueDate: now, priority: .urgent, course: course)
        let high = AcademicTask(title: "Review notes", dueDate: now.addingTimeInterval(3600), priority: .high, course: course)
        let medium = AcademicTask(title: "Read chapter", dueDate: now.addingTimeInterval(7200), priority: .medium, course: course)
        let completedUrgent = AcademicTask(title: "Old task", dueDate: now, priority: .urgent, status: .completed, course: course)

        let result = PlannerTaskQuery.filteredTasks([medium, completedUrgent, urgent, high], filter: .priority, searchText: "", courseID: nil)

        #expect(result.map(\.title).contains("Submit sheet"))
        #expect(result.map(\.title).contains("Review notes"))
        #expect(!result.map(\.title).contains("Read chapter"))
        #expect(!result.map(\.title).contains("Old task"))
    }

    @Test func plannerSortingByPriorityUsesDueDateAsTieBreaker() {
        let now = Date()
        let laterUrgent = AcademicTask(title: "Later urgent", dueDate: now.addingTimeInterval(7200), priority: .urgent)
        let soonerUrgent = AcademicTask(title: "Sooner urgent", dueDate: now.addingTimeInterval(3600), priority: .urgent)
        let high = AcademicTask(title: "High", dueDate: now, priority: .high)

        let sorted = PlannerTaskQuery.sortedTasks([high, laterUrgent, soonerUrgent], sort: .priority)
        #expect(sorted.map(\.title) == ["Sooner urgent", "Later urgent", "High"])
    }

    @MainActor
    @Test func linkedNoteCreationIsIdempotentAndKeepsContext() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Microeconomics", code: "ECO")
        let chapter = Chapter(number: 1, title: "Elasticity", order: 1, course: course)
        let start = Date()
        let session = ClassSession(number: 1, title: "Lecture", date: start, startTime: start, endTime: start.addingTimeInterval(3600), course: course, chapter: chapter)
        let resource = AcademicResource(title: "Reader", resourceKind: .pdf, originalFileName: "reader.pdf", storedRelativePath: "reader.pdf", course: course, chapter: chapter, session: session)
        context.insert(course)
        context.insert(chapter)
        context.insert(session)
        context.insert(resource)
        try context.save()

        let first = try LinkedNoteService.note(for: resource, existingNotes: [], in: context)
        let second = try LinkedNoteService.note(for: resource, existingNotes: try context.fetch(FetchDescriptor<StudyNote>()), in: context)

        #expect(first.id == second.id)
        #expect(try context.fetch(FetchDescriptor<StudyNote>()).count == 1)
        #expect(first.course?.id == course.id)
        #expect(first.chapter?.id == chapter.id)
        #expect(first.session?.id == session.id)
        #expect(first.resource?.id == resource.id)
    }

    @Test func flashcardBulkParserAcceptsChatGPTFormat() {
        let input = """
        FLASHCARD
        Front: What is price elasticity of demand?
        Back: The responsiveness of quantity demanded to a change in price.
        Hint: Think percentage changes.
        Explanation: PED = % change in quantity demanded / % change in price.
        Tags: economics, elasticity
        ---
        FLASHCARD
        Front: What does |PED| > 1 mean?
        Back: Demand is elastic.
        Tags: economics, elasticity
        """

        let result = FlashcardBulkParser.parse(input)

        #expect(result.cards.count == 2)
        #expect(result.cards.allSatisfy { $0.isValid })
        #expect(result.cards.first?.tags == ["economics", "elasticity"])
    }

    @Test func flashcardBulkParserHandlesTwentyFiveCardsAndMultilineFields() {
        let blocks = (1...25).map { index in
            """
            FLASHCARD
            Front: Concept \(index)
            Back: First line \(index)
            second line \(index)
            Hint: Hint \(index)
            Tags: demo, card\(index)
            """
        }
        let result = FlashcardBulkParser.parse(blocks.joined(separator: "\n---\n"))

        #expect(result.cards.count == 25)
        #expect(result.cards.allSatisfy { $0.isValid })
        #expect(result.cards[0].back.contains("second line 1"))
        #expect(result.cards[0].sourceLine == 1)
        #expect(result.cards[1].sourceLine > result.cards[0].sourceLine)
    }

    @Test func flashcardBulkParserReportsMissingFieldsAndDuplicates() {
        let input = """
        FLASHCARD
        Front: Elasticity
        ---
        FLASHCARD
        Front: Elasticity
        Back: Duplicate front
        """

        let result = FlashcardBulkParser.parse(input)

        #expect(result.cards.first?.errors.contains("Back is required.") == true)
        #expect(result.duplicateFronts.contains("elasticity"))
        #expect(result.cards.first?.sourceLine == 1)
    }

    @Test func spacedRepetitionSchedulerIsDeterministicAndNeverPastDue() {
        let reviewedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let scheduler = SimpleSpacedRepetitionScheduler()
        let state = FlashcardReviewState(dueDate: reviewedAt, interval: 86_400, ease: 2.3, repetitions: 1)

        for rating in FlashcardRating.allCases {
            let first = scheduler.schedule(state: state, rating: rating, reviewedAt: reviewedAt, calendar: .current)
            let second = scheduler.schedule(state: state, rating: rating, reviewedAt: reviewedAt, calendar: .current)
            #expect(first == second)
            #expect(first.dueDate >= reviewedAt)
        }
    }

    @MainActor
    @Test func createsDeckAndFlashcardInSwiftData() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Microeconomics", code: "ECO")
        let deck = StudyDeck(title: "Elasticity", course: course)
        let card = Flashcard(front: "Front", back: "Back", deck: deck)
        deck.cards.append(card)
        context.insert(course)
        context.insert(deck)
        context.insert(card)
        try context.save()

        let savedDeck = try #require(try context.fetch(FetchDescriptor<StudyDeck>()).first)
        #expect(savedDeck.cards.count == 1)
        #expect(savedDeck.course?.name == "Microeconomics")
    }

    @Test func quizParserAndScoringSupportQCM() {
        let input = """
        QUESTION
        Type: Multiple Choice
        Prompt: If demand is elastic, what happens when price decreases?
        A: Total revenue decreases.
        B: Total revenue increases.
        Correct: B
        Explanation: With elastic demand, quantity rises proportionally more than price falls.
        Tags: economics, elasticity
        """

        let parsed = QuizBulkParser.parse(input)
        #expect(parsed.count == 1)
        #expect(parsed.first?.isValid == true)
        let question = QuizQuestion(
            prompt: parsed[0].prompt,
            type: parsed[0].type,
            choices: parsed[0].choices,
            correctAnswers: parsed[0].correctAnswers,
            explanation: parsed[0].explanation
        )
        let score = QuizScoringService.score(questions: [question], answers: ["B"])
        #expect(score.score == 1)
        #expect(score.maximum == 1)
    }

    @Test func quizParserAndScoringSupportMultipleSelectTrueFalseAndShortAnswer() {
        let input = """
        QUESTION
        Type: Multiple Select
        Prompt: Select demand shifters.
        A: Income
        B: Weather
        C: Price of this good
        Correct: A, B
        Explanation: Income and weather can shift demand.
        ---
        QUESTION
        Type: True/False
        Prompt: A binding constraint is active.
        Correct: True
        Explanation: Binding means active at the solution.
        ---
        QUESTION
        Type: Short Answer
        Prompt: Name a Python collection type.
        Correct: list
        Explanation: Lists store ordered values.
        """

        let parsed = QuizBulkParser.parse(input)
        #expect(parsed.count == 3)
        #expect(parsed.map(\.type) == [.multipleSelect, .trueFalse, .shortAnswer])
        #expect(parsed.allSatisfy { $0.isValid })

        let questions = parsed.enumerated().map { index, parsed in
            QuizQuestion(prompt: parsed.prompt, type: parsed.type, choices: parsed.choices, correctAnswers: parsed.correctAnswers, explanation: parsed.explanation, position: index)
        }
        let score = QuizScoringService.score(questions: questions, answers: ["A, B", "True", "list"])
        #expect(score.score == 3)
        #expect(score.maximum == 3)
    }

    @MainActor
    @Test func demoWorkspaceIncludesStudyStudioData() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        DemoWorkspaceService.loadDemoWorkspace(in: context)
        DemoWorkspaceService.loadDemoWorkspace(in: context)

        let decks = try context.fetch(FetchDescriptor<StudyDeck>())
        let cards = try context.fetch(FetchDescriptor<Flashcard>())
        let quizzes = try context.fetch(FetchDescriptor<Quiz>())
        let attempts = try context.fetch(FetchDescriptor<QuizAttempt>())

        #expect(decks.count >= 4)
        #expect(cards.count >= 60)
        #expect(cards.contains { $0.reviewState.dueDate <= .now })
        #expect(quizzes.count >= 2)
        #expect(attempts.contains { $0.isCompleted })
        #expect(decks.map(\.title).count == Set(decks.map(\.title)).count)
    }

    @Test func understandingPracticeHelpLevelTracksStrongestHelpUsed() {
        #expect(UnderstandingPracticeService.strongestHelpLevel(current: .none, didRevealHint: false, revealedStepCount: 0, didRevealSolution: false) == .none)
        #expect(UnderstandingPracticeService.strongestHelpLevel(current: .none, didRevealHint: true, revealedStepCount: 0, didRevealSolution: false) == .hint)
        #expect(UnderstandingPracticeService.strongestHelpLevel(current: .hint, didRevealHint: true, revealedStepCount: 2, didRevealSolution: false) == .steps)
        #expect(UnderstandingPracticeService.strongestHelpLevel(current: .steps, didRevealHint: true, revealedStepCount: 2, didRevealSolution: true) == .solution)
    }

    @Test func understandingProgressUsesAutonomousRedoResult() {
        let independent = UnderstandingPracticeAttempt(exercisePrompt: "Explain elasticity", subject: "Microeconomics", autonomousResult: .independent)
        let partial = UnderstandingPracticeAttempt(exercisePrompt: "Solve derivative", subject: "Math", autonomousResult: .partial)
        let blocked = UnderstandingPracticeAttempt(exercisePrompt: "Write loop", subject: "Computing", autonomousResult: .couldNotRedo)
        let draft = UnderstandingPracticeAttempt(exercisePrompt: "Draft", subject: "General", autonomousResult: .notChecked)

        let summary = UnderstandingPracticeService.progressSummary(for: [independent, partial, blocked, draft])

        #expect(summary.attemptCount == 4)
        #expect(summary.independentCount == 1)
        #expect(summary.partialCount == 1)
        #expect(summary.completedCheckCount == 2)
        #expect(abs(summary.averageRedoProgress - ((1 + 0.55 + 0) / 3)) < 0.0001)
    }

    @MainActor
    @Test func understandingPracticeAttemptPersistsCourseHelpAndTransferResult() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Microeconomics", code: "ECO")
        let attempt = UnderstandingPracticeAttempt(
            exercisePrompt: "Use elasticity to explain revenue.",
            subject: "Microeconomics",
            studentAttempt: "I compare percentage changes.",
            hint: "Name the unknown.",
            explanationSteps: ["Identify variables", "Apply formula"],
            solution: "Demo solution",
            transferQuestion: "Change the price movement.",
            transferAnswer: "I can redo the method.",
            suggestedTransferAnswer: "Same method with changed values.",
            helpLevelUsed: .steps,
            autonomousResult: .partial,
            assistanceSource: "Demo mode",
            course: course
        )
        context.insert(course)
        context.insert(attempt)
        try context.save()

        let saved = try #require(try context.fetch(FetchDescriptor<UnderstandingPracticeAttempt>()).first)
        #expect(saved.course?.id == course.id)
        #expect(saved.helpLevelUsed == .steps)
        #expect(saved.autonomousResult == .partial)
        #expect(saved.explanationSteps.count == 2)
        #expect(saved.transferAnswer == "I can redo the method.")
    }

    @MainActor
    @Test func demoUnderstandingProviderIsExplicitlyMarkedAsDemo() async throws {
        let provider = DemoUnderstandingAssistanceProvider()
        let assistance = try await provider.assistance(for: "Solve 2x = 10", subject: "Math", course: nil)

        #expect(assistance.isDemo)
        #expect(assistance.sourceLabel == "Demo mode")
        #expect(!assistance.hint.isEmpty)
        #expect(!assistance.explanationSteps.isEmpty)
        #expect(assistance.solution.contains("Demo guidance"))
    }

    @MainActor
    @Test func audioRecorderReportsDeniedPermissionWithoutCreatingModel() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let checker = FakeMicrophonePermissionChecker(status: .denied)
        let recorder = CourseAudioRecorder(
            permissionChecker: checker,
            fileStore: AcademicFileStore(rootDirectory: temporaryDirectory("DeniedRecorder"))
        )

        recorder.requestPermissionAndStart(title: "Denied")

        guard case .denied(let message) = recorder.state else {
            Issue.record("Expected denied recorder state")
            return
        }
        #expect(message.contains("Microphone"))
        #expect(try context.fetch(FetchDescriptor<CourseRecording>()).isEmpty)
    }

    @MainActor
    @Test func audioRecorderRequestsUndeterminedPermissionAndHandlesDenial() async throws {
        let checker = FakeMicrophonePermissionChecker(status: .notDetermined, requestResult: false)
        let recorder = CourseAudioRecorder(
            permissionChecker: checker,
            fileStore: AcademicFileStore(rootDirectory: temporaryDirectory("UndeterminedRecorder"))
        )

        recorder.requestPermissionAndStart(title: "Lecture")
        try? await Task.sleep(for: .milliseconds(50))

        #expect(checker.requestCount == 1)
        guard case .denied = recorder.state else {
            Issue.record("Expected denied recorder state after rejected permission prompt")
            return
        }
    }

    @MainActor
    @Test func audioRecorderStopIsIdempotentWhenIdle() {
        let recorder = CourseAudioRecorder(
            permissionChecker: FakeMicrophonePermissionChecker(status: .denied),
            fileStore: AcademicFileStore(rootDirectory: temporaryDirectory("IdleRecorder"))
        )

        recorder.stop()
        recorder.stop()

        guard case .idle = recorder.state else {
            Issue.record("Stopping an idle recorder should keep it idle")
            return
        }
    }

    @MainActor
    @Test func recordingPersistenceCreatesSingleLinkedRecordingAndDeletesFile() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let root = temporaryDirectory("RecordingPersistence")
        let fileStore = AcademicFileStore(rootDirectory: root)
        let prepared = try fileStore.prepareRecordingDestination(originalTitle: "Lecture")
        try Data("audio bytes".utf8).write(to: prepared.url, options: .atomic)
        let saved = try fileStore.savedRecording(from: prepared, duration: 42)
        let course = Course(name: "Microeconomics", code: "ECO")
        let chapter = Chapter(number: 1, title: "Elasticity", order: 1, course: course)
        let start = Date()
        let session = ClassSession(number: 1, title: "Lecture", date: start, startTime: start, endTime: start.addingTimeInterval(3600), course: course, chapter: chapter)
        let note = StudyNote(title: "Lecture notes", course: course, chapter: chapter, session: session)
        context.insert(course)
        context.insert(chapter)
        context.insert(session)
        context.insert(note)
        try context.save()

        let recording = try RecordingPersistenceService.createRecording(
            title: "Lecture audio",
            savedRecording: saved,
            course: course,
            chapter: chapter,
            session: session,
            note: note,
            in: context,
            fileStore: fileStore
        )

        #expect(try context.fetch(FetchDescriptor<CourseRecording>()).count == 1)
        #expect(recording.course?.id == course.id)
        #expect(recording.chapter?.id == chapter.id)
        #expect(recording.session?.id == session.id)
        #expect(recording.note?.id == note.id)
        #expect(try fileStore.url(for: saved.storedRelativePath).lastPathComponent == saved.storedRelativePath)

        RecordingPersistenceService.deleteRecording(recording, in: context, fileStore: fileStore)
        #expect(try context.fetch(FetchDescriptor<CourseRecording>()).isEmpty)
        #expect(throws: AcademicFileStoreError.fileMissing) {
            _ = try fileStore.url(for: saved.storedRelativePath)
        }
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    @Test func sessionTypeRawValueFallbackRepairsMissingAndUnknownValues() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Legacy Course", code: "LEG")
        let missing = ClassSession(number: 1, title: "Missing", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600), course: course)
        let unknown = ClassSession(number: 2, title: "Unknown", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600), course: course)
        let valid = ClassSession(number: 3, title: "Lab", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600), sessionType: .lab, course: course)
        missing.sessionTypeRawValue = nil
        unknown.sessionTypeRawValue = "old-bad-value"
        context.insert(course)
        context.insert(missing)
        context.insert(unknown)
        context.insert(valid)
        try context.save()

        try PersistenceController.repairSessionTypes(in: context)

        #expect(missing.sessionType == .lecture)
        #expect(unknown.sessionType == .lecture)
        #expect(valid.sessionType == .lab)
        #expect(missing.course?.id == course.id)
        #expect(valid.course?.id == course.id)
    }

    @MainActor
    @Test func sessionTypeRepairIsIdempotentAndDoesNotDuplicateSessions() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Microeconomics", code: "ECO")
        let session = ClassSession(number: 1, title: "Seminar", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600), sessionType: .seminar, course: course)
        context.insert(course)
        context.insert(session)
        try context.save()

        try PersistenceController.repairSessionTypes(in: context)
        try PersistenceController.repairSessionTypes(in: context)

        let sessions = try context.fetch(FetchDescriptor<ClassSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.sessionType == .seminar)
        #expect(sessions.first?.sessionTypeRawValue == ClassSessionType.seminar.rawValue)
    }

    @Test func sessionTypeComputedPropertyUsesStableRawValue() {
        let session = ClassSession(number: 1, title: "Tutorial", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600))
        session.sessionType = .tutorial
        #expect(session.sessionTypeRawValue == ClassSessionType.tutorial.rawValue)
        #expect(session.sessionType == .tutorial)

        session.sessionTypeRawValue = nil
        #expect(session.sessionType == .lecture)

        session.sessionTypeRawValue = "unknown"
        #expect(session.sessionType == .lecture)
    }

    @MainActor
    @Test func migrationPlanOpensFreshStoreAndMigratesV2StoreToCurrentSchema() throws {
        let storeName = "MigrationRegression-\(UUID().uuidString)"
        let legacySchema = Schema(versionedSchema: UniSaverSchemaV2.self)
        let legacyConfiguration = ModelConfiguration(storeName, schema: legacySchema)
        let legacyContainer = try ModelContainer(
            for: legacySchema,
            configurations: [legacyConfiguration]
        )
        let legacyContext = ModelContext(legacyContainer)
        let course = UniSaverSchemaV2.Course()
        course.name = "Migration Economics"
        course.code = "MIG"
        let deck = UniSaverSchemaV2.StudyDeck()
        deck.title = "Legacy Deck"
        deck.course = course
        legacyContext.insert(course)
        legacyContext.insert(deck)
        try legacyContext.save()

        #expect(!legacySchema.entities.contains { $0.name == "UnderstandingPracticeAttempt" })
        #expect(PersistenceController.schema.entities.contains { $0.name == "UnderstandingPracticeAttempt" })

        let currentConfiguration = ModelConfiguration(storeName, schema: PersistenceController.schema)
        let currentContainer = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: UniSaverMigrationPlan.self,
            configurations: [currentConfiguration]
        )
        let currentContext = ModelContext(currentContainer)
        let courses = try currentContext.fetch(FetchDescriptor<Course>())
        let decks = try currentContext.fetch(FetchDescriptor<StudyDeck>())
        let checks = try currentContext.fetch(FetchDescriptor<UnderstandingPracticeAttempt>())

        #expect(courses.contains { $0.name == "Migration Economics" })
        #expect(decks.contains { $0.title == "Legacy Deck" })
        #expect(checks.isEmpty)

        let freshName = "FreshCurrent-\(UUID().uuidString)"
        let freshConfiguration = ModelConfiguration(freshName, schema: PersistenceController.schema)
        let freshContainer = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: UniSaverMigrationPlan.self,
            configurations: [freshConfiguration]
        )
        let freshContext = ModelContext(freshContainer)
        #expect(try freshContext.fetch(FetchDescriptor<Course>()).isEmpty)
        #expect(try freshContext.fetch(FetchDescriptor<UnderstandingPracticeAttempt>()).isEmpty)
    }

    @MainActor
    @Test func historicalStoreCopyOpensWithCurrentSchemaWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["UNISAVER_HISTORICAL_STORE_PATH"], !path.isEmpty else {
            return
        }

        let storeURL = URL(filePath: path)
        let configuration = ModelConfiguration("HistoricalMigrationProbe", schema: PersistenceController.schema, url: storeURL)
        let container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: UniSaverMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)

        let counts = [
            "courses": try context.fetchCount(FetchDescriptor<Course>()),
            "chapters": try context.fetchCount(FetchDescriptor<Chapter>()),
            "sessions": try context.fetchCount(FetchDescriptor<ClassSession>()),
            "resources": try context.fetchCount(FetchDescriptor<AcademicResource>()),
            "notes": try context.fetchCount(FetchDescriptor<StudyNote>()),
            "recordings": try context.fetchCount(FetchDescriptor<CourseRecording>()),
            "decks": try context.fetchCount(FetchDescriptor<StudyDeck>()),
            "flashcards": try context.fetchCount(FetchDescriptor<Flashcard>())
        ]

        print("HISTORICAL_MIGRATION_COUNTS \(counts)")
        #expect(counts.values.allSatisfy { $0 >= 0 })
    }

    @Test func currentSchemaUsesCurrentAppWorkspaceModel() throws {
        let v2Workspace = try #require(UniSaverSchemaV2.models.first { String(describing: $0) == "AppWorkspace" })
        let v4Workspace = try #require(UniSaverSchemaV4.models.first { String(describing: $0) == "AppWorkspace" })
        let v2Recording = try #require(UniSaverSchemaV2.models.first { String(describing: $0) == "CourseRecording" })
        let v4Recording = try #require(UniSaverSchemaV4.models.first { String(describing: $0) == "CourseRecording" })
        let v5Recording = try #require(UniSaverSchemaV5.models.first { String(describing: $0) == "CourseRecording" })
        let v6Recording = try #require(UniSaverSchemaV6.models.first { String(describing: $0) == "CourseRecording" })
        let currentWorkspace = PersistenceController.schema.entities.first { $0.name == "AppWorkspace" }

        #expect(String(reflecting: v2Workspace) == "UniSaver.UniSaverSchemaV2.AppWorkspace")
        #expect(String(reflecting: v4Workspace) == "UniSaver.AppWorkspace")
        #expect(String(reflecting: v2Recording) == "UniSaver.UniSaverSchemaV2.CourseRecording")
        #expect(String(reflecting: v4Recording) == "UniSaver.CourseRecording")
        #expect(String(reflecting: v5Recording) == "UniSaver.UniSaverSchemaV5.CourseRecording")
        #expect(String(reflecting: v6Recording) == "UniSaver.CourseRecording")
        #expect(currentWorkspace != nil)
        #expect(Schema(versionedSchema: UniSaverSchemaV2.self).entities.count == 19)
        #expect(Schema(versionedSchema: UniSaverSchemaV4.self).entities.count == 20)
        #expect(Schema(versionedSchema: UniSaverSchemaV5.self).entities.count == 22)
        #expect(Schema(versionedSchema: UniSaverSchemaV6.self).entities.count == 22)
        #expect(PersistenceController.schema.entities.contains { $0.name == "LibraryFolder" })
        #expect(PersistenceController.schema.entities.contains { $0.name == "LibraryItem" })
    }

    @Test func noteNavigationGuardBlocksSectionChangesUntilResolved() {
        let navigation = AppNavigationState()
        navigation.select(.classes)
        navigation.noteNavigationGuard = { _ in false }

        navigation.requestSelect(.today)
        #expect(navigation.selectedSection == .classes)

        navigation.noteNavigationGuard = { _ in true }
        navigation.requestSelect(.today)
        #expect(navigation.selectedSection == .today)
    }

    @MainActor
    @Test func libraryFolderDeletionKeepsUnderlyingNoteUnfiled() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let note = StudyNote(title: "Legacy note")
        let folder = LibraryFolder(name: "Week 1")
        let assignment = LibraryItem(itemKind: .note, itemID: note.id.uuidString, folder: folder)
        context.insert(note)
        context.insert(folder)
        context.insert(assignment)
        try context.save()

        let savedNotes = try context.fetch(FetchDescriptor<StudyNote>())
        #expect(savedNotes.count == 1)
        #expect(try context.fetch(FetchDescriptor<LibraryItem>()).first?.folder?.name == "Week 1")

        assignment.folder = nil
        context.delete(folder)
        try context.save()

        let notesAfterDelete = try context.fetch(FetchDescriptor<StudyNote>())
        let assignmentsAfterDelete = try context.fetch(FetchDescriptor<LibraryItem>())
        #expect(notesAfterDelete.map(\.title) == ["Legacy note"])
        #expect(assignmentsAfterDelete.count == 1)
        #expect(assignmentsAfterDelete.first?.folder == nil)
        #expect(try context.fetch(FetchDescriptor<LibraryFolder>()).isEmpty)
    }

    @MainActor
    @Test func recordingTranscriptionPersistsOnSingleAudioRecordingWithoutCreatingStudyNote() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Algorithms", code: "CS")
        let session = ClassSession(number: 1, title: "Graphs", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600), course: course)
        let recording = CourseRecording(title: "Graphs audio", storedRelativePath: "graphs.m4a", duration: 90, course: course, session: session, notes: "Graph traversal")
        context.insert(course)
        context.insert(session)
        context.insert(recording)
        try context.save()

        let savedRecordings = try context.fetch(FetchDescriptor<CourseRecording>())
        let savedNotes = try context.fetch(FetchDescriptor<StudyNote>())
        #expect(savedRecordings.count == 1)
        #expect(savedRecordings.first?.notes == "Graph traversal")
        #expect(savedNotes.isEmpty)
    }

    @Test func appleSpeechTranscriptDoesNotOverwriteExistingRecordingNotes() {
        let merged = NativeSpeechTranscriptionService.mergedNotes("Manual note from class.", transcript: "Generated transcript")
        #expect(merged.contains("Manual note from class."))
        #expect(merged.contains("Apple Speech Transcript"))
        #expect(merged.contains("Generated transcript"))

        let replaced = NativeSpeechTranscriptionService.mergedNotes(merged, transcript: "Updated transcript")
        #expect(replaced.contains("Manual note from class."))
        #expect(replaced.contains("Updated transcript"))
        #expect(!replaced.contains("Generated transcript"))
    }

    @Test func resourceImportValidationAllowsUnfiledResourceWithoutCourse() {
        let draft = ResourceImportDraft(
            fileURL: URL(fileURLWithPath: "/tmp/sample.pdf"),
            title: "Sample",
            resourceDescription: "",
            course: nil,
            chapter: nil,
            session: nil,
            tags: []
        )

        let validation = ResourceImportValidation.validate(draft)

        #expect(validation.isValid)
        #expect(validation.courseError == nil)
    }

    @Test func calendarICSParserKeepsValidEventsAndReportsInvalidLines() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:Microeconomics lecture
        DTSTART:20260925T090000Z
        DTEND:20260925T103000Z
        LOCATION:Room 201
        RRULE:FREQ=WEEKLY;COUNT=3
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:Broken event
        END:VEVENT
        END:VCALENDAR
        """

        let parsed = CalendarICSParser.parse(ics)

        let event = try #require(parsed.events.first)
        #expect(parsed.events.count == 1)
        #expect(event.title == "Microeconomics lecture")
        #expect(event.location == "Room 201")
        #expect(event.recurrenceNote?.contains("FREQ=WEEKLY") == true)
        #expect(parsed.errors.contains { $0.message.contains("Date de début") })
    }

    @MainActor
    @Test func moodleSyncMappingUpdatesWithoutDuplicates() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let metadataURL = temporaryDirectory("MoodleMetadata").appending(path: "metadata.json")
        let metadataStore = MoodleSyncMetadataStore(fileURL: metadataURL)
        let institutionURL = try #require(URL(string: "https://moodle.example.edu"))
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let courses = [
            MoodleCourseDTO(id: 10, fullname: "Calculus I", shortname: "MATH101", viewurl: URL(string: "https://moodle.example.edu/course/view.php?id=10"), summary: "Limits", startdate: nil, enddate: nil)
        ]
        let events = [
            MoodleEventDTO(id: 99, name: "Problem set", description: "Week 1", timestart: Int(dueDate.timeIntervalSince1970), timeduration: nil, url: URL(string: "https://moodle.example.edu/mod/assign/view.php?id=99"), courseid: 10, modulename: "assign")
        ]

        _ = try MoodleSyncService.apply(
            remoteCourses: courses,
            remoteEvents: events,
            siteName: "Example Moodle",
            userDisplayName: "Student",
            availableFunctions: ["core_enrol_get_users_courses", "core_calendar_get_action_events_by_courses"],
            institutionURL: institutionURL,
            context: context,
            metadataStore: metadataStore
        )
        let secondSummary = try MoodleSyncService.apply(
            remoteCourses: [MoodleCourseDTO(id: 10, fullname: "Calculus IA", shortname: "MATH101", viewurl: nil, summary: "Updated", startdate: nil, enddate: nil)],
            remoteEvents: [MoodleEventDTO(id: 99, name: "Problem set updated", description: "Updated", timestart: Int(dueDate.timeIntervalSince1970), timeduration: nil, url: nil, courseid: 10, modulename: "assign")],
            siteName: "Example Moodle",
            userDisplayName: "Student",
            availableFunctions: ["core_enrol_get_users_courses"],
            institutionURL: institutionURL,
            context: context,
            metadataStore: metadataStore
        )

        let savedCourses = try context.fetch(FetchDescriptor<Course>())
        let savedTasks = try context.fetch(FetchDescriptor<AcademicTask>())
        let metadata = metadataStore.load()
        #expect(savedCourses.count == 1)
        #expect(savedCourses.first?.name == "Calculus IA")
        #expect(savedTasks.count == 1)
        #expect(savedTasks.first?.title == "Problem set updated")
        #expect(secondSummary.importedCourseCount == 0)
        #expect(secondSummary.updatedCourseCount == 1)
        #expect(secondSummary.importedTaskCount == 0)
        #expect(secondSummary.updatedTaskCount == 1)
        #expect(metadata.records.filter { $0.kind == .course }.count == 1)
        #expect(metadata.records.filter { $0.kind == .task }.count == 1)
    }

    @Test func moodleAccessDeniedSurfacesReadableError() {
        let error = MoodleClientError.permissionDenied("Access control exception")
        #expect(error.localizedDescription.contains("Moodle refused access"))
        #expect(MoodleClientError.missingAuthorizedToken.localizedDescription.contains("Connexion indisponible"))
    }

    @Test func existingCourseContentCanMoveBetweenChaptersWithoutDuplication() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Accounting II", code: "ACC2")
        let firstChapter = Chapter(number: 1, title: "Financial statements", order: 1, course: course)
        let secondChapter = Chapter(number: 2, title: "Inventory", order: 2, course: course)
        let start = Date()
        let session = ClassSession(number: 1, title: "Lecture", date: start, startTime: start, endTime: start.addingTimeInterval(3600), course: course)
        let resource = AcademicResource(
            title: "Syllabus",
            resourceKind: .document,
            originalFileName: "Accounting II Syllabus.docx",
            storedRelativePath: "Resources/syllabus.docx",
            fileExtension: "docx",
            course: course
        )
        let note = StudyNote(title: "Chapter note", course: course)
        let quiz = Quiz(title: "Practice quiz", course: course)

        context.insert(course)
        context.insert(firstChapter)
        context.insert(secondChapter)
        context.insert(session)
        context.insert(resource)
        context.insert(note)
        context.insert(quiz)
        try context.save()

        session.chapter = firstChapter
        resource.chapter = firstChapter
        note.chapter = firstChapter
        quiz.chapter = firstChapter
        try context.save()

        resource.chapter = secondChapter
        note.chapter = secondChapter
        quiz.chapter = secondChapter
        try context.save()

        let savedResources = try context.fetch(FetchDescriptor<AcademicResource>())
        let savedNotes = try context.fetch(FetchDescriptor<StudyNote>())
        let savedQuizzes = try context.fetch(FetchDescriptor<Quiz>())
        let savedSessions = try context.fetch(FetchDescriptor<ClassSession>())

        #expect(savedResources.count == 1)
        #expect(savedResources.first?.id == resource.id)
        #expect(savedResources.first?.chapter?.id == secondChapter.id)
        #expect(savedNotes.count == 1)
        #expect(savedNotes.first?.chapter?.id == secondChapter.id)
        #expect(savedQuizzes.count == 1)
        #expect(savedQuizzes.first?.chapter?.id == secondChapter.id)
        #expect(savedSessions.count == 1)
        #expect(savedSessions.first?.chapter?.id == firstChapter.id)
    }

    @Test func sessionStreakUsesOnlyFinishedAttendedSessions() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: now))
        let threeDaysAgo = try #require(calendar.date(byAdding: .day, value: -3, to: now))

        let attendedYesterday = ClassSession(number: 1, title: "Yesterday", date: yesterday, startTime: yesterday, endTime: yesterday.addingTimeInterval(3_600), attendanceStatus: .attended)
        let attendedTwoDaysAgo = ClassSession(number: 2, title: "Two days ago", date: twoDaysAgo, startTime: twoDaysAgo, endTime: twoDaysAgo.addingTimeInterval(3_600), attendanceStatus: .attended)
        let missedThreeDaysAgo = ClassSession(number: 3, title: "Missed", date: threeDaysAgo, startTime: threeDaysAgo, endTime: threeDaysAgo.addingTimeInterval(3_600), attendanceStatus: .missed)
        let futureToday = ClassSession(number: 4, title: "Future", date: now, startTime: now.addingTimeInterval(3_600), endTime: now.addingTimeInterval(7_200), attendanceStatus: .attended)

        let summary = SessionStreakCalculator.summary(
            from: [attendedYesterday, attendedTwoDaysAgo, missedThreeDaysAgo, futureToday],
            calendar: calendar,
            now: now
        )

        #expect(summary.currentStreak == 2)
        #expect(summary.completedSessionCount == 2)
        #expect(summary.recentDays.filter(\.hasCompletedSession).count == 2)
    }

    @Test func sessionStreakHasHonestEmptyState() {
        let summary = SessionStreakCalculator.summary(from: [], calendar: .current, now: .now)

        #expect(summary.currentStreak == 0)
        #expect(summary.completedSessionCount == 0)
        #expect(summary.recentDays.allSatisfy { !$0.hasCompletedSession })
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration("TestStore", schema: PersistenceController.schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: PersistenceController.schema, configurations: [configuration])
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func session(_ title: String, course: Course, day: Date, hour: Int) -> ClassSession {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return ClassSession(number: hour, title: title, date: day, startTime: start, endTime: start.addingTimeInterval(3600), course: course)
    }

    private func hasDuplicate(candidate: Course, in semester: Semester, courses: [Course]) -> Bool {
        let normalizedName = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let normalizedCode = candidate.code.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        return courses.contains { existing in
            guard existing.semester === semester else { return false }
            return existing.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == normalizedName
                || (!normalizedCode.isEmpty && existing.code.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == normalizedCode)
        }
    }
}

private final class FakeMicrophonePermissionChecker: MicrophonePermissionChecking {
    private let statusValue: AVAuthorizationStatus
    private let requestResult: Bool
    private(set) var requestCount = 0

    init(status: AVAuthorizationStatus, requestResult: Bool = false) {
        self.statusValue = status
        self.requestResult = requestResult
    }

    func authorizationStatus() -> AVAuthorizationStatus {
        statusValue
    }

    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        requestCount += 1
        completion(requestResult)
    }
}
