import SwiftData
import SwiftUI

struct PlaceholderFeatureView: View {
    let section: AppSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: section.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                        .frame(width: 44, height: 44)
                        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title3.weight(.bold))
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if section == .study {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Future capabilities")
                            .font(.headline)
                        Text("Flashcards, QCM, quizzes, spaced repetition, and error tracking will arrive in a later lot.")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))

                    Button("Back to Classes", systemImage: "books.vertical") {
                        NotificationCenter.default.post(name: .selectAppSection, object: AppSection.classes)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Back to Today", systemImage: "sun.max") {
                        NotificationCenter.default.post(name: .selectAppSection, object: AppSection.today)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .navigationTitle(section.title)
    }

    private var title: String {
        if section == .study {
            return "Study Studio arrives in a later lot"
        }
        return "\(section.title) is planned"
    }

    private var message: String {
        switch section {
        case .planner:
            "Tasks, assignments, exams, calendar planning, and notifications will be built from the dashboard models already in place."
        case .progress:
            "Progress will summarize structural workflow data without inventing academic mastery."
        case .library:
            "Documents, PDF reading, and resource organization arrive in the Documents lot."
        case .study:
            "The dashboard can show demo study counts, but the real study engine is not implemented yet."
        default:
            "This section is reserved for a later lot."
        }
    }
}

struct ProgressDashboardView: View {
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \ClassSession.startTime) private var sessions: [ClassSession]
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \StudyBlock.startDate) private var studyBlocks: [StudyBlock]
    @Query(sort: \FlashcardReviewEvent.reviewedAt, order: .reverse) private var flashcardReviews: [FlashcardReviewEvent]
    @Query(sort: \QuizAttempt.startedAt, order: .reverse) private var quizAttempts: [QuizAttempt]
    @Query(sort: \UnderstandingPracticeAttempt.createdAt, order: .reverse) private var understandingAttempts: [UnderstandingPracticeAttempt]
    @Query(sort: \ExternalLearningActivity.updatedAt, order: .reverse) private var externalActivities: [ExternalLearningActivity]
    @Query(sort: \MathExerciseAttempt.updatedAt, order: .reverse) private var mathAttempts: [MathExerciseAttempt]
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyDeck.updatedAt, order: .reverse) private var decks: [StudyDeck]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                streakSection
                if activeCourses.isEmpty {
                    EmptyStateView(
                        title: "Pas encore de matières",
                        message: "Crée ou importe des cours pour voir les séances, tâches et activités réelles.",
                        systemImage: "chart.line.uptrend.xyaxis",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                        ForEach(activeCourses) { course in
                            ProgressCourseCard(summary: summary(for: course))
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1220, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .navigationTitle(AppSection.progress.title)
    }

    private var activeCourses: [Course] {
        courses.filter { !$0.isArchived }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progression réelle")
                .font(.title.bold())
            Text("Les indicateurs distinguent l’activité faite de la compréhension démontrée. Sans tentative, UniSaver n’affiche pas de maîtrise fictive.")
                .foregroundStyle(.secondary)
        }
    }

    private var meaningfulActivities: [StudyActivityEntry] {
        StudyProgressEngine.activities(
            tasks: tasks,
            studyBlocks: studyBlocks,
            flashcardReviews: flashcardReviews,
            quizAttempts: quizAttempts,
            understandingAttempts: understandingAttempts,
            externalActivities: externalActivities,
            mathAttempts: mathAttempts
        )
    }

    private var streakSummary: StudyStreakSummary {
        StudyProgressEngine.streakSummary(from: meaningfulActivities, calendar: .current, now: .now)
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Série d’étude")
                        .font(.headline)
                    Text("Un jour compte seulement après une action terminée : quiz remis, cartes revues, tâche ou révision terminée.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                streakMetric("\(streakSummary.currentStreak)", "série actuelle")
                streakMetric("\(streakSummary.longestStreak)", "meilleure série")
                streakMetric("\(streakSummary.studyDaysThisWeek)", "jours cette semaine")
                streakMetric("\(meaningfulActivities.count)", "actions terminées")
            }

            if meaningfulActivities.isEmpty {
                Text("Pas encore d’activité qualifiante. Termine une tâche, une révision, un quiz ou une séance de cartes pour démarrer la série.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(streakSummary.recentDays) { day in
                        VStack(spacing: 5) {
                            Circle()
                                .fill(day.hasActivity ? StudyDeskTheme.accentPrimary : StudyDeskTheme.borderSubtle)
                                .frame(width: 14, height: 14)
                            Text(day.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(10)
                .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .deskCard()
    }

    private func streakMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func summary(for course: Course) -> ProgressCourseSummary {
        let courseSessions = sessions.filter { $0.course?.id == course.id }
        let now = Date()
        let courseTasks = tasks.filter { $0.course?.id == course.id }
        let courseQuizAttempts = quizAttempts.filter { $0.quiz?.course?.id == course.id }
        let courseUnderstanding = understandingAttempts.filter { $0.course?.id == course.id }
        let courseExternalActivities = externalActivities.filter { $0.course?.id == course.id }
        let courseReviewEvents = flashcardReviews.filter { $0.card?.deck?.course?.id == course.id }
        let courseStudyBlocks = studyBlocks.filter { $0.course?.id == course.id }
        let courseMathAttempts = mathAttempts.filter { $0.exercise?.course?.id == course.id }
        let courseResources = resources.filter { $0.course?.id == course.id }
        let courseDecks = decks.filter { $0.course?.id == course.id && !$0.isArchived }
        let courseActivities = meaningfulActivities.filter { $0.courseID == course.id }

        return ProgressCourseSummary(
            course: course,
            pastSessions: courseSessions.filter { $0.startTime < now }.count,
            upcomingSessions: courseSessions.filter { $0.startTime >= now }.count,
            completedTasks: courseTasks.filter { $0.status == .completed }.count,
            openTasks: courseTasks.filter { $0.status != .completed && $0.status != .cancelled }.count,
            completedRevisions: courseStudyBlocks.filter { $0.status == .completed }.count,
            upcomingRevisions: courseStudyBlocks.filter { $0.status == .planned && $0.startDate >= now }.count,
            completedReading: courseResources.filter { $0.readingProgress >= 0.98 }.count,
            readingInProgress: courseResources.filter { $0.readingProgress > 0 && $0.readingProgress < 0.98 }.count,
            flashcardReviews: courseReviewEvents.count,
            deckCount: courseDecks.count,
            completedQuizAttempts: courseQuizAttempts.filter(\.isCompleted).count,
            latestQuizScore: latestScore(from: courseQuizAttempts),
            bestQuizScore: bestScore(from: courseQuizAttempts),
            independentUnderstandingChecks: courseUnderstanding.filter { $0.autonomousResult == .independent }.count,
            partialUnderstandingChecks: courseUnderstanding.filter { $0.autonomousResult == .partial }.count,
            externalCompleted: courseExternalActivities.filter { $0.status == .completed }.count,
            externalOpen: courseExternalActivities.filter { $0.status != .completed }.count,
            completedExercises: courseMathAttempts.filter { $0.status == .submitted }.count,
            recentActivities: Array(courseActivities.prefix(4))
        )
    }

    private func latestScore(from attempts: [QuizAttempt]) -> Double? {
        attempts
            .filter { $0.isCompleted && $0.maximumScore > 0 }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
            .first
            .map { $0.score / $0.maximumScore }
    }

    private func bestScore(from attempts: [QuizAttempt]) -> Double? {
        attempts
            .filter { $0.isCompleted && $0.maximumScore > 0 }
            .map { $0.score / $0.maximumScore }
            .max()
    }
}

private struct ProgressCourseSummary: Identifiable {
    let course: Course
    let pastSessions: Int
    let upcomingSessions: Int
    let completedTasks: Int
    let openTasks: Int
    let completedRevisions: Int
    let upcomingRevisions: Int
    let completedReading: Int
    let readingInProgress: Int
    let flashcardReviews: Int
    let deckCount: Int
    let completedQuizAttempts: Int
    let latestQuizScore: Double?
    let bestQuizScore: Double?
    let independentUnderstandingChecks: Int
    let partialUnderstandingChecks: Int
    let externalCompleted: Int
    let externalOpen: Int
    let completedExercises: Int
    let recentActivities: [StudyActivityEntry]

    var id: UUID { course.id }
    var hasDemonstratedUnderstanding: Bool {
        completedQuizAttempts > 0 || independentUnderstandingChecks > 0 || partialUnderstandingChecks > 0 || completedExercises > 0
    }

    var completedWork: Int {
        completedTasks + completedRevisions + completedQuizAttempts + flashcardReviews + externalCompleted + completedExercises + completedReading
    }

    var remainingWork: Int {
        openTasks + upcomingRevisions + max(deckCount - flashcardReviews, 0) + externalOpen + readingInProgress
    }
}

private struct ProgressCourseCard: View {
    let summary: ProgressCourseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(CourseColor.color(for: summary.course.colorIdentifier))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.course.name)
                        .font(.headline)
                        .lineLimit(2)
                    if !summary.course.code.isEmpty {
                        Text(summary.course.code)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 18) {
                stat("\(summary.pastSessions)", "séances passées")
                stat("\(summary.upcomingSessions)", "à venir")
                stat("\(summary.completedTasks)", "tâches finies")
                stat("\(summary.openTasks)", "à faire")
            }

            ProgressMeter(value: progressValue)
            Text("\(summary.completedWork) éléments terminés · \(summary.remainingWork) restants")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Compréhension démontrée")
                    .font(.subheadline.weight(.semibold))
                if summary.hasDemonstratedUnderstanding {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 18) {
                            stat("\(summary.completedQuizAttempts)", "quiz remis")
                            stat("\(summary.independentUnderstandingChecks)", "refaits seuls")
                            stat("\(summary.partialUnderstandingChecks)", "partiels")
                            stat("\(summary.completedExercises)", "exercices remis")
                        }
                        HStack(spacing: 18) {
                            stat(scoreLabel(summary.latestQuizScore), "dernier score")
                            stat(scoreLabel(summary.bestQuizScore), "meilleur score")
                        }
                    }
                } else {
                    Text("Pas encore de données")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 18) {
                stat("\(summary.flashcardReviews)", "révisions cartes")
                stat("\(summary.completedRevisions)", "révisions finies")
                stat("\(summary.externalCompleted)", "activités terminées")
                stat("\(summary.externalOpen)", "liens à faire")
            }

            if !summary.recentActivities.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Activité récente")
                        .font(.subheadline.weight(.semibold))
                    ForEach(summary.recentActivities) { activity in
                        Label(activity.title, systemImage: activity.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 72, alignment: .leading)
    }

    private var progressValue: Double {
        let total = summary.completedWork + summary.remainingWork
        guard total > 0 else { return 0 }
        return Double(summary.completedWork) / Double(total)
    }

    private func scoreLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
}

private struct StudyActivityEntry: Identifiable {
    let id: String
    let date: Date
    let courseID: UUID?
    let title: String
    let symbolName: String
}

private struct StudyStreakSummary {
    let currentStreak: Int
    let longestStreak: Int
    let studyDaysThisWeek: Int
    let recentDays: [StudyDayMarker]
}

private struct StudyDayMarker: Identifiable {
    let id: Date
    let label: String
    let hasActivity: Bool
}

private enum StudyProgressEngine {
    static func activities(
        tasks: [AcademicTask],
        studyBlocks: [StudyBlock],
        flashcardReviews: [FlashcardReviewEvent],
        quizAttempts: [QuizAttempt],
        understandingAttempts: [UnderstandingPracticeAttempt],
        externalActivities: [ExternalLearningActivity],
        mathAttempts: [MathExerciseAttempt]
    ) -> [StudyActivityEntry] {
        let taskEntries = tasks
            .filter { $0.status == .completed }
            .map { StudyActivityEntry(id: "task-\($0.id)", date: $0.updatedAt, courseID: $0.course?.id, title: "Tâche terminée · \($0.title)", symbolName: "checklist") }
        let revisionEntries = studyBlocks
            .filter { $0.status == .completed }
            .map { StudyActivityEntry(id: "revision-\($0.id)", date: $0.updatedAt, courseID: $0.course?.id, title: "Révision terminée · \($0.title)", symbolName: "timer") }
        let flashcardEntries = flashcardReviews.map {
            StudyActivityEntry(id: "flashcard-\($0.id)", date: $0.reviewedAt, courseID: $0.card?.deck?.course?.id, title: "Carte revue · \($0.card?.deck?.title ?? "Deck")", symbolName: "rectangle.stack")
        }
        let quizEntries = quizAttempts
            .filter(\.isCompleted)
            .map { StudyActivityEntry(id: "quiz-\($0.id)", date: $0.completedAt ?? $0.startedAt, courseID: $0.quiz?.course?.id, title: "Quiz remis · \($0.quiz?.title ?? "Quiz")", symbolName: "questionmark.app") }
        let understandingEntries = understandingAttempts
            .filter { $0.autonomousResult == .independent || $0.autonomousResult == .partial }
            .map { StudyActivityEntry(id: "understanding-\($0.id)", date: $0.updatedAt, courseID: $0.course?.id, title: "Compréhension vérifiée · \($0.subject)", symbolName: "brain.head.profile") }
        let externalEntries = externalActivities
            .filter { $0.status == .completed }
            .map { StudyActivityEntry(id: "external-\($0.id)", date: $0.updatedAt, courseID: $0.course?.id, title: "Activité terminée · \($0.title)", symbolName: "link") }
        let exerciseEntries = mathAttempts
            .filter { $0.status == .submitted }
            .map { StudyActivityEntry(id: "exercise-\($0.id)", date: $0.submittedAt ?? $0.updatedAt, courseID: $0.exercise?.course?.id, title: "Exercice remis · \($0.exercise?.title ?? "Exercice")", symbolName: "pencil.and.outline") }
        return (taskEntries + revisionEntries + flashcardEntries + quizEntries + understandingEntries + externalEntries + exerciseEntries)
            .sorted { $0.date > $1.date }
    }

    static func streakSummary(from activities: [StudyActivityEntry], calendar: Calendar, now: Date) -> StudyStreakSummary {
        let days = Set(activities.map { calendar.startOfDay(for: $0.date) })
        let today = calendar.startOfDay(for: now)
        var current = 0
        var cursor = today
        while days.contains(cursor) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86_400)
        }
        var longest = 0
        var running = 0
        for day in days.sorted() {
            if let previous = calendar.date(byAdding: .day, value: -1, to: day), days.contains(previous) {
                running += 1
            } else {
                running = 1
            }
            longest = max(longest, running)
        }
        let week = TodayDashboardService.weekInterval(containing: now, calendar: calendar)
        let weekCount = days.filter { week.contains($0) }.count
        let recent = (0..<14).reversed().compactMap { offset -> StudyDayMarker? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return StudyDayMarker(id: date, label: date.formatted(.dateTime.weekday(.narrow)), hasActivity: days.contains(date))
        }
        return StudyStreakSummary(currentStreak: current, longestStreak: longest, studyDaysThisWeek: weekCount, recentDays: recent)
    }
}
