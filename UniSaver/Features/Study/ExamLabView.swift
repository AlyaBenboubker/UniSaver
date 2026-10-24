import SwiftUI
import SwiftData

private enum ExamLabSection: String, CaseIterable, Identifiable {
    case practice = "Practice", mocks = "Mock exams", history = "History"
    var id: String { rawValue }
}
private struct ExamLabLaunch: Identifiable {
    let id = UUID()
    let quiz: Quiz
    var mode: BankPracticeMode = .mixed
    var sessionID: UUID? = nil
}

struct StudyStudioView: View {
    @Binding var quickAddTarget: QuickAddTarget?
    var body: some View { ExamLabView(quickAddTarget: $quickAddTarget) }
}

struct ExamLabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Quiz.updatedAt, order: .reverse) private var quizzes: [Quiz]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var section: ExamLabSection = .practice
    @State private var courseID: UUID?
    @State private var chapterID: UUID?
    @State private var launch: ExamLabLaunch?
    @State private var importing = false
    @State private var saved: [(quiz: Quiz, session: BankPracticeSession)] = []
    @State private var error: String?

    private var chapters: [Chapter] { courses.first { $0.id == courseID }?.chapters.sorted { $0.order < $1.order } ?? [] }
    private var banks: [Quiz] {
        quizzes.filter { !$0.isArchived && (courseID == nil || $0.course?.id == courseID) && (chapterID == nil || $0.chapter?.id == chapterID) }
    }
    private var teacherPapers: [Quiz] { banks.filter(ExamLabService.canUseAsTeacherMock) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Study activity", selection: $section) {
                    ForEach(ExamLabSection.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(20).accessibilityIdentifier("examLabNavigation")
                if section == .history {
                    RevisionHistoryView(onOpenSession: openSaved)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            Text(section == .practice ? "Build recall, one question at a time" : "Practise with the teacher’s paper").font(.largeTitle.bold())
                            Text(section == .practice ? "Submit, understand the correction, then return for a later recall check." : "Original wording, order and marks. Hints and corrections stay hidden until you submit.").foregroundStyle(.secondary)
                            filters
                            if let error { Text(error).foregroundStyle(.orange) }
                            savedAttempts
                            if section == .mocks {
                                if teacherPapers.isEmpty { Text("No imported papers in this selection. Import the teacher’s question blocks, then select the paper here.").foregroundStyle(.secondary) }
                                ForEach(teacherPapers) { bank in bankCard(bank, teacher: true) }
                                Button("Import teacher paper", systemImage: "square.and.arrow.down") { importing = true }
                                Text("Only existing imported papers appear here. AI-generated and authored practice remain in Practice. Choose timing inside the attempt setup.").font(.caption).foregroundStyle(.secondary)
                            } else {
                                let original = banks.filter { !ExamLabService.isAIGenerated($0) }
                                Text("Question banks").font(.title2.bold())
                                if original.isEmpty { Text("Import or create a question bank to start practising.").foregroundStyle(.secondary) }
                                ForEach(original) { bank in bankCard(bank, teacher: false) }
                                Button("Import or create questions", systemImage: "plus") { importing = true }
                                let generated = banks.filter(ExamLabService.isAIGenerated)
                                if !generated.isEmpty {
                                    Text("AI-generated practice").font(.title2.bold())
                                    Text("Separate from teacher papers. Check AI content and answer keys before relying on them.").font(.caption).foregroundStyle(.secondary)
                                    ForEach(generated) { bank in bankCard(bank, teacher: false) }
                                }
                                Divider()
                                NavigationLink("Flashcards and other study tools") { StudyStudioLibraryView(quickAddTarget: $quickAddTarget) }
                            }
                        }.padding(28).frame(maxWidth: 1120, alignment: .leading).frame(maxWidth: .infinity)
                    }
                }
            }.background(StudyDeskTheme.backgroundPrimary).navigationTitle("Study")
        }
        .sheet(item: $launch, onDismiss: reload) { target in
            QuestionBankPracticeView(quiz: target.quiz, initialMode: target.mode, resumeSessionID: target.sessionID)
        }
        .sheet(isPresented: $importing, onDismiss: reload) { QuizFormView(initialMode: section == .mocks ? .exam : .practice) }
        .onAppear(perform: reload)
        .onChange(of: notes.map(\.updatedAt)) { _, _ in reload() }
        .onChange(of: courseID) { _, _ in chapterID = nil }
        .onReceive(NotificationCenter.default.publisher(for: .uniSaverConversationAccountChanged)) { _ in launch = nil; reload() }
    }

    private var filters: some View {
        HStack {
            Picker("Course", selection: $courseID) {
                Text("All courses").tag(UUID?.none)
                ForEach(courses.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Chapter", selection: $chapterID) {
                Text("All chapters").tag(UUID?.none)
                ForEach(chapters) { Text($0.title).tag(Optional($0.id)) }
            }.disabled(courseID == nil)
        }
    }

    @ViewBuilder private var savedAttempts: some View {
        let attempts = saved.filter { !$0.session.isCompleted && $0.session.isTeacherMock == (section == .mocks) }
            .filter { item in (courseID == nil || item.quiz.course?.id == courseID) && (chapterID == nil || item.quiz.chapter?.id == chapterID) }
        if !attempts.isEmpty {
            Text("Continue an attempt").font(.title2.bold())
            ForEach(attempts, id: \.session.id) { item in
                Button {
                    launch = ExamLabLaunch(quiz: item.quiz, mode: item.session.mode, sessionID: item.session.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.quiz.title).font(.headline)
                            Text(item.session.mode.title + " · " + item.session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            Text("\(item.session.questions.filter { !$0.answer.isEmpty }.count)/\(item.session.questions.count) answered" + (item.session.timeExpired() ? " · time expired" : ""))
                        }
                        Spacer()
                        Label("Resume", systemImage: "play.fill")
                    }.padding(18).deskCard()
                }.buttonStyle(.plain).accessibilityIdentifier("examLabResume")
            }
        }
    }

    private func bankCard(_ bank: Quiz, teacher: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bank.title).font(.title3.bold())
                    Text([bank.course?.name, bank.chapter?.title].compactMap { $0 }.joined(separator: " → ")).foregroundStyle(.secondary)
                }
                Spacer()
                Text(teacher ? "Imported paper" : ExamLabService.isAIGenerated(bank) ? "AI practice" : "Question bank").font(.caption)
            }
            Text("\(bank.questions.count) questions · \(bank.questions.reduce(0) { $0 + $1.points }) marks · " + Set(bank.questions.map { $0.type.title }).sorted().joined(separator: ", ")).font(.callout)
            HStack {
                Button(teacher ? "Set up mock exam" : "Set up practice") { launch = ExamLabLaunch(quiz: bank, mode: teacher ? .teacherMock : .mixed) }.buttonStyle(.borderedProminent)
                if !teacher {
                    Button("Retry mistakes") { launch = ExamLabLaunch(quiz: bank, mode: .mistakes) }
                        .disabled(!saved.contains { $0.quiz.id == bank.id && !$0.session.questions.filter { $0.correct == false || $0.skipped == true }.isEmpty })
                }
            }
        }.padding(22).deskCard()
    }
    private func reload() {
        do {
            saved = try quizzes.filter { !$0.isArchived }.flatMap { quiz in
                try QuestionBankSessionService.load(quizID: quiz.id, context: context).sessions.map { (quiz, $0) }
            }.sorted { $0.session.startedAt > $1.session.startedAt }
            error = nil
        } catch { self.error = "Saved attempts could not be read. They have been preserved. " + error.localizedDescription }
    }
    private func openSaved(_ quizID: UUID, _ sessionID: UUID) {
        guard let item = saved.first(where: { $0.quiz.id == quizID && $0.session.id == sessionID }) else { error = "The source bank is no longer available. Its saved answers remain in History."; return }
        launch = ExamLabLaunch(quiz: item.quiz, mode: item.session.mode, sessionID: sessionID)
    }
}
