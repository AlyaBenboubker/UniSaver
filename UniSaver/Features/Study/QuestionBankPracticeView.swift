import AppKit
import Combine
import SwiftUI
import SwiftData
import Observation

struct QuizPracticeView: View {
    let quiz: Quiz
    var body: some View { QuestionBankPracticeView(quiz: quiz) }
}

/// The regular sheet and its focus window observe the same reference state.
/// Copying State-backed values into a second hosting view leaves its UI stale.
@Observable @MainActor final class ExamLabPracticeState {
    var ledger: QuestionBankLedger? = nil
    var activeID: UUID? = nil
    var mode: BankPracticeMode = .mixed
    var tags: Set<String> = []
    var types: Set<QuizQuestionType> = Set(QuizQuestionType.allCases)
    var filter: String = "All questions"
    var count: Int = 10
    var shuffleAnswers: Bool = false
    var timed: Bool = false
    var minutes: Int = 45
    var error: String? = nil
    var notice: String? = nil
    var answerClock: RevisionAnswerClock = RevisionAnswerClock()
    var paused: Bool = false
    var now: Date = Date()
    var showCorrections: Bool = false
    var confirmingSubmit: Bool = false
    var focusWindow: NSWindow? = nil
    var presentation: QuizPracticeSession = QuizPracticeSession()
    var generationProvenance: RevisionGenerationRecord? = nil
}

struct QuestionBankPracticeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let quiz: Quiz
    var initialMode: BankPracticeMode = .mixed
    var resumeSessionID: UUID? = nil
    @State private var state = ExamLabPracticeState()
    private var ledger: QuestionBankLedger? {
        get { state.ledger }
        nonmutating set { state.ledger = newValue }
    }
    private var activeID: UUID? {
        get { state.activeID }
        nonmutating set { state.activeID = newValue }
    }
    private var mode: BankPracticeMode {
        get { state.mode }
        nonmutating set { state.mode = newValue }
    }
    private var tags: Set<String> {
        get { state.tags }
        nonmutating set { state.tags = newValue }
    }
    private var types: Set<QuizQuestionType> {
        get { state.types }
        nonmutating set { state.types = newValue }
    }
    private var filter: String {
        get { state.filter }
        nonmutating set { state.filter = newValue }
    }
    private var count: Int {
        get { state.count }
        nonmutating set { state.count = newValue }
    }
    private var shuffleAnswers: Bool {
        get { state.shuffleAnswers }
        nonmutating set { state.shuffleAnswers = newValue }
    }
    private var timed: Bool {
        get { state.timed }
        nonmutating set { state.timed = newValue }
    }
    private var minutes: Int {
        get { state.minutes }
        nonmutating set { state.minutes = newValue }
    }
    private var error: String? {
        get { state.error }
        nonmutating set { state.error = newValue }
    }
    private var notice: String? {
        get { state.notice }
        nonmutating set { state.notice = newValue }
    }
    private var answerClock: RevisionAnswerClock {
        get { state.answerClock }
        nonmutating set { state.answerClock = newValue }
    }
    private var paused: Bool {
        get { state.paused }
        nonmutating set { state.paused = newValue }
    }
    private var now: Date {
        get { state.now }
        nonmutating set { state.now = newValue }
    }
    private var showCorrections: Bool {
        get { state.showCorrections }
        nonmutating set { state.showCorrections = newValue }
    }
    private var confirmingSubmit: Bool {
        get { state.confirmingSubmit }
        nonmutating set { state.confirmingSubmit = newValue }
    }
    private var focusWindow: NSWindow? {
        get { state.focusWindow }
        nonmutating set { state.focusWindow = newValue }
    }
    private var presentation: QuizPracticeSession {
        get { state.presentation }
        nonmutating set { state.presentation = newValue }
    }

    private var session: BankPracticeSession? { ledger?.sessions.first { $0.id == activeID } }
    private var isMockFlow: Bool { initialMode == .teacherMock }
    private var topics: [String] { Array(Set(quiz.questions.flatMap(\.tags))).sorted() }
    private var candidates: [QuizQuestion] {
        guard let ledger else { return [] }
        return QuestionBankSessionService.candidates(quiz: quiz, ledger: ledger, tags: tags, type: nil, filter: filter, mode: mode, context: context)
            .filter { types.contains($0.type) }
    }
    private var current: BankQuestionRun? {
        guard let session, session.questions.indices.contains(session.index) else { return nil }
        return session.questions[session.index]
    }
    private var editable: Bool {
        guard let session, let current else { return false }
        return !paused && !session.isCompleted && !session.timeExpired(at: now) && (session.isTeacherMock || current.submittedAt == nil)
    }

    var body: some View {
        content
            .frame(minWidth: 820, idealWidth: 1040, minHeight: 640, idealHeight: 780)
            .onAppear(perform: load)
            .onChange(of: candidates.count) { _, available in
                if activeID == nil { count = min(count, max(1, available)) }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                now = date
                if session?.timeExpired(at: date) == true { answerClock.hide() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .uniSaverConversationAccountChanged)) { _ in
                ledger = nil; activeID = nil; answerClock.hide(); load()
            }
            .onDisappear { answerClock.hide(); persist(); focusWindow?.close(); focusWindow = nil }
            .interactiveDismissDisabled(error != nil)
            .confirmationDialog("Submit this mock exam?", isPresented: $state.confirmingSubmit) {
                Button("Submit exam and show corrections") { finish() }
                Button("Keep working", role: .cancel) {}
            } message: {
                Text("\(session?.questions.filter { $0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count ?? 0) unanswered questions will be recorded as skipped. Submitted answers cannot be changed.")
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(quiz.title).font(.title2.bold())
                    Text([quiz.course?.name, quiz.chapter?.title].compactMap { $0 }.joined(separator: " → ")).foregroundStyle(.secondary)
                }
                Spacer()
                if let session, !session.isCompleted {
                    Button(paused ? "Resume" : "Pause") { paused.toggle(); answerClock.pause(paused) }
                }
                Button(studyText(presentation.isFocused ? "Exit Focus Mode" : "Focus Mode")) { toggleFocus() }
                if presentation.isFocused { Button("Fullscreen") { focusWindow?.toggleFullScreen(nil) } }
                Button("Save and exit", systemImage: "xmark") { exit() }.accessibilityIdentifier("bankExit")
            }.padding(14)
            Divider()
            if let error { Text(error).foregroundStyle(.orange).padding(8).accessibilityIdentifier("bankError") }
            if let notice { Text(notice).foregroundStyle(.secondary).padding(8) }
            if let session {
                if session.isCompleted { summary(session) }
                else if let current { workspace(current, session: session) }
            } else if let ledger { setup(ledger) }
            else { ProgressView().padding() }
        }
        .frame(minWidth: 820, idealWidth: 1000, minHeight: 640, idealHeight: 780)
        .background(StudyDeskTheme.backgroundPrimary)
    }

    private func setup(_ ledger: QuestionBankLedger) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(isMockFlow ? "Teacher mock exam" : "Practice").font(.largeTitle.bold())
                if isMockFlow {
                    Text("Use this imported paper as a teacher mock. All wording, question order, types, option identifiers and marks are preserved. AI-generated practice stays separate.")
                    Text("\(quiz.questions.count) questions · \(quiz.questions.reduce(0) { $0 + $1.points }) marks")
                    Toggle("Timed attempt", isOn: $state.timed)
                    if timed { Stepper("Time limit: \(minutes) minutes", value: $state.minutes, in: 1...360) }
                    Text("Hints and corrections stay hidden until final submission. A timed attempt continues while you pause, leave this view or close the app. At expiry, answers lock; submit when ready to see corrections.").font(.callout).foregroundStyle(.secondary)
                    Text("Written answers use the saved model answer and any imported rubric. They need review and are excluded from the automatically scored total. AI feedback is provisional, never an official grade.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Picker("Activity", selection: $state.mode) {
                        Text("Practice").tag(BankPracticeMode.mixed)
                        Text("Retry mistakes").tag(BankPracticeMode.mistakes)
                    }.pickerStyle(.segmented).accessibilityIdentifier("bankMode")
                    if mode == .mistakes {
                        Text("Unresolved mistakes include immediate retries that were correct. Return after at least a day and answer without a hint to demonstrate later recall.").font(.callout).foregroundStyle(.secondary)
                    }
                    Stepper("Questions: \(count)", value: $state.count, in: 1...max(1, candidates.count))
                    Text("Question types").font(.headline)
                    ForEach(QuizQuestionType.allCases.filter { type in quiz.questions.contains { $0.type == type } }) { type in
                        Toggle(type.title, isOn: Binding(get: { types.contains(type) }, set: { if $0 { types.insert(type) } else { types.remove(type) } }))
                    }
                    DisclosureGroup("Topics · \(tags.count == 0 ? "All" : String(tags.count) + " selected")") {
                        ForEach(topics, id: \.self) { tag in
                            Toggle(tag, isOn: Binding(get: { tags.contains(tag) }, set: { if $0 { tags.insert(tag) } else { tags.remove(tag) } }))
                        }
                    }
                    DisclosureGroup("Practice settings") {
                        Picker("Progress", selection: $state.filter) {
                            ForEach(["All questions", "Unanswered", "Previously incorrect", "Due for review"], id: \.self) { Text($0).tag($0) }
                        }
                        Toggle("Shuffle answer options", isOn: $state.shuffleAnswers)
                        Text("Options keep their original identifiers, even when their display order changes.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(candidates.count) matching questions").foregroundStyle(.secondary)
                }
                Button(isMockFlow ? "Start mock exam" : mode == .mistakes ? "Retry mistakes" : "Start practice", systemImage: "play.fill") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMockFlow ? quiz.questions.isEmpty || !ExamLabService.canUseAsTeacherMock(quiz) : candidates.isEmpty)
                    .accessibilityIdentifier("bankStart")
                if !resumable(ledger).isEmpty {
                    Divider()
                    Text("Saved attempts").font(.headline)
                    ForEach(resumable(ledger)) { saved in
                        Button("Resume \(saved.mode.title) · \(saved.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(saved.questions.filter { !$0.answer.isEmpty }.count)/\(saved.questions.count) answered") { resume(saved.id) }
                            .accessibilityIdentifier("bankResume")
                    }
                }
                if let provenance = state.generationProvenance {
                    DisclosureGroup("AI generation sources and provenance") {
                        Text("Student-reviewed AI practice · \(provenance.preview.provider) · \(provenance.preview.model) · \(provenance.preview.generatedAt.formatted())").font(.caption)
                        Text(provenance.preview.difficultyReason).font(.caption)
                        ForEach(provenance.preview.sources) { Text($0.reference).font(.caption) }
                    }
                }
                Text("Answers save automatically to this Mac for the current account. Revision answers are not included in cloud sync.").font(.caption).foregroundStyle(.secondary)
            }.padding(32).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func resumable(_ ledger: QuestionBankLedger) -> [BankPracticeSession] {
        ledger.sessions.filter { !$0.isCompleted && $0.isTeacherMock == isMockFlow }
    }

    private func workspace(_ run: BankQuestionRun, session: BankPracticeSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(session.index + 1) / \(session.questions.count)")
                if session.isTeacherMock { Text("\(run.question.points) marks").foregroundStyle(.secondary) }
                Spacer()
                if let deadline = session.deadline {
                    let seconds = max(0, Int(deadline.timeIntervalSince(now)))
                    Text(seconds == 0 ? "Time expired · submit to review" : String(format: "%d:%02d remaining", seconds / 60, seconds % 60)).monospacedDigit().foregroundStyle(seconds == 0 ? .orange : .primary)
                }
                Button("Session setup") { leaveAttempt() }
            }.padding(18)
            if session.isTeacherMock {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(session.questions.enumerated()), id: \.element.id) { offset, question in
                            Button("\(offset + 1)" + (question.markedForReview == true ? " ⚑" : question.skipped == true ? " –" : !question.answer.isEmpty ? " ✓" : "")) { navigateTo(offset) }
                                .buttonStyle(.bordered).tint(offset == session.index ? .accentColor : .secondary)
                        }
                    }.padding(.horizontal, 18)
                }
            }
            if paused { Text("Answer timing paused" + (session.deadline == nil ? "" : " · The exam timer continues")).padding() }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(run.writtenResponse == true ? "Written response" : run.question.type == .multipleSelect ? "Select all that apply" : run.question.type.title).font(.headline).foregroundStyle(StudyDeskTheme.accentPrimary)
                    Text(run.question.prompt).font(.system(size: 25, weight: .medium)).lineSpacing(6).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier("bankPrompt")
                    answers(run).disabled(!editable)
                    if !session.hidesCorrections && run.submittedAt == nil, let hint = run.question.hint, !hint.isEmpty {
                        Button("Hint") { mutate { $0.questions[$0.index].hintsUsed = 1 } }.disabled(paused)
                        if (run.hintsUsed ?? 0) > 0 { Text(hint).font(.callout) }
                    }
                    if !session.hidesCorrections && run.submittedAt != nil {
                        feedback(run)
                        if run.correct == false { Button("Retry now", systemImage: "arrow.clockwise") { retryNow(run) }.accessibilityIdentifier("bankRetryNow") }
                        aiAssistance(run)
                    } else if run.savedAt != nil || run.submittedAt != nil {
                        Text("Answer saved. Corrections appear after exam submission.").foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: 900, alignment: .leading).padding(32).frame(maxWidth: .infinity)
            }
            Divider()
            HStack(spacing: 16) {
                Button("Previous") { navigateTo(session.index - 1) }.disabled(session.index == 0)
                Button(run.markedForReview == true ? "Unflag" : "Flag for review", systemImage: run.markedForReview == true ? "flag.fill" : "flag") {
                    mutate { $0.questions[$0.index].markedForReview = !($0.questions[$0.index].markedForReview ?? false) }
                }
                Spacer()
                if editable {
                    Button("Skip") { skip() }
                    Button(session.hidesCorrections ? "Save answer" : "Submit answer") { check() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("bankCheck")
                }
                if session.index < session.questions.count - 1 {
                    Button("Next") { navigateTo(session.index + 1) }
                        .disabled(!session.isTeacherMock && run.submittedAt == nil).accessibilityIdentifier("bankNext")
                }
                if session.isTeacherMock {
                    Button("Submit exam") { persist(); if error == nil { confirmingSubmit = true } }
                        .disabled(paused).accessibilityIdentifier("bankFinish")
                } else if session.index == session.questions.count - 1 {
                    Button("Finish session") { finish() }.disabled(!session.questions.allSatisfy { $0.submittedAt != nil }).accessibilityIdentifier("bankFinish")
                }
            }.padding(20)
        }
    }

    @ViewBuilder private func answers(_ run: BankQuestionRun) -> some View {
        if run.question.type == .shortAnswer {
            TextField(run.writtenResponse == true ? "Write your response" : "Enter your answer", text: Binding(get: { current?.answer ?? "" }, set: setAnswer), axis: .vertical)
                .font(.title3).textFieldStyle(.roundedBorder).lineLimit(3...12).accessibilityIdentifier("bankShortAnswer")
        } else {
            VStack(spacing: 12) {
                ForEach(run.displayChoices, id: \.index) { option in
                    let selected = run.question.type == .multipleSelect ? Set(run.answer.components(separatedBy: ",")).contains(option.key) : run.answer == option.key
                    let graded = session?.hidesCorrections == false && run.correct != nil
                    let correctOption = run.question.correctAnswers.map { QuizScoringService.optionKey($0).uppercased() }.contains(option.key.uppercased())
                    let state: Bool? = graded ? (correctOption ? true : selected ? false : nil) : nil
                    let tint: Color = state.map { $0 ? .green : .red } ?? StudyDeskTheme.accentPrimary
                    Button { select(option.key) } label: {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: state.map { $0 ? "checkmark.circle.fill" : "xmark.circle.fill" } ?? (selected ? "largecircle.fill.circle" : "circle")).foregroundStyle(tint)
                            Text(option.text).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }.font(.title3).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected || state != nil ? tint.opacity(0.10) : StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected || state != nil ? tint : StudyDeskTheme.borderSubtle))
                    }.buttonStyle(.plain).accessibilityLabel(option.text + (selected ? ", selected" : "")).accessibilityIdentifier("bankOption\(option.index)")
                }
            }
        }
    }

    private func feedback(_ run: BankQuestionRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(run.resultTitle, systemImage: run.needsWrittenReview ? "pencil.and.outline" : run.correct == true ? "checkmark.circle.fill" : "exclamationmark.circle").font(.headline)
                .foregroundStyle(run.correct == true ? .green : .orange)
            Text((run.writtenResponse == true ? "Model answer: " : "Correct answer: ") + run.correctAnswerText)
            if let rubric = run.question.rubric { Text("Rubric: " + rubric) }
            Text(run.question.explanation).lineLimit(4)
            if run.question.explanation.count > 320 { DisclosureGroup("Full explanation") { QuizExplanationView(explanation: run.question.explanation) } }
            if run.needsWrittenReview { Text("No official grade. Written marks are pending review; AI feedback is provisional.").font(.callout).foregroundStyle(.secondary) }
            if let issue = run.suspectedKeyIssue { Label("Suspected key issue · flagged for review; stored grading unchanged", systemImage: "flag.fill"); Text(issue) }
            if let explanation = run.coachingExplanation { Text(explanation).font(.callout) }
            if let feedback = run.aiFeedback { Text("Provisional AI feedback · not an official grade").font(.caption.bold()); Text(feedback).textSelection(.enabled) }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("bankFeedback")
    }

    private func aiAssistance(_ run: BankQuestionRun) -> some View {
        let expectedSessionID = activeID
        return QuizContextAssistance(question: run.question, submittedAnswer: run.answer, courseID: quiz.course?.id,
            courseName: quiz.course?.name ?? "", chapterTitle: quiz.chapter?.title ?? "", provisionalFeedback: run.needsWrittenReview,
            quizID: quiz.id, sessionID: activeID, onCoaching: { result in
                guard activeID == expectedSessionID else { return }
                mutate { session in
                    if let i = session.questions.firstIndex(where: { $0.id == run.id }) {
                        if run.needsWrittenReview { session.questions[i].aiFeedback = result.explanation }
                        else { session.questions[i].coachingExplanation = result.explanation }
                        session.questions[i].coachingSourceIDs = result.sourceIDs
                        session.questions[i].suspectedKeyIssue = result.suspectedKeyIssue
                        if result.suspectedKeyIssue != nil { session.questions[i].markedForReview = true }
                    }
                }
            }).id((activeID?.uuidString ?? "") + run.id.uuidString)
    }

    private func summary(_ session: BankPracticeSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Results").font(.largeTitle.bold())
                if session.objectivelyAvailable > 0 { Text("\(session.score) / \(session.objectivelyAvailable) automatically scored marks").font(.title) }
                if session.writtenMarks > 0 { Text("\(session.writtenMarks) written marks pending review · no official grade").foregroundStyle(.secondary) }
                if let coaching = session.coaching {
                    Text(coaching.summary).font(.headline).accessibilityIdentifier("coachSessionSummary")
                    if let recommendation = coaching.recommendation {
                        Text(recommendation.reason).font(.callout).foregroundStyle(.secondary)
                        Button("Start recommended practice") { startRecommended(recommendation) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("coachStartRecommended")
                        DisclosureGroup("Evidence and difficulty") {
                            Text("Based on this account’s saved course/chapter attempts; the next practice uses this bank. Immediate retries and pending written grades do not demonstrate independent success.").font(.caption)
                            Text(recommendation.difficultyReason).font(.caption)
                            ForEach(Array(coaching.evidence.enumerated()), id: \.offset) { _, evidence in
                                Text("Session \(evidence.sessionID.uuidString.prefix(8)) · question \(evidence.questionID.uuidString.prefix(8)) · \(evidence.submittedAt.formatted())").font(.caption)
                            }
                        }
                    }
                } else { Text(nextAction(session)).font(.headline) }
                ForEach(session.topicMistakes.keys.sorted(), id: \.self) { topic in Text("\(topic): \(session.topicMistakes[topic] ?? 0) mistakes or skipped questions") }
                HStack {
                    Button("Review corrections") { showCorrections.toggle() }.buttonStyle(.bordered)
                    Button("Retry mistakes") { retryMistakes() }.disabled(ledger?.mistakeIDs.isEmpty != false)
                    Button("Review later") {
                        if mutate({ $0.reviewAfterAt = Date().addingTimeInterval(86400) }) { notice = "Saved for tomorrow. In this bank, use Practice settings → Progress → Due for review." }
                    }
                }
                if session.immediateRetryOf != nil { Text("This was an immediate retry. A correct answer today does not clear tomorrow’s review.").foregroundStyle(.secondary) }
                Button("Choose another activity") { leaveAttempt() }
                if showCorrections {
                    ForEach(session.questions) { run in
                        Text(run.question.prompt).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text("Your answer: " + (run.answer.isEmpty ? "—" : QuizScoringService.displayAnswer(question: run.question.gradingQuestion(), answer: run.answer)))
                        if run.markedForReview == true { Label("Flagged for review", systemImage: "flag.fill") }
                        feedback(run)
                        if run.correct == false { Button("Retry now") { retryNow(run) } }
                        aiAssistance(run)
                    }
                }
            }.padding(32).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func nextAction(_ session: BankPracticeSession) -> String {
        if session.immediateRetryOf != nil { return "Next: return tomorrow for a recall check without looking at the correction." }
        if !session.topicMistakes.isEmpty { return "Next: retry the unresolved mistakes, then return tomorrow for a recall check." }
        if session.writtenMarks > 0 { return "Next: review the model answers and rubric. Ask your teacher for official written marks." }
        return "Next: choose Review later to schedule tomorrow’s recall check."
    }

    private func load() {
        guard ledger == nil else { return }
        do {
            ledger = try QuestionBankSessionService.load(quizID: quiz.id, context: context)
            state.generationProvenance = try RevisionGenerationService.provenance(quizID: quiz.id, context: context)
            count = min(count, max(1, quiz.questions.count))
            mode = isMockFlow ? .teacherMock : initialMode == .mistakes ? .mistakes : .mixed
            if let id = resumeSessionID, ledger?.sessions.contains(where: { $0.id == id }) == true { resume(id) }
        } catch { self.error = error.localizedDescription }
    }
    private func resume(_ id: UUID) {
        activeID = id; paused = false; answerClock.pause(false); _ = answerClock.take(); now = .now
        if session?.timeExpired(at: now) == false && session?.isCompleted == false { answerClock.show() } else { answerClock.hide() }
        showCorrections = session?.isCompleted == true
    }
    private func start() {
        guard var next = ledger else { return }
        do {
            let id: UUID
            if isMockFlow { id = try ExamLabService.startMock(quiz: quiz, ledger: &next, minutes: timed ? minutes : nil, context: context) }
            else {
                let selected = QuestionBankSessionService.select(candidates, mode: mode, count: count)
                id = try QuestionBankSessionService.start(quiz: quiz, ledger: &next, selected: selected, mode: mode, context: context, shuffleAnswers: shuffleAnswers)
            }
            ledger = next; resume(id); error = nil; notice = nil
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult private func mutate(_ change: (inout BankPracticeSession) throws -> Void) -> Bool {
        guard var next = ledger, let i = next.sessions.firstIndex(where: { $0.id == activeID }) else { return false }
        do { try change(&next.sessions[i]); ledger = try QuestionBankSessionService.save(next, quiz: quiz, context: context); error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func setAnswer(_ answer: String) {
        guard editable else { return }
        // Synchronous draft saves keep view changes and process exits safe.
        mutate { session in session.questions[session.index].answer = answer; session.questions[session.index].skipped = false; session.questions[session.index].savedAt = nil }
    }
    private func select(_ key: String) {
        guard let run = current, editable else { return }
        if run.question.type == .multipleSelect {
            var selected = Set(run.answer.components(separatedBy: ",").filter { !$0.isEmpty })
            if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
            setAnswer(selected.sorted().joined(separator: ","))
        } else { setAnswer(key) }
    }
    private func check() {
        guard editable else { return }
        persist()
        guard error == nil else { return }
        mutate { session in
            try QuestionBankSessionService.submit(&session.questions[session.index], mode: session.mode)
            session.questions[session.index].modelAnswerRevealed = !session.hidesCorrections
        }
    }
    private func skip() {
        guard editable else { return }
        persist()
        guard error == nil else { return }
        mutate { session in
            session.questions[session.index].skipped = true
            session.questions[session.index].answer = ""
            if !session.isTeacherMock { session.questions[session.index].submittedAt = .now; session.questions[session.index].modelAnswerRevealed = true }
        }
    }
    private func navigateTo(_ index: Int) {
        persist(); guard error == nil else { return }
        if mutate({ $0.index = max(0, min($0.questions.count - 1, index)) }) { _ = answerClock.take() }
    }
    private func finish() {
        persist(); guard error == nil else { return }
        if mutate({ session in
            try QuestionBankSessionService.finish(&session)
            for i in session.questions.indices { session.questions[i].modelAnswerRevealed = true }
        }) { answerClock.hide(); showCorrections = false }
    }
    private func startRecommended(_ recommendation: RevisionRecommendation) {
        persist(); guard error == nil else { return }
        do {
            let (source, saved, id) = try RevisionCoachingService.startRecommended(recommendation, context: context)
            guard source.id == quiz.id else { return }
            ledger = saved; resume(id); notice = recommendation.reason
        } catch { self.error = error.localizedDescription }
    }
    private func retryNow(_ run: BankQuestionRun) {
        persist(); guard error == nil, var next = ledger else { return }
        do {
            // Retry the exact immutable version whose correction was just seen.
            let id = try QuestionBankSessionService.start(quiz: quiz, ledger: &next, selected: [run.question.gradingQuestion()], mode: .mistakes, context: context, shuffleAnswers: shuffleAnswers, immediateRetryOf: activeID, snapshots: [run.id: run.question])
            ledger = next; resume(id); notice = "Immediate reinforcement — this question stays eligible for later review."
        } catch { self.error = error.localizedDescription }
    }
    private func retryMistakes() {
        persist(); guard error == nil else { return }
        activeID = nil; mode = .mistakes; tags = []; types = Set(QuizQuestionType.allCases); filter = "All questions"
        // A mock's retry is always practice, never a rewritten teacher paper.
        guard var next = ledger else { return }
        let selected = QuestionBankSessionService.select(candidates, mode: .mistakes, count: max(count, 1))
        do {
            let id = try QuestionBankSessionService.start(quiz: quiz, ledger: &next, selected: selected, mode: .mistakes, context: context, shuffleAnswers: shuffleAnswers)
            ledger = next; resume(id)
        } catch { self.error = error.localizedDescription }
    }
    private func persist() {
        guard session != nil else { return }
        let elapsed = answerClock.take()
        mutate { session in
            if !session.isCompleted && (session.isTeacherMock || session.questions[session.index].submittedAt == nil) {
                let remaining = session.timeLimitSeconds.map { max(0, $0 - session.questions.reduce(0) { $0 + $1.seconds }) } ?? elapsed
                session.questions[session.index].seconds += min(elapsed, remaining)
            }
        }
    }
    private func leaveAttempt() { persist(); if error == nil { answerClock.hide(); activeID = nil; notice = nil } }
    private func exit() { persist(); if error == nil { dismiss() } }
    private func toggleFocus() {
        if presentation.isFocused { focusWindow?.close(); focusWindow = nil; presentation.isFocused = false; return }
        presentation.returnWindow = NSApp.keyWindow
        let window = NSWindow(contentRect: NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1040, height: 780), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = quiz.title; window.isReleasedWhenClosed = false; window.delegate = presentation
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: QuizFocusWorkspace { AnyView(content.environment(\.modelContext, context)) })
        window.minSize = NSSize(width: 600, height: 440)
        focusWindow = window; presentation.isFocused = true; window.makeKeyAndOrderFront(nil)
    }
}
