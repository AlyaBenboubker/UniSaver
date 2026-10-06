import SwiftData
import SwiftUI

struct StudyStudioView: View {
    @Query(sort: \StudyDeck.updatedAt, order: .reverse) private var decks: [StudyDeck]
    @Query(sort: \Flashcard.updatedAt, order: .reverse) private var cards: [Flashcard]
    @Query(sort: \FlashcardReviewEvent.reviewedAt, order: .reverse) private var reviewEvents: [FlashcardReviewEvent]
    @Query(sort: \Quiz.updatedAt, order: .reverse) private var quizzes: [Quiz]
    @Query(sort: \QuizAttempt.startedAt, order: .reverse) private var attempts: [QuizAttempt]
    @Query(sort: \UnderstandingPracticeAttempt.createdAt, order: .reverse) private var understandingAttempts: [UnderstandingPracticeAttempt]
    @Query(sort: \ExternalLearningActivity.updatedAt, order: .reverse) private var externalActivities: [ExternalLearningActivity]
    @Query(sort: \MathExercise.updatedAt, order: .reverse) private var mathExercises: [MathExercise]
    @Query(sort: \EssayAssignment.updatedAt, order: .reverse) private var essayAssignments: [EssayAssignment]
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var creatingDeck = false
    @State private var creatingCard = false
    @State private var bulkImport = false
    @State private var creatingQuiz = false
    @State private var creatingUnderstandingCheck = false
    @State private var reviewingCards: [Flashcard] = []
    @State private var selectedDeck: StudyDeck?
    @State private var selectedQuiz: Quiz?
    @State private var selectedExternalActivity: ExternalLearningActivity?
    @State private var selectedMathExercise: MathExercise?
    @State private var selectedEssayAssignment: EssayAssignment?

    private var activeDecks: [StudyDeck] {
        decks.filter { !$0.isArchived }
    }

    private var activeQuizzes: [Quiz] {
        quizzes.filter { !$0.isArchived }
    }

    private var dueCards: [Flashcard] {
        cards.filter { $0.deck?.isArchived != true && $0.reviewState.dueDate <= .now }
            .sorted { $0.reviewState.dueDate < $1.reviewState.dueDate }
    }

    private var recentAccuracy: Int? {
        let recent = Array(reviewEvents.prefix(20))
        guard !recent.isEmpty else { return nil }
        let correct = recent.filter { $0.rating == .good || $0.rating == .easy }.count
        return Int((Double(correct) / Double(recent.count) * 100).rounded())
    }

    private var reviewTimeThisWeek: TimeInterval {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return reviewEvents.filter { $0.reviewedAt >= start }.reduce(0) { $0 + $1.responseDuration }
    }

    private var understandingProgress: UnderstandingProgressSummary {
        UnderstandingPracticeService.progressSummary(for: understandingAttempts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StudyStudioHeader(dueCount: dueCards.count) {
                    reviewingCards = dueCards
                }
                studyMetrics
                understandingSection
                mathExercisesSection
                essayAssignmentsSection
                externalActivitiesSection
                decksSection
                quizzesSection
            }
            .padding(24)
            .frame(maxWidth: 1220, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .navigationTitle("Study")
        .toolbar {
            ToolbarItemGroup {
                Button("Create Deck", systemImage: "rectangle.stack.badge.plus") { creatingDeck = true }
                Button("Bulk Import", systemImage: "text.badge.plus") { bulkImport = true }
                Button("Create Quiz", systemImage: "questionmark.app") { creatingQuiz = true }
                Button("Understanding Check (demo)", systemImage: "brain.head.profile") { creatingUnderstandingCheck = true }
            }
        }
        .sheet(isPresented: $creatingDeck) { StudyDeckFormView() }
        .sheet(isPresented: $creatingCard) { FlashcardFormView() }
        .sheet(isPresented: $bulkImport) { BulkFlashcardImportView() }
        .sheet(isPresented: $creatingQuiz) { QuizFormView() }
        .sheet(isPresented: $creatingUnderstandingCheck) { UnderstandingPracticeFlowView() }
        .sheet(item: $selectedDeck) { deck in
            NavigationStack { DeckWorkspaceView(deck: deck) }
        }
        .sheet(item: $selectedQuiz) { quiz in
            QuizPracticeView(quiz: quiz)
        }
        .sheet(item: $selectedExternalActivity) { activity in
            ExternalLearningActivityWorkspaceView(activity: activity)
        }
        .sheet(item: $selectedMathExercise) { exercise in
            MathExerciseWorkspaceView(exercise: exercise)
        }
        .sheet(item: $selectedEssayAssignment) { assignment in
            EssayWorkspaceView(assignment: assignment)
        }
        .studyReviewPresentation(cards: $reviewingCards)
    }

    private var studyMetrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            StudyMetricCard(title: "Cards Due Today", value: "\(dueCards.count)", subtitle: "\(activeDecks.count) active decks", systemImage: "rectangle.stack.fill", tint: .purple)
            StudyMetricCard(title: "Review Time", value: minutesLabel(reviewTimeThisWeek), subtitle: "This week", systemImage: "timer", tint: .teal)
            StudyMetricCard(title: "Recent Accuracy", value: recentAccuracy.map { "\($0)%" } ?? "No data", subtitle: "Last 20 reviews", systemImage: "target", tint: .green)
            StudyMetricCard(title: "Quiz Progress", value: "\(attempts.filter { !$0.isCompleted }.count)", subtitle: "Attempts to continue", systemImage: "checklist.checked", tint: .orange)
            StudyMetricCard(title: "Redo Progress", value: "\(Int((understandingProgress.averageRedoProgress * 100).rounded()))%", subtitle: "\(understandingProgress.independentCount) independent checks", systemImage: "brain.head.profile", tint: .indigo)
        }
    }

    private var understandingSection: some View {
        StudySection(title: "Understanding Check (demo mode)", trailing: {
            Button("New Demo Check", systemImage: "plus") { creatingUnderstandingCheck = true }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                UnderstandingProgressCard(summary: understandingProgress) {
                    creatingUnderstandingCheck = true
                }
                if !understandingAttempts.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                        ForEach(Array(understandingAttempts.prefix(3))) { attempt in
                            UnderstandingAttemptCard(attempt: attempt)
                        }
                    }
                }
            }
        }
    }

    private var decksSection: some View {
        StudySection(title: "Your Decks", trailing: {
            HStack {
                Button("Create Card", systemImage: "plus.rectangle.on.rectangle") { creatingCard = true }
                Button("Bulk Import", systemImage: "text.badge.plus") { bulkImport = true }
            }
        }) {
            if activeDecks.isEmpty {
                CompactStudyEmptyState(title: "Create your first deck", message: "Paste flashcards from your own notes or add cards manually.", actionTitle: "Create Deck") {
                    creatingDeck = true
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(activeDecks) { deck in
                        StudyDeckCard(deck: deck) {
                            selectedDeck = deck
                        } reviewAction: {
                            reviewingCards = deck.cards.filter { $0.reviewState.dueDate <= .now }
                        }
                    }
                }
            }
        }
    }

    private var externalActivitiesSection: some View {
        StudySection(title: "Original platform activities", trailing: {
            Text("Moodle / Quizlet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }) {
            let visibleActivities = externalActivities.filter { $0.status != .completed }
            if visibleActivities.isEmpty {
                CompactStudyEmptyState(title: "No external exercises", message: "Add a Moodle or Quizlet activity from a course or chapter.", actionTitle: nil)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(visibleActivities) { activity in
                        ExternalLearningActivityCard(activity: activity) {
                            selectedExternalActivity = activity
                        }
                    }
                }
            }
        }
    }

    private var mathExercisesSection: some View {
        StudySection(title: "Atelier Maths", trailing: {
            Text("PDF · image · Moodle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }) {
            if mathExercises.isEmpty {
                CompactStudyEmptyState(title: "No imported exercises", message: "Import a real exercise from a course or chapter. On macOS you can work from the source and typed scratch; Pencil tools require iPad.", actionTitle: nil)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(mathExercises.prefix(6)) { exercise in
                        Button {
                            selectedMathExercise = exercise
                        } label: {
                            MathExerciseRow(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var essayAssignmentsSection: some View {
        StudySection(title: "Questions ouvertes et essais", trailing: {
            Text("Réponse complète")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }) {
            if essayAssignments.isEmpty {
                CompactStudyEmptyState(title: "No essay assignments", message: "Create an open question or essay from a course or chapter.", actionTitle: nil)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(essayAssignments.prefix(6)) { assignment in
                        Button {
                            selectedEssayAssignment = assignment
                        } label: {
                            EssayAssignmentRow(assignment: assignment)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var quizzesSection: some View {
        StudySection(title: "Quiz Studio", trailing: {
            Button("Create Quiz", systemImage: "questionmark.app") { creatingQuiz = true }
        }) {
            if activeQuizzes.isEmpty {
                CompactStudyEmptyState(title: "Create a practice quiz", message: "Build QCM, true/false, and short-answer quizzes with preview before importing.", actionTitle: "Create Quiz") {
                    creatingQuiz = true
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(activeQuizzes) { quiz in
                        QuizSummaryCard(quiz: quiz) {
                            selectedQuiz = quiz
                        }
                    }
                }
            }
        }
    }

    private func minutesLabel(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

struct CourseStudyView: View {
    let course: Course
    @Query(sort: \StudyDeck.updatedAt, order: .reverse) private var decks: [StudyDeck]
    @Query(sort: \Quiz.updatedAt, order: .reverse) private var quizzes: [Quiz]
    @Query(sort: \ExternalLearningActivity.updatedAt, order: .reverse) private var externalActivities: [ExternalLearningActivity]
    @Query(sort: \MathExercise.updatedAt, order: .reverse) private var mathExercises: [MathExercise]
    @Query(sort: \EssayAssignment.updatedAt, order: .reverse) private var essayAssignments: [EssayAssignment]
    @State private var creatingDeck = false
    @State private var bulkImport = false
    @State private var creatingQuiz = false
    @State private var creatingUnderstandingCheck = false
    @State private var configuringStudy = false
    @State private var reviewingCards: [Flashcard] = []
    @State private var reviewMode: FlashcardStudyMode = .flashcards
    @State private var reviewTimerMinutes: Int?
    @State private var selectedDeck: StudyDeck?
    @State private var selectedQuiz: Quiz?
    @State private var selectedExternalActivity: ExternalLearningActivity?
    @State private var selectedMathExercise: MathExercise?
    @State private var selectedEssayAssignment: EssayAssignment?

    private var courseDecks: [StudyDeck] {
        decks.filter { $0.course?.id == course.id && !$0.isArchived }
    }

    private var dueCards: [Flashcard] {
        courseDecks.flatMap(\.cards).filter { $0.reviewState.dueDate <= .now }
    }

    private var courseQuizzes: [Quiz] {
        quizzes.filter { $0.course?.id == course.id && !$0.isArchived }
    }

    private var courseExternalActivities: [ExternalLearningActivity] {
        externalActivities.filter { $0.course?.id == course.id }
    }

    private var courseMathExercises: [MathExercise] {
        mathExercises.filter { $0.course?.id == course.id }
    }

    private var courseEssayAssignments: [EssayAssignment] {
        essayAssignments.filter { $0.course?.id == course.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StudyStudioHeader(title: "Study for \(course.name)", subtitle: "\(dueCards.count) cards due · \(courseQuizzes.count) quizzes · \(courseMathExercises.count) math exercises · \(courseEssayAssignments.count) essays · \(courseExternalActivities.count) external activities", dueCount: dueCards.count) {
                    reviewMode = .quickReview
                    reviewTimerMinutes = nil
                    reviewingCards = dueCards
                }
                HStack {
                    Button("New Deck", systemImage: "rectangle.stack.badge.plus") { creatingDeck = true }
                    Button("Bulk Import", systemImage: "text.badge.plus") { bulkImport = true }
                    Button("Study Mode", systemImage: "sparkles.rectangle.stack") { configuringStudy = true }
                        .disabled(courseDecks.flatMap(\.cards).isEmpty)
                    Button("New Quiz", systemImage: "questionmark.app") { creatingQuiz = true }
                    Button("Understanding Check (demo)", systemImage: "brain.head.profile") { creatingUnderstandingCheck = true }
                }
                .buttonStyle(.bordered)

                if courseDecks.isEmpty && courseQuizzes.isEmpty && courseExternalActivities.isEmpty && courseMathExercises.isEmpty && courseEssayAssignments.isEmpty {
                    CompactStudyEmptyState(title: "Build study material for this course", message: "Create a deck, import your own flashcards, or build a practice quiz.", actionTitle: "Bulk Import") {
                        bulkImport = true
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                        ForEach(courseEssayAssignments) { assignment in
                            Button {
                                selectedEssayAssignment = assignment
                            } label: {
                                EssayAssignmentRow(assignment: assignment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                        ForEach(courseMathExercises) { exercise in
                            Button {
                                selectedMathExercise = exercise
                            } label: {
                                MathExerciseRow(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                        ForEach(courseExternalActivities) { activity in
                            ExternalLearningActivityCard(activity: activity) {
                                selectedExternalActivity = activity
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                        ForEach(courseDecks) { deck in
                            StudyDeckCard(deck: deck) { selectedDeck = deck } reviewAction: {
                                reviewMode = .quickReview
                                reviewTimerMinutes = nil
                                reviewingCards = deck.cards.filter { $0.reviewState.dueDate <= .now }
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                        ForEach(courseQuizzes) { quiz in
                            QuizSummaryCard(quiz: quiz) { selectedQuiz = quiz }
                        }
                    }
                }
            }
            .padding()
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .sheet(isPresented: $creatingDeck) { StudyDeckFormView(initialCourse: course) }
        .sheet(isPresented: $bulkImport) { BulkFlashcardImportView(initialCourse: course) }
        .sheet(isPresented: $configuringStudy) {
            FlashcardStudySetupView(title: course.name, decks: courseDecks, initialMode: .flashcards) { cards, mode, timer in
                reviewMode = mode
                reviewTimerMinutes = timer
                reviewingCards = cards
            }
        }
        .sheet(isPresented: $creatingQuiz) { QuizFormView(initialCourse: course) }
        .sheet(isPresented: $creatingUnderstandingCheck) { UnderstandingPracticeFlowView(initialCourse: course) }
        .sheet(item: $selectedDeck) { deck in NavigationStack { DeckWorkspaceView(deck: deck) } }
        .sheet(item: $selectedQuiz) { quiz in QuizPracticeView(quiz: quiz) }
        .sheet(item: $selectedExternalActivity) { activity in ExternalLearningActivityWorkspaceView(activity: activity) }
        .sheet(item: $selectedMathExercise) { exercise in MathExerciseWorkspaceView(exercise: exercise) }
        .sheet(item: $selectedEssayAssignment) { assignment in EssayWorkspaceView(assignment: assignment) }
        .studyReviewPresentation(cards: $reviewingCards, mode: reviewMode, timerMinutes: reviewTimerMinutes)
    }
}

enum FlashcardStudyMode: String, CaseIterable, Identifiable {
    case flashcards = "Flashcards"
    case learn = "Learn"
    case test = "Quizlet-style Test"
    case matching = "Matching"
    case written = "Written Practice"
    case quickReview = "Quick Review"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .flashcards: "rectangle.stack.fill"
        case .learn: "brain.head.profile"
        case .test: "checklist.checked"
        case .matching: "arrow.left.arrow.right.square"
        case .written: "pencil.and.outline"
        case .quickReview: "bolt.fill"
        }
    }

    var description: String {
        switch self {
        case .flashcards: "Reveal answers and rate your recall."
        case .learn: "Prioritize cards you do not know yet."
        case .test: "Answer mixed prompts from the selected deck."
        case .matching: "Match terms with definitions."
        case .written: "Type an answer, then self-assess against the saved answer."
        case .quickReview: "Short session from due or difficult cards."
        }
    }
}

private enum FlashcardStudyScope: String, CaseIterable, Identifiable {
    case due = "Due cards"
    case difficult = "Difficult"
    case all = "All cards"
    var id: String { rawValue }
}

struct FlashcardStudySetupView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let decks: [StudyDeck]
    let initialMode: FlashcardStudyMode
    let onStart: ([Flashcard], FlashcardStudyMode, Int?) -> Void
    @State private var selectedMode: FlashcardStudyMode
    @State private var selectedDeckID: UUID?
    @State private var scope: FlashcardStudyScope = .due
    @State private var sessionLength = 10
    @State private var timerEnabled = false
    @State private var timerMinutes = 15
    @State private var error: String?

    init(title: String, decks: [StudyDeck], initialMode: FlashcardStudyMode, onStart: @escaping ([Flashcard], FlashcardStudyMode, Int?) -> Void) {
        self.title = title
        self.decks = decks
        self.initialMode = initialMode
        self.onStart = onStart
        _selectedMode = State(initialValue: initialMode)
        _selectedDeckID = State(initialValue: decks.first?.id)
    }

    private var selectedDeck: StudyDeck? {
        decks.first { $0.id == selectedDeckID } ?? decks.first
    }

    private var availableCards: [Flashcard] {
        let source = (selectedDeck?.cards ?? decks.flatMap(\.cards)).sorted { $0.position < $1.position }
        switch scope {
        case .due:
            let due = source.filter { $0.reviewState.dueDate <= .now }
            return due.isEmpty ? source : due
        case .difficult:
            let difficult = source.filter { $0.reviewState.lastRating == .again || $0.reviewState.lastRating == .hard || $0.reviewState.lapses > 0 }
            return difficult.isEmpty ? source : difficult
        case .all:
            return source
        }
    }

    var body: some View {
        CreationWindow(
            icon: "sparkles.rectangle.stack",
            title: "Start Study Session",
            subtitle: "Choose the mode, scope, and timer before studying \(title).",
            accent: CourseColor.indigo.color,
            closeAction: { dismiss() }
        ) {
            CreationCard("Mode") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    ForEach(FlashcardStudyMode.allCases) { mode in
                        Button {
                            selectedMode = mode
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(mode.rawValue, systemImage: mode.systemImage)
                                    .font(.headline)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                            .background(selectedMode == mode ? CourseColor.indigo.color.opacity(0.16) : StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedMode == mode ? CourseColor.indigo.color.opacity(0.55) : StudyDeskTheme.borderSubtle, lineWidth: selectedMode == mode ? 2 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            CreationCard("Content") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Deck", selection: $selectedDeckID) {
                        Text("All decks").tag(UUID?.none)
                        ForEach(decks) { deck in
                            Text(deck.title).tag(Optional(deck.id))
                        }
                    }
                    Picker("Scope", selection: $scope) {
                        ForEach(FlashcardStudyScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Session length: \(min(sessionLength, availableCards.count)) cards", value: $sessionLength, in: 1...max(availableCards.count, 1))
                }
            }

            CreationCard("Timer") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use a study timer", isOn: $timerEnabled)
                    if timerEnabled {
                        Stepper("Timer: \(timerMinutes) minutes", value: $timerMinutes, in: 5...120, step: 5)
                        Text("The timer can be paused. UniSaver will not submit or end your session automatically when time runs out.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error {
                CreationErrorText(message: error)
            }
        } footer: {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                CreationPrimaryButton(title: "Start", systemImage: "play.fill", accent: CourseColor.indigo.color, isDisabled: availableCards.isEmpty, action: start)
            }
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 700, idealHeight: 780)
    }

    private func start() {
        let cards = Array(orderedCardsForMode().prefix(sessionLength))
        guard !cards.isEmpty else {
            error = "This scope has no cards to study."
            return
        }
        onStart(cards, selectedMode, timerEnabled ? timerMinutes : nil)
        dismiss()
    }

    private func orderedCardsForMode() -> [Flashcard] {
        switch selectedMode {
        case .learn, .quickReview:
            return availableCards.sorted {
                let leftWeight = difficultyWeight($0)
                let rightWeight = difficultyWeight($1)
                if leftWeight == rightWeight {
                    return $0.reviewState.dueDate < $1.reviewState.dueDate
                }
                return leftWeight < rightWeight
            }
        case .test, .matching:
            return availableCards.shuffled()
        case .flashcards, .written:
            return availableCards
        }
    }

    private func difficultyWeight(_ card: Flashcard) -> Int {
        if card.reviewState.lastRating == .again { return 0 }
        if card.reviewState.lastRating == .hard || card.reviewState.lapses > 0 { return 1 }
        return 2
    }
}

private struct StudyStudioHeader: View {
    var title = "Study Studio"
    var subtitle = "Flashcards, QCM, quizzes, and spaced repetition from your real study data."
    let dueCount: Int
    let startReview: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title.bold())
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Start Review", systemImage: "play.fill", action: startReview)
                .buttonStyle(.borderedProminent)
                .disabled(dueCount == 0)
        }
    }
}

private struct StudySection<Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                Spacer()
                trailing()
            }
            content()
        }
    }
}

private struct StudyMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .deskCard()
    }
}

private struct StudyDeckCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var deck: StudyDeck
    let openAction: () -> Void
    let reviewAction: () -> Void
    @State private var deleteConfirmation = false

    private var sortedCards: [Flashcard] {
        deck.cards.sorted { $0.position < $1.position }
    }

    private var dueCount: Int {
        sortedCards.filter { $0.reviewState.dueDate <= .now }.count
    }

    private var mastery: Double {
        guard !sortedCards.isEmpty else { return 0 }
        let mature = sortedCards.filter { $0.reviewState.repetitions >= 3 && $0.reviewState.lapses == 0 }.count
        return Double(mature) / Double(sortedCards.count)
    }

    private var lastActivity: Date? {
        sortedCards.compactMap(\.reviewState.lastReviewedAt).max() ?? sortedCards.map(\.updatedAt).max()
    }

    var body: some View {
        Button(action: openAction) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: CourseIconCatalog.sanitizedSymbolName(deck.symbolName))
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(CourseColor.color(for: deck.colorIdentifier), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deck.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text([deck.course?.name, deck.chapter?.title].compactMap { $0 }.joined(separator: " · ").nilIfEmpty ?? "General Study")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Menu {
                        Button("Browse Cards", systemImage: "rectangle.stack") { openAction() }
                        Button(deck.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                            deck.isArchived.toggle()
                            deck.updatedAt = .now
                            try? modelContext.save()
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.borderless)
                }

                ProgressView(value: mastery)
                    .tint(CourseColor.color(for: deck.colorIdentifier))
                HStack {
                    deckStat("\(sortedCards.count)", "Cards")
                    deckStat("\(dueCount)", "Due")
                    deckStat("\(Int((mastery * 100).rounded()))%", "Stable")
                    Spacer()
                }
                Text(lastActivity.map { "Last activity \(UniDateFormatters.dayMonth.string(from: $0))" } ?? "No activity yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Review", systemImage: "play.fill", action: reviewAction)
                    .buttonStyle(.bordered)
                    .disabled(dueCount == 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .deskCard()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Open \(deck.title)")
        .confirmationDialog("Delete deck?", isPresented: $deleteConfirmation) {
            Button("Delete Deck", role: .destructive) {
                modelContext.delete(deck)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the deck and its cards. Review history remains in the store until related cards are deleted by SwiftData.")
        }
    }

    private func deckStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 58, alignment: .leading)
    }
}

private struct QuizSummaryCard: View {
    let quiz: Quiz
    let openAction: () -> Void

    private var bestScore: String {
        let completed = quiz.attempts.filter { $0.isCompleted && $0.maximumScore > 0 }
        guard let best = completed.max(by: { ($0.score / $0.maximumScore) < ($1.score / $1.maximumScore) }) else {
            return "No score"
        }
        return "\(Int((best.score / best.maximumScore * 100).rounded()))%"
    }

    private var hasContinuation: Bool {
        quiz.attempts.contains { !$0.isCompleted }
    }

    var body: some View {
        Button(action: openAction) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(quiz.mode.title, systemImage: quiz.mode == .practice ? "play.circle" : "lock.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(quiz.mode == .practice ? .blue : .orange)
                    Spacer()
                    if hasContinuation {
                        Text("Continue")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.12), in: Capsule())
                    }
                }
                Text(quiz.title)
                    .font(.headline)
                    .lineLimit(2)
                Text([quiz.course?.name, quiz.chapter?.title].compactMap { $0 }.joined(separator: " · ").nilIfEmpty ?? "General quiz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Text("\(quiz.questions.count) questions")
                    Spacer()
                    Text("Best \(bestScore)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .deskCard()
        }
        .buttonStyle(.plain)
    }
}

private struct CompactStudyEmptyState: View {
    let title: String
    let message: String
    var actionTitle: String? = "Start"
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .foregroundStyle(StudyDeskTheme.accentPrimary)
                .frame(width: 42, height: 42)
                .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .deskCard()
    }
}

private struct UnderstandingProgressCard: View {
    let summary: UnderstandingProgressSummary
    let start: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.indigo, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text("Check that you can redo the work alone")
                    .font(.headline)
                Text("Paste an exercise, reveal help gradually, write your own attempt, then prove transfer on a nearby question.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    progressStat("\(summary.attemptCount)", "attempts")
                    progressStat("\(summary.independentCount)", "independent")
                    progressStat("\(Int((summary.averageRedoProgress * 100).rounded()))%", "redo progress")
                }
            }
            Spacer()
            Button("Start Demo Check", systemImage: "arrow.right", action: start)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .deskCard()
    }

    private func progressStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct UnderstandingAttemptCard: View {
    let attempt: UnderstandingPracticeAttempt

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attempt.autonomousResult.title, systemImage: resultIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(resultColor)
                Spacer()
                Text(attempt.helpLevelUsed.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(attempt.subject)
                .font(.headline)
                .lineLimit(1)
            Text(attempt.exercisePrompt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text("Saved \(UniDateFormatters.dayMonth.string(from: attempt.createdAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard()
    }

    private var resultIcon: String {
        switch attempt.autonomousResult {
        case .notChecked: "circle"
        case .couldNotRedo: "xmark.circle"
        case .partial: "circle.lefthalf.filled"
        case .independent: "checkmark.seal"
        }
    }

    private var resultColor: Color {
        switch attempt.autonomousResult {
        case .notChecked: .secondary
        case .couldNotRedo: .red
        case .partial: .orange
        case .independent: .green
        }
    }
}

struct UnderstandingPracticeFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    @State private var selectedCourseID: UUID?
    @State private var subject = ""
    @State private var exercise = ""
    @State private var studentAttempt = ""
    @State private var transferAnswer = ""
    @State private var autonomousResult: AutonomousCheckResult = .notChecked
    @State private var assistance: UnderstandingAssistance?
    @State private var isLoadingAssistance = false
    @State private var didRevealHint = false
    @State private var revealedStepCount = 0
    @State private var didRevealSolution = false
    @State private var error: String?
    @State private var successMessage: String?
    @AppStorage(AIRevisionSettings.fundingModeKey) private var aiFundingModeRaw = AIRevisionFundingMode.personalKey.rawValue
    @AppStorage(AIRevisionSettings.activeProviderKey) private var activeAIProviderRaw = AIRevisionProviderID.openAI.rawValue
    @AppStorage("aiRevisionModel.openAI") private var openAIModel = AIRevisionProviderID.openAI.defaultModel
    @AppStorage("aiRevisionModel.claude") private var claudeModel = AIRevisionProviderID.claude.defaultModel
    @AppStorage("aiRevisionModel.gemini") private var geminiModel = AIRevisionProviderID.gemini.defaultModel

    init(initialCourse: Course? = nil) {
        _selectedCourseID = State(initialValue: initialCourse?.id)
        _subject = State(initialValue: initialCourse?.name ?? "")
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    private var cleanSubject: String {
        subject.trimmedStudyText.nilIfEmpty ?? selectedCourse?.name ?? "General Study"
    }

    private var canAskForHelp: Bool {
        !exercise.trimmedStudyText.isEmpty && !cleanSubject.trimmedStudyText.isEmpty
    }

    private var canRevealSolution: Bool {
        !studentAttempt.trimmedStudyText.isEmpty
    }

    private var helpLevelUsed: UnderstandingHelpLevel {
        UnderstandingPracticeService.strongestHelpLevel(
            current: .none,
            didRevealHint: didRevealHint,
            revealedStepCount: revealedStepCount,
            didRevealSolution: didRevealSolution
        )
    }

    private var providerStatus: AIRevisionProviderStatus {
        aiClient.status()
    }

    private var aiClient: AIRevisionAssistantClient {
        AIRevisionAssistantClient(settings: aiSettings)
    }

    private var aiSettings: AIRevisionSettings {
        AIRevisionSettings(
            fundingMode: AIRevisionFundingMode(rawValue: aiFundingModeRaw) ?? .personalKey,
            activeProvider: AIRevisionProviderID(rawValue: activeAIProviderRaw) ?? .openAI,
            modelsByProvider: [
                .openAI: openAIModel,
                .claude: claudeModel,
                .gemini: geminiModel
            ]
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    providerBanner
                    exerciseSection
                    helpSection
                    attemptSection
                    transferSection
                    saveSection
                    if let successMessage {
                        Text(successMessage)
                            .foregroundStyle(.green)
                    }
                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                .padding(22)
                .frame(maxWidth: 900, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .background(StudyDeskTheme.backgroundPrimary)
            .navigationTitle("Understanding Check")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Check", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 760)
    }

    private var providerBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("AI mode", selection: $aiFundingModeRaw) {
                Text("Included with UniSaver").tag(AIRevisionFundingMode.included.rawValue)
                Text("My own key").tag(AIRevisionFundingMode.personalKey.rawValue)
            }
            .pickerStyle(.segmented)
            Label(providerBannerText, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
            if case .ready = providerStatus {
                Text("Fournisseur actif : \(aiClient.activeProviderSummary()). Les données envoyées sont l’exercice saisi, la matière et le cours sélectionné.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(aiClient.paymentDisclosure())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button("Configurer dans Settings", systemImage: "gearshape") {
                    NotificationCenter.default.post(name: .selectAppSection, object: AppSection.settings)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(providerBannerColor, in: RoundedRectangle(cornerRadius: 10))
    }

    private var providerBannerText: String {
        switch providerStatus {
        case .ready:
            return "IA configurée. L’aide respecte le parcours : indice, tentative personnelle, solution, puis transfert."
        case .notConfigured:
            return aiSettings.fundingMode == .included
                ? "IA incluse bientôt disponible : aucun abonnement, quota serveur ou backend UniSaver n’est configuré dans ce build."
                : "Aucun fournisseur IA n’est configuré. UniSaver ne génère pas d’aide simulée."
        case .error(let message):
            return "Fournisseur IA en erreur : \(message)"
        }
    }

    private var providerBannerColor: Color {
        switch providerStatus {
        case .ready: return .green.opacity(0.12)
        case .notConfigured, .error: return .orange.opacity(0.12)
        }
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Exercise")
                .font(.headline)
            Picker("Course", selection: $selectedCourseID) {
                Text("No course").tag(UUID?.none)
                ForEach(courses.filter { !$0.isArchived }) { course in
                    Text(course.name).tag(Optional(course.id))
                }
            }
            TextField("Subject or module", text: $subject)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $exercise)
                .font(.body)
                .frame(minHeight: 130)
                .padding(8)
                .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(StudyDeskTheme.borderSubtle) }
        }
        .padding(16)
        .deskCard()
    }

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("2. Progressive help")
                    .font(.headline)
                Spacer()
                Button(isLoadingAssistance ? "Preparing..." : "Prepare AI Help", systemImage: "wand.and.stars") {
                    Task { await loadAssistance() }
                }
                .disabled(!canAskForHelp || isLoadingAssistance || providerStatus != .ready)
            }
            if let assistance {
                HStack {
                    Button("Show Hint", systemImage: "lightbulb") {
                        didRevealHint = true
                    }
                    Button("Next Step", systemImage: "list.number") {
                        revealedStepCount = min(revealedStepCount + 1, assistance.explanationSteps.count)
                    }
                    .disabled(revealedStepCount >= assistance.explanationSteps.count)
                    Button("Show Solution", systemImage: "eye") {
                        didRevealSolution = true
                    }
                    .disabled(!canRevealSolution)
                    Spacer()
                    Text("Help used: \(helpLevelUsed.title)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)

                if didRevealHint {
                    StudyInfoBlock(title: "Hint", text: assistance.hint, systemImage: "lightbulb")
                }
                ForEach(Array(assistance.explanationSteps.prefix(revealedStepCount).enumerated()), id: \.offset) { index, step in
                    StudyInfoBlock(title: "Step \(index + 1)", text: step, systemImage: "arrow.right.circle")
                }
                if !canRevealSolution {
                    Text("Write your own attempt before revealing the solution.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if didRevealSolution {
                    StudyInfoBlock(title: "Solution Scaffold", text: assistance.solution, systemImage: "checklist")
                }
            } else {
                Text("Prepare help after entering the exercise. The first reveal is only a hint; the complete solution stays locked until you submit your own attempt.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .deskCard()
    }

    private var attemptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. Your attempt before the solution")
                .font(.headline)
            TextEditor(text: $studentAttempt)
                .font(.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(StudyDeskTheme.borderSubtle) }
        }
        .padding(16)
        .deskCard()
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("4. Transfer check")
                .font(.headline)
            if let assistance {
                StudyInfoBlock(title: "Nearby exercise", text: assistance.transferQuestion, systemImage: "shuffle")
                TextEditor(text: $transferAnswer)
                    .font(.body)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(StudyDeskTheme.borderSubtle) }
                StudyInfoBlock(title: "\(assistance.sourceLabel) self-check criteria", text: assistance.suggestedTransferAnswer, systemImage: "checkmark.circle")
            } else {
                Text("The transfer exercise appears after demo help is prepared.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .deskCard()
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("5. Result")
                .font(.headline)
            Picker("Could you redo a nearby exercise alone?", selection: $autonomousResult) {
                ForEach(AutonomousCheckResult.allCases.filter { $0 != .notChecked }) { result in
                    Text(result.title).tag(result)
                }
            }
            .pickerStyle(.segmented)
            ProgressView(value: autonomousResult.progressValue)
                .tint(.green)
            Button("Save Check", systemImage: "checkmark.seal", action: save)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
        .padding(16)
        .deskCard()
    }

    private var canSave: Bool {
        assistance != nil
            && !exercise.trimmedStudyText.isEmpty
            && !studentAttempt.trimmedStudyText.isEmpty
            && !transferAnswer.trimmedStudyText.isEmpty
            && autonomousResult != .notChecked
    }

    private func loadAssistance() async {
        guard canAskForHelp else {
            error = "Enter an exercise and subject first."
            return
        }
        isLoadingAssistance = true
        error = nil
        do {
            assistance = try await aiClient.understandingAssistance(for: exercise, subject: cleanSubject, course: selectedCourse)
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingAssistance = false
    }

    private func save() {
        guard let assistance else {
            error = "Prepare AI help before saving."
            return
        }
        guard canSave else {
            error = "Complete your attempt, transfer answer, and result before saving."
            return
        }
        let record = UnderstandingPracticeAttempt(
            exercisePrompt: exercise.trimmedStudyText,
            subject: cleanSubject,
            studentAttempt: studentAttempt.trimmedStudyText,
            hint: assistance.hint,
            explanationSteps: Array(assistance.explanationSteps.prefix(revealedStepCount)),
            solution: didRevealSolution ? assistance.solution : "",
            transferQuestion: assistance.transferQuestion,
            transferAnswer: transferAnswer.trimmedStudyText,
            suggestedTransferAnswer: assistance.suggestedTransferAnswer,
            helpLevelUsed: helpLevelUsed,
            autonomousResult: autonomousResult,
            assistanceSource: assistance.sourceLabel,
            course: selectedCourse
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
            successMessage = "Understanding check saved."
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DeckWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var deck: StudyDeck
    @State private var searchText = ""
    @State private var editingCard: Flashcard?
    @State private var creatingCard = false
    @State private var editingDeck = false
    @State private var importingCards = false
    @State private var configuringStudy = false
    @State private var reviewingCards: [Flashcard] = []
    @State private var reviewMode: FlashcardStudyMode = .flashcards
    @State private var reviewTimerMinutes: Int?
    @State private var deleteConfirmation: Flashcard?
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteDeckConfirmation = false
    @State private var feedback: String?

    private var filteredCards: [Flashcard] {
        deck.cards
            .sorted { $0.position < $1.position }
            .filter { searchText.isEmpty || $0.front.localizedCaseInsensitiveContains(searchText) || $0.back.localizedCaseInsensitiveContains(searchText) || $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText) }
    }

    private var sortedCards: [Flashcard] {
        deck.cards.sorted { $0.position < $1.position }
    }

    private var dueCards: [Flashcard] {
        sortedCards.filter { $0.reviewState.dueDate <= .now }
    }

    var body: some View {
        ZStack {
            StudyDeskTheme.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                deckHeader
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let feedback {
                            Label(feedback, systemImage: "checkmark.circle.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(12)
                                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                        studyActions
                        cardsSection
                    }
                    .padding(24)
                    .frame(maxWidth: 1040, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .navigationTitle(deck.title)
        .sheet(isPresented: $creatingCard) { FlashcardFormView(initialDeck: deck) }
        .sheet(isPresented: $editingDeck) { StudyDeckEditView(deck: deck) }
        .sheet(isPresented: $importingCards) { BulkFlashcardImportView(initialCourse: deck.course, initialChapter: deck.chapter, initialDeck: deck) }
        .sheet(isPresented: $configuringStudy) {
            FlashcardStudySetupView(title: deck.title, decks: [deck], initialMode: .flashcards) { cards, mode, timer in
                reviewMode = mode
                reviewTimerMinutes = timer
                reviewingCards = cards
            }
        }
        .sheet(item: $editingCard) { card in FlashcardEditView(card: card) }
        .studyReviewPresentation(cards: $reviewingCards, mode: reviewMode, timerMinutes: reviewTimerMinutes)
        .confirmationDialog("Delete flashcard?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let deleteConfirmation {
                    modelContext.delete(deleteConfirmation)
                    normalizePositions()
                }
                try? modelContext.save()
                deleteConfirmation = nil
                feedback = "Flashcard deleted."
            }
            Button("Cancel", role: .cancel) { deleteConfirmation = nil }
        }
        .confirmationDialog("Delete deck?", isPresented: $showingDeleteDeckConfirmation) {
            Button("Delete Deck and Cards", role: .destructive) {
                modelContext.delete(deck)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the deck and its flashcards from UniSaver. Existing course and chapter data stay untouched.")
        }
    }

    private var deckHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(CourseColor(rawValue: deck.colorIdentifier)?.color.opacity(0.16) ?? StudyDeskTheme.accentPrimary.opacity(0.14))
                    Image(systemName: deck.symbolName)
                        .font(.title2)
                        .foregroundStyle(CourseColor(rawValue: deck.colorIdentifier)?.color ?? StudyDeskTheme.accentPrimary)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 8) {
                    Text(deck.title)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text(deck.deckDescription.nilIfEmpty ?? "A focused deck for active recall.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        chip(deck.course?.name ?? "General Study", "books.vertical")
                        if let chapter = deck.chapter { chip(chapter.title, "list.number") }
                        if let session = deck.session { chip(session.title, "calendar") }
                    }
                }

                Spacer()

                Menu("Deck Actions", systemImage: "ellipsis.circle") {
                    Button("Rename and Link", systemImage: "pencil") { editingDeck = true }
                    Button("Import Flashcards", systemImage: "text.badge.plus") { importingCards = true }
                    Divider()
                    Button("Delete Deck", systemImage: "trash", role: .destructive) { showingDeleteDeckConfirmation = true }
                }
                .menuStyle(.button)
            }

            HStack(spacing: 12) {
                Button("Study Due Cards", systemImage: "play.fill") {
                    reviewingCards = dueCards
                }
                .buttonStyle(.borderedProminent)
                .disabled(dueCards.isEmpty)

                Button("Study All", systemImage: "rectangle.stack.fill") {
                    reviewingCards = sortedCards
                }
                .buttonStyle(.bordered)
                .disabled(sortedCards.isEmpty)

                Button("Add Card", systemImage: "plus") { creatingCard = true }
                    .buttonStyle(.bordered)

                Button("Import", systemImage: "square.and.arrow.down") { importingCards = true }
                    .buttonStyle(.bordered)

                Button("Choose Mode", systemImage: "sparkles.rectangle.stack") { configuringStudy = true }
                    .buttonStyle(.bordered)
                    .disabled(sortedCards.isEmpty)
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [StudyDeskTheme.surfacePrimary, StudyDeskTheme.surfaceTinted.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var studyActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            DeckStatCard(title: "Cards", value: "\(deck.cards.count)", subtitle: "In this deck", color: .purple)
            DeckStatCard(title: "Due", value: "\(dueCards.count)", subtitle: "Ready to review", color: .orange)
            DeckStatCard(title: "Reviewed", value: "\(deck.cards.filter { $0.reviewState.lastReviewedAt != nil }.count)", subtitle: "With saved progress", color: .green)
        }
    }

    private var cardsSection: some View {
        CreationCard("Cards") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("Search cards", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                    Spacer()
                    Button("Add Card", systemImage: "plus") { creatingCard = true }
                    Button("Import", systemImage: "text.badge.plus") { importingCards = true }
                }

                if filteredCards.isEmpty {
                    EmptyStateView(
                        title: deck.cards.isEmpty ? "No cards yet" : "No matching cards",
                        message: deck.cards.isEmpty ? "Add a card manually or import a batch from your notes." : "Try another search term.",
                        systemImage: "rectangle.stack"
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredCards) { card in
                            FlashcardRow(
                                card: card,
                                canMoveUp: canMove(card, direction: -1),
                                canMoveDown: canMove(card, direction: 1),
                                edit: { editingCard = card },
                                delete: {
                                    deleteConfirmation = card
                                    showingDeleteConfirmation = true
                                },
                                moveUp: { move(card, direction: -1) },
                                moveDown: { move(card, direction: 1) }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ text: String, _ systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(StudyDeskTheme.surfacePrimary, in: Capsule())
            .overlay { Capsule().stroke(StudyDeskTheme.borderSubtle) }
    }

    private func canMove(_ card: Flashcard, direction: Int) -> Bool {
        guard searchText.isEmpty, let index = sortedCards.firstIndex(where: { $0.id == card.id }) else { return false }
        let destination = index + direction
        return sortedCards.indices.contains(destination)
    }

    private func move(_ card: Flashcard, direction: Int) {
        var cards = sortedCards
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        let destination = index + direction
        guard cards.indices.contains(destination) else { return }
        cards.swapAt(index, destination)
        for (position, card) in cards.enumerated() {
            card.position = position
            card.updatedAt = .now
        }
        deck.updatedAt = .now
        try? modelContext.save()
        feedback = "Card order updated."
    }

    private func normalizePositions() {
        for (position, card) in sortedCards.enumerated() {
            card.position = position
        }
    }
}

private struct DeckStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.18)) }
    }
}

private struct FlashcardRow: View {
    let card: Flashcard
    let canMoveUp: Bool
    let canMoveDown: Bool
    let edit: () -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.front)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.back)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !card.tags.isEmpty {
                    Text(card.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button("Edit", systemImage: "pencil", action: edit)
                    Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                }
                .labelStyle(.iconOnly)
                HStack(spacing: 6) {
                    Button("Move Up", systemImage: "chevron.up", action: moveUp)
                        .disabled(!canMoveUp)
                    Button("Move Down", systemImage: "chevron.down", action: moveDown)
                        .disabled(!canMoveDown)
                }
                .labelStyle(.iconOnly)
            }
        }
        .padding(16)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(StudyDeskTheme.borderSubtle) }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: edit)
        .accessibilityElement(children: .combine)
    }
}

struct FlashcardEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var card: Flashcard
    @State private var tagsText = ""
    @State private var error: String?

    var body: some View {
        CreationWindow(
            icon: "pencil",
            title: "Edit Flashcard",
            subtitle: "Keep the prompt and answer readable for review.",
            accent: CourseColor.sky.color,
            closeAction: { dismiss() }
        ) {
            CreationCard("Card") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Front", text: $card.front, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                    TextField("Back", text: $card.back, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                    TextField("Hint", text: Binding($card.hint, replacingNilWith: ""))
                        .textFieldStyle(.roundedBorder)
                    TextField("Explanation", text: Binding($card.explanation, replacingNilWith: ""), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...6)
                    TextField("Tags", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            if let error {
                CreationErrorText(message: error)
            }
        } footer: {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                CreationPrimaryButton(
                    title: "Save",
                    systemImage: "checkmark.circle.fill",
                    accent: CourseColor.sky.color,
                    isDisabled: card.front.trimmedStudyText.isEmpty || card.back.trimmedStudyText.isEmpty,
                    action: save
                )
            }
        }
        .frame(minWidth: 560, idealWidth: 700, minHeight: 560, idealHeight: 680)
        .onAppear { tagsText = card.tags.joined(separator: ", ") }
    }

    private func save() {
        guard !card.front.trimmedStudyText.isEmpty else {
            error = "Enter the card front."
            return
        }
        guard !card.back.trimmedStudyText.isEmpty else {
            error = "Enter the card back."
            return
        }
        card.front = card.front.trimmedStudyText
        card.back = card.back.trimmedStudyText
        card.tags = tagsText.studyTags
        card.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct StudyDeckEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    @Bindable var deck: StudyDeck
    @State private var title = ""
    @State private var description = ""
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var error: String?

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    var body: some View {
        CreationWindow(
            icon: "rectangle.stack.fill",
            title: "Edit Deck",
            subtitle: "Rename the deck or move it to the right course and chapter.",
            accent: CourseColor.teal.color,
            closeAction: { dismiss() }
        ) {
            CreationCard("Deck Details") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                    TextField("Description", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Picker("Course", selection: $selectedCourseID) {
                        Text("General Study").tag(UUID?.none)
                        ForEach(courses) { course in
                            Text(course.name).tag(Optional(course.id))
                        }
                    }
                    Picker("Chapter", selection: $selectedChapterID) {
                        Text("No chapter").tag(UUID?.none)
                        ForEach((selectedCourse?.chapters ?? []).sorted { $0.order < $1.order }) { chapter in
                            Text(chapter.title).tag(Optional(chapter.id))
                        }
                    }
                }
            }
            if let error {
                CreationErrorText(message: error)
            }
        } footer: {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                CreationPrimaryButton(
                    title: "Save",
                    systemImage: "checkmark.circle.fill",
                    accent: CourseColor.teal.color,
                    isDisabled: title.trimmedStudyText.isEmpty,
                    action: save
                )
            }
        }
        .frame(minWidth: 540, idealWidth: 640, minHeight: 410, idealHeight: 500)
        .onAppear {
            title = deck.title
            description = deck.deckDescription
            selectedCourseID = deck.course?.id
            selectedChapterID = deck.chapter?.id
        }
        .onChange(of: selectedCourseID) { _, _ in
            if selectedCourse?.chapters.contains(where: { $0.id == selectedChapterID }) != true {
                selectedChapterID = nil
            }
        }
    }

    private func save() {
        let cleanTitle = title.trimmedStudyText
        guard !cleanTitle.isEmpty else {
            error = "Enter a deck title."
            return
        }
        let course = selectedCourse
        deck.title = cleanTitle
        deck.deckDescription = description.trimmedStudyText
        deck.course = course
        deck.chapter = course?.chapters.first { $0.id == selectedChapterID }
        deck.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct StudyDeckFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    let initialCourse: Course?
    let initialChapter: Chapter?
    let initialSession: ClassSession?
    let onSave: ((StudyDeck) -> Void)?
    @State private var title = ""
    @State private var description = ""
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var error: String?

    init(initialCourse: Course? = nil, initialChapter: Chapter? = nil, initialSession: ClassSession? = nil, onSave: ((StudyDeck) -> Void)? = nil) {
        self.initialCourse = initialCourse
        self.initialChapter = initialChapter
        self.initialSession = initialSession
        self.onSave = onSave
        _selectedCourseID = State(initialValue: initialCourse?.id)
        _selectedChapterID = State(initialValue: initialChapter?.id)
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID } ?? initialCourse
    }

    var body: some View {
        CreationWindow(
            icon: "rectangle.stack.fill",
            title: "Créer un deck",
            subtitle: "Prépare un paquet de cartes lié à la bonne matière.",
            accent: CourseColor.teal.color,
            closeAction: { dismiss() }
        ) {
            CreationCard("Deck") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Titre", text: $title)
                        .textFieldStyle(.roundedBorder)
                    TextField("Description", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Picker("Matière", selection: $selectedCourseID) {
                        Text("Étude générale").tag(UUID?.none)
                        ForEach(courses) { course in Text(course.name).tag(Optional(course.id)) }
                    }
                    Picker("Chapitre", selection: $selectedChapterID) {
                        Text("Sans chapitre").tag(UUID?.none)
                        ForEach((selectedCourse?.chapters ?? []).sorted { $0.order < $1.order }) { chapter in
                            Text(chapter.title).tag(Optional(chapter.id))
                        }
                    }
                }
            }
            if let error {
                CreationErrorText(message: error)
            }
        } footer: {
            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                CreationPrimaryButton(title: "Créer", systemImage: "checkmark.circle.fill", accent: CourseColor.teal.color, isDisabled: title.trimmedStudyText.isEmpty, action: save)
            }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 390, idealHeight: 460)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            error = "Enter a deck title."
            return
        }
        let course = selectedCourse
        let chapter = course?.chapters.first { $0.id == selectedChapterID } ?? initialChapter
        let deck = StudyDeck(
            title: cleanTitle,
            deckDescription: description,
            colorIdentifier: course?.colorIdentifier ?? "blueViolet",
            symbolName: course?.symbolName ?? "rectangle.stack.fill",
            course: course,
            chapter: chapter,
            session: initialSession
        )
        modelContext.insert(deck)
        do {
            try modelContext.save()
            onSave?(deck)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct FlashcardFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyDeck.title) private var decks: [StudyDeck]
    let initialDeck: StudyDeck?
    @State private var selectedDeckID: UUID?
    @State private var front = ""
    @State private var back = ""
    @State private var hint = ""
    @State private var explanation = ""
    @State private var tags = ""
    @State private var error: String?

    init(initialDeck: StudyDeck? = nil) {
        self.initialDeck = initialDeck
        _selectedDeckID = State(initialValue: initialDeck?.id)
    }

    var body: some View {
        CreationWindow(
            icon: "rectangle.stack.badge.plus",
            title: "New Flashcard",
            subtitle: "Write one clear prompt and one answer. You can add hints and tags if they help review.",
            accent: CourseColor.sky.color,
            closeAction: { dismiss() }
        ) {
            CreationCard("Card") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Front", text: $front, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                    TextField("Back", text: $back, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                    TextField("Hint", text: $hint)
                        .textFieldStyle(.roundedBorder)
                    TextField("Explanation", text: $explanation, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...6)
                    TextField("Tags", text: $tags)
                        .textFieldStyle(.roundedBorder)
                    Picker("Deck", selection: $selectedDeckID) {
                        Text("Choose a deck").tag(UUID?.none)
                        ForEach(decks.filter { !$0.isArchived }) { deck in
                            Text(deck.title).tag(Optional(deck.id))
                        }
                    }
                }
            }
            if let error {
                CreationErrorText(message: error)
            }
        } footer: {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                CreationPrimaryButton(
                    title: "Save",
                    systemImage: "checkmark.circle.fill",
                    accent: CourseColor.sky.color,
                    isDisabled: front.trimmedStudyText.isEmpty || back.trimmedStudyText.isEmpty || selectedDeckID == nil,
                    action: save
                )
            }
        }
        .frame(minWidth: 560, idealWidth: 700, minHeight: 560, idealHeight: 680)
    }

    private func save() {
        guard let deck = decks.first(where: { $0.id == selectedDeckID }) ?? initialDeck else {
            error = "Choose a deck."
            return
        }
        guard !front.trimmedStudyText.isEmpty else {
            error = "Enter the card front."
            return
        }
        guard !back.trimmedStudyText.isEmpty else {
            error = "Enter the card back."
            return
        }
        let card = Flashcard(
            front: front.trimmedStudyText,
            back: back.trimmedStudyText,
            hint: hint.trimmedStudyText.nilIfEmpty,
            explanation: explanation.trimmedStudyText.nilIfEmpty,
            tags: tags.studyTags,
            position: deck.cards.count,
            deck: deck
        )
        deck.cards.append(card)
        modelContext.insert(card)
        try? modelContext.save()
        dismiss()
    }
}

private enum BulkImportStep: String, CaseIterable, Identifiable {
    case configure = "Configure"
    case paste = "Paste & Parse"
    case review = "Review & Import"
    var id: String { rawValue }
}

private enum ParsedFlashcardStatus: String {
    case valid = "Valid"
    case warning = "Warning"
    case duplicate = "Duplicate"
    case invalid = "Invalid"
}

private enum FlashcardImportDestination: String, CaseIterable, Identifiable {
    case existing = "Existing Deck"
    case new = "New Deck"
    var id: String { rawValue }
}

private enum FlashcardImportError: LocalizedError {
    case missingDeck
    case missingDeckTitle

    var errorDescription: String? {
        switch self {
        case .missingDeck: "Choose a deck, or create a new one for this import."
        case .missingDeckTitle: "Enter a title for the new deck."
        }
    }
}

private struct FlashcardImportRow: Identifiable {
    let id = UUID()
    var source: ParsedFlashcard
    var include: Bool
    var isExistingDuplicate: Bool
    var isInternalDuplicate: Bool

    var status: ParsedFlashcardStatus {
        if !source.errors.isEmpty { return .invalid }
        if isExistingDuplicate || isInternalDuplicate { return .duplicate }
        if !source.warnings.isEmpty { return .warning }
        return .valid
    }

    var canImport: Bool {
        include && source.isValid && !isExistingDuplicate && !isInternalDuplicate
    }
}

struct BulkFlashcardImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyDeck.title) private var decks: [StudyDeck]
    @Query(sort: \Course.name) private var courses: [Course]
    let initialCourse: Course?
    let initialChapter: Chapter?
    let initialDeck: StudyDeck?
    @State private var step: BulkImportStep = .configure
    @State private var destination: FlashcardImportDestination = .existing
    @State private var selectedDeckID: UUID?
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var newDeckTitle = ""
    @State private var newDeckDescription = ""
    @State private var cardCount = 25
    @State private var language = "English"
    @State private var difficulty = "Undergraduate"
    @State private var text = ""
    @State private var rows: [FlashcardImportRow] = []
    @State private var isImporting = false
    @State private var error: String?
    @State private var copied = false
    @State private var successMessage: String?

    init(initialCourse: Course? = nil, initialChapter: Chapter? = nil, initialDeck: StudyDeck? = nil) {
        self.initialCourse = initialCourse
        self.initialChapter = initialChapter
        self.initialDeck = initialDeck
        _selectedDeckID = State(initialValue: initialDeck?.id)
        _selectedCourseID = State(initialValue: initialCourse?.id)
        _selectedChapterID = State(initialValue: initialChapter?.id)
        _newDeckTitle = State(initialValue: initialChapter?.title ?? initialCourse.map { "\($0.name) flashcards" } ?? "")
    }

    private var selectedDeck: StudyDeck? {
        decks.first { $0.id == selectedDeckID } ?? initialDeck
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID } ?? selectedDeck?.course ?? initialCourse
    }

    private var selectedChapter: Chapter? {
        selectedCourse?.chapters.first { $0.id == selectedChapterID } ?? selectedDeck?.chapter ?? initialChapter
    }

    private var importableCount: Int {
        rows.filter(\.canImport).count
    }

    private var canAdvanceFromConfigure: Bool {
        switch destination {
        case .existing: selectedDeck != nil
        case .new: !newDeckTitle.trimmedStudyText.isEmpty
        }
    }

    private var prompt: String {
        """
        Create \(cardCount) accurate UniSaver flashcards in \(language).
        Course: \(selectedCourse?.name ?? "General Study")
        Chapter: \(selectedChapter?.title ?? "Not specified")
        Difficulty: \(difficulty)

        Output only this exact plain-text format. Do not add Markdown fences, numbering, commentary, or extra headings.

        FLASHCARD
        Front: ...
        Back: ...
        Hint: ...
        Explanation: ...
        Tags: tag1, tag2
        ---
        """
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Step", selection: $step) {
                    ForEach(BulkImportStep.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                .disabled(isImporting)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch step {
                        case .configure:
                            configureStep
                        case .paste:
                            pasteStep
                        case .review:
                            reviewStep
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 920, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Bulk Create Flashcards")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isImporting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: primaryAction) {
                        if isImporting {
                            HStack { ProgressView(); Text("Importing...") }
                        } else {
                            Text(primaryTitle)
                        }
                    }
                    .disabled(!primaryEnabled)
                    .accessibilityIdentifier("bulkFlashcardPrimaryButton")
                }
            }
        }
        .frame(minWidth: 760, minHeight: 720)
        .onAppear {
            if selectedDeckID == nil, let initialDeck {
                selectedDeckID = initialDeck.id
                destination = .existing
                syncContextFromDeck()
            } else if selectedDeckID == nil {
                selectedDeckID = decks.first { !$0.isArchived && ($0.course?.id == initialCourse?.id || initialCourse == nil) }?.id
                syncContextFromDeck()
            }
            if selectedDeckID == nil {
                destination = .new
            }
        }
        .onChange(of: selectedDeckID) { _, _ in syncContextFromDeck() }
    }

    private var configureStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Destination", selection: $destination) {
                ForEach(FlashcardImportDestination.allCases) { destination in
                    Text(destination.rawValue).tag(destination)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            if destination == .existing {
                LabeledContent("Deck") {
                    Picker("Deck", selection: $selectedDeckID) {
                        Text("Choose a deck").tag(UUID?.none)
                        ForEach(decks.filter { !$0.isArchived }) { deck in Text(deck.title).tag(Optional(deck.id)) }
                    }
                    .frame(maxWidth: 360)
                }
                if selectedDeck == nil {
                    Text("A deck is required for import. Choose an existing deck or create a new one here without losing your pasted cards.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                CreationCard("New Deck") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Deck title", text: $newDeckTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField("Description", text: $newDeckDescription, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            LabeledContent("Course") {
                Picker("Course", selection: $selectedCourseID) {
                    Text("General Study").tag(UUID?.none)
                    ForEach(courses) { course in Text(course.name).tag(Optional(course.id)) }
                }
                .frame(maxWidth: 360)
            }
            LabeledContent("Chapter") {
                Picker("Chapter", selection: $selectedChapterID) {
                    Text("No chapter").tag(UUID?.none)
                    ForEach((selectedCourse?.chapters ?? []).sorted { $0.order < $1.order }) { chapter in
                        Text(chapter.title).tag(Optional(chapter.id))
                    }
                }
                .frame(maxWidth: 360)
            }
            HStack {
                Stepper("Cards: \(cardCount)", value: $cardCount, in: 5...80)
                TextField("Difficulty", text: $difficulty)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                TextField("Language", text: $language)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ChatGPT prompt")
                        .font(.headline)
                    Spacer()
                    if copied { Text("Copied").font(.caption).foregroundStyle(.green) }
                    Button("Copy Prompt", systemImage: "doc.on.doc", action: copyPrompt)
                    Link("Open ChatGPT", destination: URL(string: "https://chatgpt.com/")!)
                }
                Text(prompt)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(StudyDeskTheme.borderSubtle) }
            }
        }
    }

    private var pasteStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Paste generated cards")
                    .font(.headline)
                Spacer()
                Button("Paste", systemImage: "doc.on.clipboard") { pasteText() }
                Button("Clear", systemImage: "xmark") { text = ""; rows = [] }
                Button("Parse", systemImage: "wand.and.stars", action: parse)
                    .buttonStyle(.borderedProminent)
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("""
                    FLASHCARD
                    Front: What is price elasticity of demand?
                    Back: The responsiveness of quantity demanded to a change in price.
                    Hint: Think percentage changes.
                    Explanation: PED = % change in quantity demanded / % change in price.
                    Tags: economics, elasticity
                    ---
                    """)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(12)
                }
                TextEditor(text: $text)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
            .frame(minHeight: 320)
            .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(StudyDeskTheme.borderSubtle) }

            if !rows.isEmpty {
                ParseSummaryView(rows: rows)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ParseSummaryView(rows: rows)
                Spacer()
            }
            HStack {
                Button("Select All") { rows.indices.forEach { rows[$0].include = true } }
                Button("Exclude Invalid") { rows.indices.forEach { if !rows[$0].source.isValid { rows[$0].include = false } } }
                Button("Skip Duplicates") { rows.indices.forEach { if rows[$0].isExistingDuplicate || rows[$0].isInternalDuplicate { rows[$0].include = false } } }
            }
            .buttonStyle(.bordered)
            LazyVStack(spacing: 10) {
                ForEach($rows) { $row in
                    FlashcardPreviewRow(row: $row)
                }
            }
            if let successMessage {
                Text(successMessage).foregroundStyle(.green)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
    }

    private var primaryTitle: String {
        switch step {
        case .configure: "Next"
        case .paste: rows.isEmpty ? "Parse" : "Review"
        case .review: "Import \(importableCount) Cards"
        }
    }

    private var primaryEnabled: Bool {
        switch step {
        case .configure: canAdvanceFromConfigure
        case .paste: !text.trimmedStudyText.isEmpty
        case .review: importableCount > 0 && !isImporting
        }
    }

    private func primaryAction() {
        switch step {
        case .configure:
            step = .paste
        case .paste:
            if rows.isEmpty { parse() }
            if !rows.isEmpty {
                refreshDuplicateChecks()
                step = .review
            }
        case .review:
            importCards()
        }
    }

    private func syncContextFromDeck() {
        guard let deck = selectedDeck else { return }
        selectedCourseID = deck.course?.id ?? selectedCourseID
        selectedChapterID = deck.chapter?.id ?? selectedChapterID
    }

    private func parse() {
        guard canAdvanceFromConfigure else {
            error = destination == .existing ? "Choose a deck before parsing." : "Enter a deck title before parsing."
            return
        }
        let parsed = FlashcardBulkParser.parse(text)
        let existingFronts = Set((destination == .existing ? selectedDeck?.cards ?? [] : []).map { $0.front.normalizedStudyKey })
        rows = parsed.cards.map { card in
            let normalized = card.front.normalizedStudyKey
            let isExisting = existingFronts.contains(normalized)
            let isInternal = parsed.duplicateFronts.contains(normalized)
            return FlashcardImportRow(source: card, include: card.isValid && !isExisting && !isInternal, isExistingDuplicate: isExisting, isInternalDuplicate: isInternal)
        }
        error = rows.isEmpty ? "No flashcard blocks found." : nil
    }

    private func importCards() {
        guard !isImporting else { return }
        refreshDuplicateChecks()
        let toImport = rows.filter(\.canImport)
        guard !toImport.isEmpty else {
            error = "No valid cards selected for import."
            return
        }
        isImporting = true
        var inserted: [Flashcard] = []
        do {
            let deck = try targetDeckForImport()
            for row in toImport {
                let card = Flashcard(
                    front: row.source.front.trimmedStudyText,
                    back: row.source.back.trimmedStudyText,
                    hint: row.source.hint?.trimmedStudyText.nilIfEmpty,
                    explanation: row.source.explanation?.trimmedStudyText.nilIfEmpty,
                    tags: row.source.tags,
                    position: deck.cards.count + inserted.count,
                    deck: deck
                )
            inserted.append(card)
            modelContext.insert(card)
            }
            deck.cards.append(contentsOf: inserted)
            deck.updatedAt = .now
            try modelContext.save()
            successMessage = "\(inserted.count) flashcards imported into \(deck.title)"
            dismiss()
        } catch {
            inserted.forEach(modelContext.delete)
            self.error = error.localizedDescription
            isImporting = false
        }
    }

    private func targetDeckForImport() throws -> StudyDeck {
        switch destination {
        case .existing:
            guard let selectedDeck else { throw FlashcardImportError.missingDeck }
            return selectedDeck
        case .new:
            let cleanTitle = newDeckTitle.trimmedStudyText
            guard !cleanTitle.isEmpty else { throw FlashcardImportError.missingDeckTitle }
            let course = selectedCourse
            let deck = StudyDeck(
                title: cleanTitle,
                deckDescription: newDeckDescription.trimmedStudyText,
                colorIdentifier: course?.colorIdentifier ?? "blueViolet",
                symbolName: course?.symbolName ?? "rectangle.stack.fill",
                course: course,
                chapter: selectedChapter
            )
            modelContext.insert(deck)
            return deck
        }
    }

    private func refreshDuplicateChecks() {
        let existingFronts = Set((destination == .existing ? selectedDeck?.cards ?? [] : []).map { $0.front.normalizedStudyKey })
        let grouped = Dictionary(grouping: rows.map { $0.source.front.normalizedStudyKey }, by: { $0 })
        let internalDuplicates = Set(grouped.filter { !$0.key.isEmpty && $0.value.count > 1 }.keys)
        for index in rows.indices {
            let normalized = rows[index].source.front.normalizedStudyKey
            rows[index].isExistingDuplicate = existingFronts.contains(normalized)
            rows[index].isInternalDuplicate = internalDuplicates.contains(normalized)
            rows[index].include = rows[index].include && rows[index].source.isValid && !rows[index].isExistingDuplicate && !rows[index].isInternalDuplicate
        }
    }

    private func copyPrompt() {
        setClipboard(prompt)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { copied = false }
        }
    }

    private func pasteText() {
        if let pasted = getClipboard(), !pasted.isEmpty {
            text = pasted
        }
    }
}

private struct ParseSummaryView: View {
    let rows: [FlashcardImportRow]

    var body: some View {
        HStack(spacing: 10) {
            chip("\(rows.filter { $0.status == .valid }.count) valid", .green)
            chip("\(rows.filter { $0.status == .warning }.count) warnings", .orange)
            chip("\(rows.filter { $0.status == .duplicate }.count) duplicates", .blue)
            chip("\(rows.filter { $0.status == .invalid }.count) invalid", .red)
        }
        .font(.caption.weight(.semibold))
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct FlashcardPreviewRow: View {
    @Binding var row: FlashcardImportRow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Include", isOn: $row.include)
                    .labelsHidden()
                    .disabled(!row.source.isValid)
                statusBadge
                Text("Line \(row.source.sourceLine)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove", systemImage: "trash") { row.include = false }
                    .labelStyle(.iconOnly)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Front").foregroundStyle(.secondary)
                    TextField("Front", text: $row.source.front, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Back").foregroundStyle(.secondary)
                    TextField("Back", text: $row.source.back, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Hint").foregroundStyle(.secondary)
                    TextField("Hint", text: Binding($row.source.hint, replacingNilWith: ""))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Tags").foregroundStyle(.secondary)
                    Text(row.source.tags.joined(separator: ", ").nilIfEmpty ?? "No tags")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(row.source.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
            ForEach(row.source.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            if row.isExistingDuplicate { Text("Already exists in this deck.").font(.caption).foregroundStyle(.blue) }
            if row.isInternalDuplicate { Text("Duplicate in pasted content.").font(.caption).foregroundStyle(.blue) }
        }
        .padding(14)
        .deskCard()
    }

    private var statusBadge: some View {
        Text(row.status.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.13), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch row.status {
        case .valid: .green
        case .warning: .orange
        case .duplicate: .blue
        case .invalid: .red
        }
    }
}

struct FlashcardReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let cards: [Flashcard]
    var mode: FlashcardStudyMode = .flashcards
    var timerMinutes: Int?
    @State private var index = 0
    @State private var showingAnswer = false
    @State private var lastEvent: FlashcardReviewEvent?
    @State private var reviewed = 0
    @State private var correctish = 0
    @State private var startDate = Date()
    @State private var remainingSeconds: Int?
    @State private var timerPaused = false
    @State private var exitConfirmation = false
    @State private var writtenAnswer = ""
    @State private var selectedChoice: String?
    @State private var submittedChoice = false
    @State private var selectedMatchPrompt: Flashcard?
    @State private var matchedCardIDs: Set<UUID> = []
    @State private var matchMessage: String?
    private let scheduler = SimpleSpacedRepetitionScheduler()

    private var current: Flashcard? { cards.indices.contains(index) ? cards[index] : nil }
    private var progress: Double { cards.isEmpty ? 1 : Double(min(index, cards.count)) / Double(cards.count) }
    private var isMatchingComplete: Bool { mode == .matching && matchedCardIDs.count >= cards.count }

    var body: some View {
        NavigationStack {
            ZStack {
                StudyDeskTheme.backgroundPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        if mode == .matching {
                            matchingMode
                        } else if let current {
                            reviewHeader(current)
                            switch mode {
                            case .written:
                                writtenPracticeCard(current)
                            case .test:
                                testPracticeCard(current)
                            default:
                                reviewCard(current)
                            }
                            if showingAnswer { ratingGrid(current) }
                            if lastEvent != nil {
                                Button("Undo last review", systemImage: "arrow.uturn.backward", action: undoLast)
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            ReviewSummaryView(reviewed: reviewed, correctish: correctish, elapsed: Date().timeIntervalSince(startDate)) {
                                dismiss()
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 1120)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(current?.deck?.title ?? "Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit") {
                        if current == nil || reviewed == 0 || isMatchingComplete { dismiss() } else { exitConfirmation = true }
                    }
                }
            }
            .confirmationDialog("Exit review session?", isPresented: $exitConfirmation) {
                Button("Exit", role: .destructive) { dismiss() }
                Button("Keep Reviewing", role: .cancel) {}
            } message: {
                Text("Your completed review events have already been saved.")
            }
        }
        .onAppear {
            if let timerMinutes, remainingSeconds == nil {
                remainingSeconds = timerMinutes * 60
            }
        }
        .task(id: remainingSeconds) {
            guard remainingSeconds != nil else { return }
            while let remainingSeconds, remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    if !timerPaused {
                        self.remainingSeconds = max(0, remainingSeconds - 1)
                    }
                }
            }
        }
    }

    private func reviewHeader(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(mode.rawValue) · \(card.deck?.title ?? "Review")")
                        .font(.headline)
                    Text("\(index + 1) of \(cards.count) · \(max(cards.count - index - 1, 0)) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                timerBadge
            }
            ProgressView(value: progress)
                .tint(StudyDeskTheme.accentPrimary)
        }
    }

    @ViewBuilder
    private var timerBadge: some View {
        if let remainingSeconds {
            HStack(spacing: 8) {
                Label(timeLabel(remainingSeconds), systemImage: timerPaused ? "pause.circle" : "timer")
                    .font(.callout.weight(.semibold))
                Button(timerPaused ? "Resume" : "Pause") {
                    timerPaused.toggle()
                }
                .buttonStyle(.bordered)
            }
            .foregroundStyle(remainingSeconds == 0 ? .orange : .secondary)
        }
    }

    private func reviewCard(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Question")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(card.front)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let hint = card.hint, !hint.isEmpty, !showingAnswer {
                Label(hint, systemImage: "lightbulb")
                    .foregroundStyle(.secondary)
            }
            if showingAnswer {
                Divider()
                Text("Answer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(card.back)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                if let hint = card.hint, !hint.isEmpty {
                    StudyInfoBlock(title: "Hint", text: hint, systemImage: "lightbulb")
                }
                if let explanation = card.explanation, !explanation.isEmpty {
                    StudyInfoBlock(title: "Explanation", text: explanation, systemImage: "quote.bubble")
                }
                if !card.tags.isEmpty {
                    Text(card.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: { showingAnswer = true }) {
                    Label("Show Answer", systemImage: "eye")
                        .font(.headline)
                        .frame(minWidth: 180)
                        .padding(.vertical, 8)
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.space, modifiers: [])
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: showingAnswer ? 430 : 360, alignment: .topLeading)
        .deskCard()
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            if !showingAnswer { showingAnswer = true }
        }
        #if os(iOS)
        .gesture(DragGesture(minimumDistance: 40).onEnded { value in
            if value.translation.width < -40 && !showingAnswer { showingAnswer = true }
        })
        #endif
    }

    private func ratingGrid(_ card: Flashcard) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
            ratingButton(.again, color: .red, image: "arrow.counterclockwise", shortcut: "1")
            ratingButton(.hard, color: .orange, image: "tortoise", shortcut: "2")
            ratingButton(.good, color: .blue, image: "checkmark", shortcut: "3")
            ratingButton(.easy, color: .green, image: "bolt", shortcut: "4")
        }
    }

    private func ratingButton(_ rating: FlashcardRating, color: Color, image: String, shortcut: KeyEquivalent) -> some View {
        Button { apply(rating) } label: {
            HStack {
                Image(systemName: image)
                    .font(.title3)
                VStack(alignment: .leading) {
                    Text(rating.title).font(.headline)
                    if let current {
                        let next = scheduler.schedule(state: current.reviewState, rating: rating, reviewedAt: .now, calendar: .current)
                        Text(StudyIntervalFormatter.label(for: next.interval)).font(.caption)
                    }
                }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.22), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .keyboardShortcut(shortcut, modifiers: [])
    }

    private func writtenPracticeCard(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(card.front)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .lineSpacing(5)
                .textSelection(.enabled)

            Text("Your answer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $writtenAnswer)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 170)
                .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(StudyDeskTheme.borderSubtle) }

            if showingAnswer {
                Divider()
                Text("Saved answer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(card.back)
                    .font(.title3.weight(.semibold))
                    .lineSpacing(4)
                Text("Self-assess honestly. UniSaver does not mark written answers objectively when wording can vary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Compare with Saved Answer", systemImage: "text.magnifyingglass") {
                    showingAnswer = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(writtenAnswer.trimmedStudyText.isEmpty)
            }
        }
        .padding(32)
        .deskCard()
    }

    private func testPracticeCard(_ card: Flashcard) -> some View {
        let choices = answerChoices(for: card)
        return VStack(alignment: .leading, spacing: 18) {
            Text("Question")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(card.front)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .lineSpacing(5)
            if choices.count >= 2 {
                LazyVStack(spacing: 12) {
                    ForEach(choices, id: \.self) { choice in
                        Button {
                            guard !submittedChoice else { return }
                            selectedChoice = choice
                        } label: {
                            HStack {
                                Text(choice)
                                    .font(.title3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if selectedChoice == choice {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .padding(18)
                            .background(choiceBackground(choice, correct: card.back), in: RoundedRectangle(cornerRadius: 16))
                            .overlay { RoundedRectangle(cornerRadius: 16).stroke(choiceBorder(choice, correct: card.back), lineWidth: selectedChoice == choice ? 2 : 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if submittedChoice {
                    Text(selectedChoice == card.back ? "Correct. This was marked against the saved answer." : "Not this time. Review the saved answer below.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(selectedChoice == card.back ? .green : .orange)
                    Text(card.back)
                        .font(.title3.weight(.semibold))
                } else {
                    Button("Check Answer", systemImage: "checkmark.circle") {
                        submittedChoice = true
                        showingAnswer = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedChoice == nil)
                }
            } else {
                Text("Not enough cards in this session for multiple-choice options. Use written practice for this card.")
                    .foregroundStyle(.secondary)
                writtenPracticeCard(card)
            }
            if showingAnswer { ratingGrid(card) }
        }
        .padding(32)
        .deskCard()
    }

    private var matchingMode: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matching")
                        .font(.title.bold())
                    Text("\(matchedCardIDs.count) of \(cards.count) matched")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                timerBadge
                Button("Finish") {
                    finishMatching()
                }
                .buttonStyle(.borderedProminent)
                .disabled(matchedCardIDs.count != cards.count)
            }
            ProgressView(value: cards.isEmpty ? 1 : Double(matchedCardIDs.count) / Double(cards.count))
            if let matchMessage {
                Text(matchMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(matchMessage.contains("Correct") ? .green : .orange)
            }
            HStack(alignment: .top, spacing: 18) {
                matchingColumn(title: "Terms", cards: cards.filter { !matchedCardIDs.contains($0.id) }, text: \.front, isPrompt: true)
                matchingColumn(title: "Definitions", cards: cards.filter { !matchedCardIDs.contains($0.id) }.shuffled(), text: \.back, isPrompt: false)
            }
            if matchedCardIDs.count == cards.count {
                ReviewSummaryView(reviewed: reviewed, correctish: correctish, elapsed: Date().timeIntervalSince(startDate)) {
                    dismiss()
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 1120)
    }

    private func matchingColumn(title: String, cards: [Flashcard], text: KeyPath<Flashcard, String>, isPrompt: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ForEach(cards) { card in
                Button {
                    if isPrompt {
                        selectedMatchPrompt = card
                        matchMessage = "Now choose the matching definition."
                    } else if selectedMatchPrompt?.id == card.id {
                        matchedCardIDs.insert(card.id)
                        applyRatingOnly(.good, for: card)
                        correctish += 1
                        selectedMatchPrompt = nil
                        matchMessage = "Correct match."
                    } else {
                        matchMessage = "That definition belongs to another card. Try again."
                        if let selectedMatchPrompt {
                            applyRatingOnly(.hard, for: selectedMatchPrompt)
                        }
                    }
                } label: {
                    Text(card[keyPath: text])
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(selectedMatchPrompt?.id == card.id ? CourseColor.indigo.color.opacity(0.16) : StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(StudyDeskTheme.borderSubtle) }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func answerChoices(for card: Flashcard) -> [String] {
        var choices = cards.filter { $0.id != card.id }.map(\.back).filter { !$0.trimmedStudyText.isEmpty }.shuffled()
        choices = Array(choices.prefix(3))
        choices.append(card.back)
        return Array(Set(choices)).shuffled()
    }

    private func choiceBackground(_ choice: String, correct: String) -> Color {
        guard submittedChoice else {
            return selectedChoice == choice ? CourseColor.indigo.color.opacity(0.16) : StudyDeskTheme.surfacePrimary
        }
        if choice == correct { return .green.opacity(0.16) }
        if selectedChoice == choice { return .orange.opacity(0.16) }
        return StudyDeskTheme.surfacePrimary
    }

    private func choiceBorder(_ choice: String, correct: String) -> Color {
        if submittedChoice && choice == correct { return .green.opacity(0.55) }
        if selectedChoice == choice { return CourseColor.indigo.color.opacity(0.55) }
        return StudyDeskTheme.borderSubtle
    }

    private func apply(_ rating: FlashcardRating, advance: Bool = true) {
        guard let current else { return }
        applyRatingOnly(rating, for: current)
        if rating == .good || rating == .easy { correctish += 1 }
        if advance {
            showingAnswer = false
            writtenAnswer = ""
            selectedChoice = nil
            submittedChoice = false
            index += 1
        }
    }

    private func applyRatingOnly(_ rating: FlashcardRating, for card: Flashcard) {
        let previous = card.reviewState.dueDate
        let next = scheduler.schedule(state: card.reviewState, rating: rating, reviewedAt: .now, calendar: .current)
        card.reviewState = next
        card.updatedAt = .now
        let event = FlashcardReviewEvent(rating: rating, previousDueDate: previous, nextDueDate: next.dueDate, responseDuration: Date().timeIntervalSince(startDate) / Double(max(reviewed + 1, 1)), card: card)
        modelContext.insert(event)
        try? modelContext.save()
        lastEvent = event
        reviewed += 1
    }

    private func finishMatching() {
        index = cards.count
        selectedMatchPrompt = nil
    }

    private func timeLabel(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func undoLast() {
        guard let event = lastEvent, let card = event.card else { return }
        card.reviewState.dueDate = event.previousDueDate
        if event.rating == .good || event.rating == .easy { correctish = max(0, correctish - 1) }
        reviewed = max(0, reviewed - 1)
        modelContext.delete(event)
        try? modelContext.save()
        index = max(0, index - 1)
        lastEvent = nil
    }
}

private struct StudyInfoBlock: View {
    let title: String
    let text: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
        }
        .padding(12)
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ReviewSummaryView: View {
    let reviewed: Int
    let correctish: Int
    let elapsed: TimeInterval
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Review complete")
                .font(.title.bold())
            Text("\(reviewed) cards studied · \(accuracy)% strong recalls · \(Int(elapsed / 60))m")
                .foregroundStyle(.secondary)
            Button("Done", action: done)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .deskCard()
    }

    private var accuracy: Int {
        guard reviewed > 0 else { return 0 }
        return Int((Double(correctish) / Double(reviewed) * 100).rounded())
    }
}

struct QuizFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    let initialCourse: Course?
    let initialChapter: Chapter?
    let onSave: ((Quiz) -> Void)?
    @State private var step = 0
    @State private var title = ""
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var mode: QuizMode = .practice
    @State private var immediateFeedback = true
    @State private var shuffleQuestions = false
    @State private var shuffleAnswers = false
    @State private var bulkText = ""
    @State private var parsed: [ParsedQuizQuestion] = []
    @State private var manualPrompt = ""
    @State private var manualAnswer = ""
    @State private var manualExplanation = ""
    @State private var manualError: String?
    @State private var error: String?
    @State private var successMessage: String?
    private let accent = CourseColor.blueViolet.color

    init(initialCourse: Course? = nil, initialChapter: Chapter? = nil, onSave: ((Quiz) -> Void)? = nil) {
        self.initialCourse = initialCourse
        self.initialChapter = initialChapter
        self.onSave = onSave
        _selectedCourseID = State(initialValue: initialCourse?.id)
        _selectedChapterID = State(initialValue: initialChapter?.id)
    }

    private var selectedCourse: Course? { courses.first { $0.id == selectedCourseID } ?? initialCourse }
    private var selectedChapter: Chapter? { selectedCourse?.chapters.first { $0.id == selectedChapterID } ?? initialChapter }
    private var validQuestions: [ParsedQuizQuestion] { parsed.filter(\.isValid) }
    private var invalidQuestions: [ParsedQuizQuestion] { parsed.filter { !$0.isValid } }
    private var stepTitles: [String] { ["Informations", "Questions", "Vérification"] }

    var body: some View {
        CreationWindow(
            icon: "questionmark.app.fill",
            title: "Créer un quiz",
            subtitle: "Prépare une activité courte, liée à la bonne matière et prête à pratiquer.",
            accent: accent,
            closeAction: { dismiss() }
        ) {
            CreationStepIndicator(steps: stepTitles, currentStep: step, accent: accent)
                .padding(.bottom, 2)
            if step == 0 {
                detailsStep
            } else if step == 1 {
                questionsStep
            } else {
                quizReviewStep
            }
            if let error {
                CreationErrorText(message: error)
            }
            if let successMessage {
                Label(successMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } footer: {
            quizFooter
        }
        .frame(minWidth: 640, idealWidth: 760, maxWidth: 860, minHeight: 420, idealHeight: 590, maxHeight: 760)
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            CreationCard("Informations", subtitle: "Ces champs restent modifiables même si le quiz est lancé depuis un chapitre.") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Titre du quiz", text: $title)
                        .textFieldStyle(.roundedBorder)
                    if title.trimmedStudyText.isEmpty && step > 0 {
                        CreationErrorText(message: "Ajoute un titre avant de continuer.")
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            Text("Matière")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("Matière", selection: $selectedCourseID) {
                                Text("Aucune matière").tag(UUID?.none)
                                ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Chapitre")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("Chapitre", selection: $selectedChapterID) {
                                Text("Sans chapitre").tag(UUID?.none)
                                ForEach((selectedCourse?.chapters ?? []).sorted { $0.order < $1.order }) { Text($0.title).tag(Optional($0.id)) }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Mode")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("Mode", selection: $mode) {
                                ForEach(QuizMode.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    if let selectedCourse, let selectedChapter {
                        Label("Enregistré dans \(selectedCourse.name) · \(selectedChapter.title)", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let selectedCourse {
                        Label("Enregistré dans \(selectedCourse.name), sans chapitre.", systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            CreationCard("Options de pratique", subtitle: "Tu peux garder les réglages simples pour commencer.") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Correction immédiate en mode pratique", isOn: $immediateFeedback)
                    Toggle("Mélanger les questions", isOn: $shuffleQuestions)
                    Toggle("Mélanger les réponses", isOn: $shuffleAnswers)
                }
            }
        }
    }

    private var questionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            CreationCard("Ajouter une question", subtitle: "Commence par une réponse courte, puis complète ou modifie la liste.") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Question", text: $manualPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    TextField("Réponse attendue", text: $manualAnswer, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    TextField("Explication facultative", text: $manualExplanation, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("Ajouter la question", systemImage: "plus.circle") {
                            addManualQuestion()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let manualError {
                    CreationErrorText(message: manualError)
                }
            }

            CreationCard("Questions du quiz", subtitle: parsed.isEmpty ? "Aucune question pour l’instant." : "\(parsed.count) question(s), \(invalidQuestions.count) à corriger.") {
                if parsed.isEmpty {
                    Text("Ajoute une question manuellement ou colle une liste structurée ci-dessous.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach($parsed) { $question in
                            QuizQuestionDraftEditor(question: $question) {
                                parsed.removeAll { $0.id == question.id }
                            }
                        }
                    }
                }
            }

            CreationCard("Importer par collage", subtitle: "Optionnel : colle des blocs QUESTION pour créer plusieurs questions à la fois.") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Copier le format attendu", systemImage: "doc.on.doc") {
                        setClipboard(quizPrompt)
                    }
                    TextEditor(text: $bulkText)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 120)
                        .padding(6)
                        .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
                        }
                    HStack {
                        Text("Format : QUESTION, Type, Prompt, Correct, Explanation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Analyser", systemImage: "wand.and.stars") {
                            parseBulkQuestions()
                        }
                        .buttonStyle(.bordered)
                    }
                    if parsed.contains(where: { !$0.isValid }) {
                        CreationErrorText(message: "Certaines questions doivent être corrigées avant l’enregistrement.")
                    }
                }
            }
        }
    }

    private var quizReviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            CreationCard("Vérification", subtitle: "Aperçu de ce que l’étudiant verra au lancement du quiz.") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title.trimmedStudyText.isEmpty ? "Quiz sans titre" : title.trimmedStudyText)
                        .font(.title3.weight(.semibold))
                    Text("\(validQuestions.count) question(s) prêtes · \(invalidQuestions.count) à corriger")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let selectedCourse {
                        Text(selectedChapter.map { "\(selectedCourse.name) · \($0.title)" } ?? selectedCourse.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            CreationCard("Questions") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(parsed) { question in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(question.prompt.isEmpty ? "Question sans énoncé" : question.prompt)
                                .font(.headline)
                            Text("\(question.type.title) · \(question.correctAnswers.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !question.explanation.isEmpty {
                                Text(question.explanation)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            if !question.errors.isEmpty {
                                CreationErrorText(message: question.errors.joined(separator: " "))
                            }
                        }
                        .padding(.vertical, 6)
                        if question.id != parsed.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var quizFooter: some View {
        HStack(spacing: 12) {
            if step == 0 {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.bordered)
            } else {
                Button("Retour", systemImage: "chevron.left") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            if let blockingReason {
                Text(blockingReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            CreationPrimaryButton(
                title: step == 2 ? "Créer le quiz" : "Continuer",
                systemImage: step == 2 ? "checkmark.circle.fill" : "arrow.right",
                accent: accent,
                isDisabled: !canContinue,
                action: nextOrCreate
            )
        }
    }

    private var canContinue: Bool {
        if step == 0 { return !title.trimmedStudyText.isEmpty }
        if step == 1 { return !bulkText.trimmedStudyText.isEmpty || !parsed.isEmpty || (!manualPrompt.trimmedStudyText.isEmpty && !manualAnswer.trimmedStudyText.isEmpty) }
        if step == 2 { return !title.trimmedStudyText.isEmpty && !validQuestions.isEmpty && invalidQuestions.isEmpty }
        return false
    }

    private var blockingReason: String? {
        if step == 0 && title.trimmedStudyText.isEmpty {
            return "Titre requis."
        }
        if step == 1 && parsed.isEmpty && manualPrompt.trimmedStudyText.isEmpty && bulkText.trimmedStudyText.isEmpty {
            return "Ajoute au moins une question."
        }
        if step == 1 && !manualPrompt.trimmedStudyText.isEmpty && manualAnswer.trimmedStudyText.isEmpty {
            return "Réponse attendue requise."
        }
        if step == 2 && validQuestions.isEmpty {
            return "Aucune question valide."
        }
        if step == 2 && !invalidQuestions.isEmpty {
            return "Corrige les questions signalées."
        }
        return nil
    }

    private var quizPrompt: String {
        """
        Create practice questions for UniSaver.
        Course: \(selectedCourse?.name ?? "General Study")
        Chapter: \(selectedChapter?.title ?? "Not specified")
        Include Multiple Choice, Multiple Select, True/False, and Short Answer when appropriate.
        Output only this format:
        QUESTION
        Type: Multiple Choice
        Prompt: ...
        A: ...
        B: ...
        Correct: A
        Explanation: ...
        Tags: ...
        ---
        """
    }

    private func nextOrCreate() {
        error = nil
        successMessage = nil
        if step == 0 {
            guard !title.trimmedStudyText.isEmpty else {
                error = "Ajoute un titre avant de continuer."
                return
            }
            step = 1
        } else if step == 1 {
            if !manualPrompt.trimmedStudyText.isEmpty || !manualAnswer.trimmedStudyText.isEmpty {
                addManualQuestion()
            }
            if parsed.isEmpty && !bulkText.trimmedStudyText.isEmpty {
                parseBulkQuestions()
            }
            if parsed.isEmpty {
                error = "Ajoute une question ou colle des blocs QUESTION valides."
                return
            }
            step = 2
        } else {
            save()
        }
    }

    private func parseBulkQuestions() {
        let parsedQuestions = QuizBulkParser.parse(bulkText)
        if parsedQuestions.isEmpty {
            error = "Aucune question n’a pu être analysée. Vérifie le format QUESTION / Prompt / Correct."
            return
        }
        parsed.append(contentsOf: parsedQuestions)
        bulkText = ""
    }

    private func addManualQuestion() {
        manualError = nil
        let prompt = manualPrompt.trimmedStudyText
        let answer = manualAnswer.trimmedStudyText
        guard !prompt.isEmpty else {
            manualError = "Question is required."
            return
        }
        guard !answer.isEmpty else {
            manualError = "Expected answer is required."
            return
        }
        parsed.append(ParsedQuizQuestion(
            type: .shortAnswer,
            prompt: prompt,
            choices: [],
            correctAnswers: [answer],
            explanation: manualExplanation.trimmedStudyText,
            hint: nil,
            tags: selectedChapter.map { [$0.title] } ?? []
        ))
        manualPrompt = ""
        manualAnswer = ""
        manualExplanation = ""
    }

    private func save() {
        guard !validQuestions.isEmpty else {
            error = "Add at least one valid question before saving."
            return
        }
        guard validQuestions.count == parsed.count else {
            error = "Some questions are invalid. Review the red messages before saving."
            return
        }
        let quiz = Quiz(title: title.trimmedStudyText, mode: mode, course: selectedCourse, chapter: selectedChapter)
        modelContext.insert(quiz)
        for (index, question) in validQuestions.enumerated() {
            let model = QuizQuestion(prompt: question.prompt, type: question.type, choices: question.choices, correctAnswers: question.correctAnswers, explanation: question.explanation, hint: question.hint, position: index, tags: question.tags, quiz: quiz)
            modelContext.insert(model)
        }
        do {
            try modelContext.save()
            successMessage = "Quiz saved."
            onSave?(quiz)
            dismiss()
        } catch {
            modelContext.rollback()
            self.error = error.localizedDescription
        }
    }
}

struct QuizQuestionDraftEditor: View {
    @Binding var question: ParsedQuizQuestion
    let deleteAction: () -> Void
    @State private var choicesText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Picker("Type", selection: $question.type) {
                    ForEach(QuizQuestionType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .frame(maxWidth: 220)
                Spacer()
                Button("Supprimer", systemImage: "trash", role: .destructive, action: deleteAction)
                    .buttonStyle(.borderless)
            }
            TextField("Énoncé", text: $question.prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            if question.type == .multipleChoice || question.type == .multipleSelect {
                TextEditor(text: $choicesText)
                    .font(.callout)
                    .frame(minHeight: 72)
                    .padding(6)
                    .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
                    }
                Text("Une option par ligne.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Réponse(s) correcte(s), séparées par des virgules", text: correctAnswersBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            TextField("Explication", text: $question.explanation, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            if !question.errors.isEmpty {
                CreationErrorText(message: question.errors.joined(separator: " "))
            }
        }
        .padding(12)
        .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            choicesText = question.choices.joined(separator: "\n")
            validate()
        }
        .onChange(of: choicesText) { _, value in
            question.choices = value
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            validate()
        }
        .onChange(of: question.prompt) { _, _ in validate() }
        .onChange(of: question.type) { _, newValue in
            if newValue == .trueFalse {
                question.choices = ["True", "False"]
                choicesText = "True\nFalse"
            }
            validate()
        }
        .onChange(of: question.correctAnswers) { _, _ in validate() }
    }

    private var correctAnswersBinding: Binding<String> {
        Binding(
            get: { question.correctAnswers.joined(separator: ", ") },
            set: { value in
                question.correctAnswers = value
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                validate()
            }
        )
    }

    private func validate() {
        var errors: [String] = []
        if question.prompt.trimmedStudyText.isEmpty {
            errors.append("Énoncé requis.")
        }
        if question.correctAnswers.isEmpty {
            errors.append("Réponse correcte requise.")
        }
        if (question.type == .multipleChoice || question.type == .multipleSelect) && question.choices.count < 2 {
            errors.append("Ajoute au moins deux choix.")
        }
        question.errors = errors
    }
}

struct QuizPracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let quiz: Quiz
    @State private var index = 0
    @State private var answers: [String] = []
    @State private var showFeedback = false
    @State private var validationMessage: String?
    @State private var result: (score: Double, maximum: Double)?

    private var questions: [QuizQuestion] { quiz.questions.sorted { $0.position < $1.position } }
    private var current: QuizQuestion? { questions.indices.contains(index) ? questions[index] : nil }
    private var progressValue: Double { questions.isEmpty ? 0 : Double(index + 1) / Double(questions.count) }

    var body: some View {
        VStack(spacing: 0) {
            quizTopBar
            Divider()
            Group {
                if let result {
                    quizResultView(result)
                } else if let current {
                    questionWorkspace(current)
                } else {
                    EmptyStateView(title: "Quiz vide", message: "Ce quiz ne contient pas encore de question.", systemImage: "questionmark.app")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(StudyDeskTheme.backgroundPrimary)
        }
        .frame(minWidth: 820, idealWidth: 980, minHeight: 640, idealHeight: 760)
        .onAppear {
            ensureAnswerSlots()
        }
    }

    private var quizTopBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(quiz.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if result == nil {
                    Text("Question \(min(index + 1, max(questions.count, 1))) sur \(questions.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Résultat et corrections")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if result == nil {
                ProgressView(value: progressValue)
                    .frame(width: 160)
            }
            Button("Fermer", systemImage: "xmark") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(StudyDeskTheme.surfacePrimary)
    }

    private func questionWorkspace(_ question: QuizQuestion) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(question.type == .multipleSelect ? "Plusieurs réponses possibles" : question.type.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(StudyDeskTheme.accentPrimary)
                        Text(question.prompt)
                            .font(.system(size: 30, weight: .semibold, design: .default))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    answerArea(for: question)

                    if let validationMessage {
                        CreationErrorText(message: validationMessage)
                    }

                    if showFeedback {
                        StudyInfoBlock(
                            title: isCurrentCorrect ? "Correct" : "À revoir",
                            text: question.explanation.isEmpty ? "Aucune explication enregistrée pour cette question." : question.explanation,
                            systemImage: isCurrentCorrect ? "checkmark.circle" : "info.circle"
                        )
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            Divider()
            quizNavigationFooter
        }
    }

    @ViewBuilder
    private func answerArea(for question: QuizQuestion) -> some View {
        if question.type == .shortAnswer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ta réponse")
                    .font(.headline)
                TextField("Écris ta réponse ici", text: bindingForCurrentAnswer(), axis: .vertical)
                    .font(.title3)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)
            }
            .padding(18)
            .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            LazyVStack(spacing: 14) {
                ForEach(Array(question.choices.enumerated()), id: \.offset) { offset, choice in
                    QuizAnswerOptionCard(
                        index: offset,
                        text: choice,
                        isSelected: isChoiceSelected(choice, for: question),
                        allowsMultipleSelection: question.type == .multipleSelect,
                        action: { toggleChoice(choice, for: question) }
                    )
                }
            }
        }
    }

    private var quizNavigationFooter: some View {
        HStack(spacing: 12) {
            Button("Précédent", systemImage: "chevron.left") {
                movePrevious()
            }
            .buttonStyle(.bordered)
            .disabled(index == 0)

            Spacer()

            if current?.type == .multipleSelect {
                Text("Sélectionne toutes les réponses justes avant de continuer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            CreationPrimaryButton(
                title: index == questions.count - 1 ? "Envoyer" : "Suivant",
                systemImage: index == questions.count - 1 ? "checkmark.circle.fill" : "chevron.right",
                accent: StudyDeskTheme.accentPrimary,
                isDisabled: false,
                action: next
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(StudyDeskTheme.surfacePrimary)
    }

    private func quizResultView(_ result: (score: Double, maximum: Double)) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quiz terminé")
                        .font(.largeTitle.weight(.bold))
                    Text("Score \(Int(result.score)) / \(Int(result.maximum))")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                ForEach(Array(questions.enumerated()), id: \.element.id) { questionIndex, question in
                    QuizReviewCard(question: question, answer: answers.indices.contains(questionIndex) ? answers[questionIndex] : "")
                }

                HStack {
                    Button("Recommencer", systemImage: "arrow.counterclockwise") { reset() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Terminé") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private var isCurrentCorrect: Bool {
        guard let current else { return false }
        let correct = Set(current.correctAnswers.map(\.normalizedStudyKey))
        let submitted = Set(currentAnswer().split(separator: ",").map { String($0).normalizedStudyKey })
        return !currentAnswer().isEmpty && (correct.contains(currentAnswer().normalizedStudyKey) || submitted == correct)
    }

    private func bindingForCurrentAnswer() -> Binding<String> {
        Binding(get: { currentAnswer() }, set: { setAnswer($0) })
    }

    private func currentAnswer() -> String {
        answers.indices.contains(index) ? answers[index] : ""
    }

    private func setAnswer(_ value: String) {
        while answers.count <= index { answers.append("") }
        answers[index] = value
        validationMessage = nil
    }

    private func answer(_ value: String) {
        setAnswer(value)
        showFeedback = quiz.mode == .practice
    }

    private func selectedChoices() -> [String] {
        currentAnswer()
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isChoiceSelected(_ choice: String, for question: QuizQuestion) -> Bool {
        if question.type == .multipleSelect {
            return selectedChoices().contains { $0.normalizedStudyKey == choice.normalizedStudyKey }
        }
        return currentAnswer().normalizedStudyKey == choice.normalizedStudyKey
    }

    private func toggleChoice(_ choice: String, for question: QuizQuestion) {
        validationMessage = nil
        showFeedback = false
        if question.type == .multipleSelect {
            var selected = selectedChoices()
            if let existingIndex = selected.firstIndex(where: { $0.normalizedStudyKey == choice.normalizedStudyKey }) {
                selected.remove(at: existingIndex)
            } else {
                selected.append(choice)
            }
            setAnswer(selected.joined(separator: ", "))
        } else {
            answer(choice)
        }
    }

    private func movePrevious() {
        index = max(0, index - 1)
        showFeedback = false
        validationMessage = nil
        ensureAnswerSlots()
    }

    private func next() {
        guard !currentAnswer().trimmedStudyText.isEmpty else {
            validationMessage = "Choisis une réponse avant de continuer."
            return
        }
        if quiz.mode == .practice && !showFeedback {
            showFeedback = true
            return
        }
        if index >= questions.count - 1 {
            let score = QuizScoringService.score(questions: questions, answers: answers)
            let attempt = QuizAttempt(completedAt: .now, score: score.score, maximumScore: score.maximum, answers: answers, duration: 0, isCompleted: true, quiz: quiz)
            modelContext.insert(attempt)
            try? modelContext.save()
            result = score
        } else {
            index += 1
            showFeedback = false
            validationMessage = nil
            ensureAnswerSlots()
        }
    }

    private func reset() {
        index = 0
        answers = []
        showFeedback = false
        validationMessage = nil
        result = nil
        ensureAnswerSlots()
    }

    private func ensureAnswerSlots() {
        while answers.count < questions.count {
            answers.append("")
        }
    }
}

private struct QuizAnswerOptionCard: View {
    let index: Int
    let text: String
    let isSelected: Bool
    let allowsMultipleSelection: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: allowsMultipleSelection ? 7 : 18, style: .continuous)
                        .stroke(isSelected ? StudyDeskTheme.accentPrimary : StudyDeskTheme.borderSubtle, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: allowsMultipleSelection ? 7 : 18, style: .continuous)
                                .fill(isSelected ? StudyDeskTheme.accentPrimary : Color.clear)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Réponse \(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? StudyDeskTheme.accentPrimary.opacity(0.10) : StudyDeskTheme.surfacePrimary,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? StudyDeskTheme.accentPrimary : StudyDeskTheme.borderSubtle, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(true)
        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct QuizReviewCard: View {
    let question: QuizQuestion
    let answer: String

    private var isCorrect: Bool {
        let correct = Set(question.correctAnswers.map(\.normalizedStudyKey))
        let submitted = Set(answer.split(separator: ",").map { String($0).normalizedStudyKey })
        return !answer.isEmpty && (correct.contains(answer.normalizedStudyKey) || submitted == correct)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isCorrect ? "Correct" : "À revoir", systemImage: isCorrect ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.headline)
                .foregroundStyle(isCorrect ? .green : .orange)
            Text(question.prompt)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Ta réponse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(answer.isEmpty ? "Aucune réponse" : answer)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Réponse attendue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(question.correctAnswers.joined(separator: ", "))
            }
            if !question.explanation.isEmpty {
                Text(question.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }
}

private extension View {
    func studyReviewPresentation(cards: Binding<[Flashcard]>, mode: FlashcardStudyMode = .flashcards, timerMinutes: Int? = nil) -> some View {
        modifier(StudyReviewPresentationModifier(cards: cards, mode: mode, timerMinutes: timerMinutes))
    }
}

private struct StudyReviewPresentationModifier: ViewModifier {
    @Binding var cards: [Flashcard]
    let mode: FlashcardStudyMode
    let timerMinutes: Int?

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: Binding(get: { !cards.isEmpty }, set: { if !$0 { cards = [] } })) {
            FlashcardReviewView(cards: cards, mode: mode, timerMinutes: timerMinutes)
        }
        #else
        content.sheet(isPresented: Binding(get: { !cards.isEmpty }, set: { if !$0 { cards = [] } })) {
            FlashcardReviewView(cards: cards, mode: mode, timerMinutes: timerMinutes)
                .frame(minWidth: 920, minHeight: 760)
        }
        #endif
    }
}

private func setClipboard(_ value: String) {
    #if os(iOS)
    UIPasteboard.general.string = value
    #elseif os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    #endif
}

private func getClipboard() -> String? {
    #if os(iOS)
    UIPasteboard.general.string
    #elseif os(macOS)
    NSPasteboard.general.string(forType: .string)
    #else
    nil
    #endif
}

private extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init(
            get: { source.wrappedValue ?? fallback },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

private extension String {
    var trimmedStudyText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedStudyKey: String {
        trimmedStudyText.lowercased()
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var studyTags: [String] {
        split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
