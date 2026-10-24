import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WebKit

#if os(iOS)
import PencilKit
#endif

struct ChapterListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var editingChapter: Chapter?
    @State private var deleteChapter: Chapter?
    @State private var showsDeleteConfirmation = false

    private var chapters: [Chapter] {
        course.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order }
    }

    private var unassignedSessions: [ClassSession] {
        course.sessions.filter { $0.chapter == nil }.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        List {
            if chapters.isEmpty {
                EmptyStateView(title: "No chapters", message: "Create the first chapter for this class.", systemImage: "list.number", actionTitle: "New Chapter") {
                    quickAddTarget = .chapter(course)
                }
            } else {
                ForEach(chapters) { chapter in
                    NavigationLink {
                        ChapterDetailView(chapter: chapter, quickAddTarget: $quickAddTarget)
                    } label: {
                        ChapterRow(chapter: chapter)
                    }
                    .swipeActions {
                        Button("Archive") {
                            chapter.isArchived = true
                            chapter.updatedAt = .now
                            try? modelContext.save()
                        }
                        .tint(.orange)
                        Button("Delete", role: .destructive) {
                            deleteChapter = chapter
                            showsDeleteConfirmation = true
                        }
                    }
                    .contextMenu {
                        Button("Edit") { editingChapter = chapter }
                        Button("Advance Status") {
                            chapter.status = chapter.status.advanced()
                            chapter.updatedAt = .now
                            try? modelContext.save()
                        }
                        Button("Archive") {
                            chapter.isArchived = true
                            chapter.updatedAt = .now
                            try? modelContext.save()
                        }
                    }
                }
                .onMove(perform: move)
            }
            if !unassignedSessions.isEmpty {
                Section("Sans chapitre") {
                    ForEach(unassignedSessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session, quickAddTarget: $quickAddTarget)
                        } label: {
                            SessionRow(session: session)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("New Chapter", systemImage: "plus") { quickAddTarget = .chapter(course) }
            }
        }
        .sheet(item: $editingChapter) { chapter in
            ChapterFormView(course: course, chapter: chapter)
        }
        .confirmationDialog("Delete chapter?", isPresented: $showsDeleteConfirmation) {
            Button("Delete Chapter", role: .destructive) {
                if let deleteChapter {
                    modelContext.delete(deleteChapter)
                    try? modelContext.save()
                    self.deleteChapter = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteChapter.map { AcademicValidationService.shouldPreferArchive(chapter: $0) } == true ? "This chapter has linked sessions. Archive is safer unless you are certain." : "This cannot be undone.")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = chapters
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, chapter) in reordered.enumerated() {
            chapter.order = index + 1
            chapter.number = index + 1
            chapter.updatedAt = .now
        }
        try? modelContext.save()
    }
}

struct ChapterRow: View {
    let chapter: Chapter

    var body: some View {
        HStack {
            Text("\(chapter.number)")
                .font(.headline.monospacedDigit())
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading) {
                Text(chapter.title).font(.headline)
                Text(chapter.status.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(chapter.status.progressWeight, format: .percent.precision(.fractionLength(0)))
                .foregroundStyle(.secondary)
        }
    }
}

struct ChapterDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var chapter: Chapter
    @Binding var quickAddTarget: QuickAddTarget?
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query(sort: \Quiz.updatedAt, order: .reverse) private var quizzes: [Quiz]
    @Query(sort: \StudyDeck.updatedAt, order: .reverse) private var decks: [StudyDeck]
    @Query(sort: \ExternalLearningActivity.updatedAt, order: .reverse) private var externalActivities: [ExternalLearningActivity]
    @Query(sort: \MathExercise.updatedAt, order: .reverse) private var mathExercises: [MathExercise]
    @Query(sort: \EssayAssignment.updatedAt, order: .reverse) private var essayAssignments: [EssayAssignment]
    @State private var editingChapter = false
    @State private var deleteConfirmation = false
    @State private var importingContent = false
    @State private var importingExercise = false
    @State private var managingExistingContent = false
    @State private var classifyingSessions = false
    @State private var revisingWithAI = false
    @State private var creatingEssayAssignment = false
    @State private var creatingQuiz = false
    @State private var creatingDeck = false
    @State private var importingFlashcards = false
    @State private var selectedQuiz: Quiz?
    @State private var selectedDeck: StudyDeck?
    @State private var editingTask: AcademicTask?
    @State private var deletingTask: AcademicTask?
    @State private var selectedMathExercise: MathExercise?
    @State private var selectedEssayAssignment: EssayAssignment?
    @State private var addingExternalActivity = false
    @State private var selectedExternalActivity: ExternalLearningActivity?

    private var sortedSessions: [ClassSession] {
        chapter.sessions.sorted { $0.startTime < $1.startTime }
    }

    private var unclassifiedCourseSessions: [ClassSession] {
        guard let course = chapter.course else { return [] }
        return course.sessions
            .filter { $0.chapter == nil }
            .sorted { $0.startTime < $1.startTime }
    }

    private var chapterResources: [AcademicResource] {
        resources.filter { $0.chapter?.id == chapter.id || $0.session?.chapter?.id == chapter.id }
    }

    private var chapterNotes: [StudyNote] {
        notes.filter { !QuestionBankSessionService.isProgressNote($0) && ($0.chapter?.id == chapter.id || $0.session?.chapter?.id == chapter.id || $0.resource?.chapter?.id == chapter.id) }
    }

    private var chapterRecordings: [CourseRecording] {
        recordings.filter { $0.chapter?.id == chapter.id || $0.session?.chapter?.id == chapter.id }
    }

    private var chapterTasks: [AcademicTask] {
        tasks.filter { ($0.chapter?.id == chapter.id || $0.session?.chapter?.id == chapter.id) && $0.status != .completed }
    }

    private var chapterExams: [Exam] {
        exams.filter { exam in
            exam.chapters.contains { $0.id == chapter.id }
        }
    }

    private var chapterQuizzes: [Quiz] {
        quizzes.filter { ($0.chapter?.id == chapter.id || $0.session?.chapter?.id == chapter.id) && !$0.isArchived }
    }

    private var chapterDecks: [StudyDeck] {
        decks.filter { ($0.chapter?.id == chapter.id || $0.session?.chapter?.id == chapter.id) && !$0.isArchived }
    }

    private var chapterExternalActivities: [ExternalLearningActivity] {
        externalActivities.filter { $0.chapter?.id == chapter.id }
    }

    private var chapterMathExercises: [MathExercise] {
        mathExercises.filter { $0.chapter?.id == chapter.id }
    }

    private var chapterEssayAssignments: [EssayAssignment] {
        essayAssignments.filter { $0.chapter?.id == chapter.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                chapterHeader
                sessionsSection
                resourcesAndNotesSection
                recordingsAndTasksSection
                studySection
            }
            .padding()
        }
        .navigationTitle(chapter.title)
        .toolbar {
            ToolbarItemGroup {
                Button("Edit", systemImage: "pencil") { editingChapter = true }
                Button("Delete", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
            }
        }
        .sheet(isPresented: $editingChapter) {
            if let course = chapter.course {
                ChapterFormView(course: course, chapter: chapter)
            }
        }
        .sheet(isPresented: $importingContent) {
            CourseContentImportSheet(initialCourse: chapter.course, initialChapter: chapter)
        }
        .sheet(isPresented: $importingExercise) {
            MathExerciseImportSheet(initialCourse: chapter.course, initialChapter: chapter)
        }
        .sheet(isPresented: $managingExistingContent) {
            ChapterContentAssociationSheet(chapter: chapter)
        }
        .sheet(isPresented: $classifyingSessions) {
            ChapterSessionClassifierSheet(chapter: chapter)
        }
        .sheet(isPresented: $revisingWithAI) {
            ChapterAIRevisionSheet(chapter: chapter)
        }
        .sheet(isPresented: $creatingEssayAssignment) {
            EssayAssignmentFormView(initialCourse: chapter.course, initialChapter: chapter)
        }
        .sheet(isPresented: $creatingQuiz) {
            QuizFormView(initialCourse: chapter.course, initialChapter: chapter) { quiz in
                selectedQuiz = quiz
            }
        }
        .sheet(isPresented: $creatingDeck) {
            StudyDeckFormView(initialCourse: chapter.course, initialChapter: chapter) { deck in
                selectedDeck = deck
            }
        }
        .sheet(isPresented: $importingFlashcards) {
            BulkFlashcardImportView(initialCourse: chapter.course, initialChapter: chapter)
        }
        .sheet(item: $editingTask) { task in
            TaskFormView(task: task, initialCourse: chapter.course, initialChapter: chapter)
        }
        .sheet(item: $selectedQuiz) { quiz in
            QuizPracticeView(quiz: quiz)
        }
        .sheet(item: $selectedMathExercise) { exercise in
            MathExerciseWorkspaceView(exercise: exercise)
        }
        .sheet(item: $selectedEssayAssignment) { assignment in
            EssayWorkspaceView(assignment: assignment)
        }
        .sheet(item: $selectedDeck) { deck in
            NavigationStack {
                DeckWorkspaceView(deck: deck)
            }
        }
        .sheet(isPresented: $addingExternalActivity) {
            ExternalLearningActivityFormView(initialCourse: chapter.course, initialChapter: chapter, existingActivities: externalActivities)
        }
        .sheet(item: $selectedExternalActivity) { activity in
            ExternalLearningActivityWorkspaceView(activity: activity)
        }
        .confirmationDialog("Delete chapter?", isPresented: $deleteConfirmation) {
            Button("Delete Chapter", role: .destructive) {
                modelContext.delete(chapter)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AcademicValidationService.shouldPreferArchive(chapter: chapter) ? "This chapter has linked sessions. Archive is safer unless you are certain." : "This cannot be undone.")
        }
        .confirmationDialog("Delete task?", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } })) {
            Button("Delete Task", role: .destructive) {
                if let deletingTask {
                    modelContext.delete(deletingTask)
                    try? modelContext.save()
                }
                deletingTask = nil
            }
            Button("Cancel", role: .cancel) { deletingTask = nil }
        } message: {
            Text("This removes the task from UniSaver. Course, chapter, and session data stay untouched.")
        }
        .onChange(of: chapter.status) { _, _ in
            chapter.updatedAt = .now
            try? modelContext.save()
        }
    }

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chapitre \(chapter.number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(chapter.status.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(StudyDeskTheme.surfaceTinted, in: Capsule())
            }
            Text(chapter.title)
                .font(.title2.weight(.bold))
            Text(chapter.chapterDescription.isEmpty ? "Aucune description pour l’instant." : chapter.chapterDescription)
                .foregroundStyle(.secondary)
            chapterSummaryBadges
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if chapter.status == .needsReview {
                Text("État de révision calculé depuis le statut du chapitre. Modifie-le si ce chapitre ne nécessite plus de revue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                primaryChapterAction
                Menu("Ajouter", systemImage: "plus.circle") {
                    Button("Importer du contenu", systemImage: "square.and.arrow.down") { importingContent = true }
                    Button("Nouvelle note", systemImage: "note.text") { quickAddTarget = .note(chapter.course, chapter, nil, nil) }
                    Button("Créer un quiz", systemImage: "questionmark.app") { creatingQuiz = true }
                    Button("Créer un deck", systemImage: "rectangle.stack.badge.plus") { creatingDeck = true }
                    Button("Importer des flashcards", systemImage: "text.badge.plus") { importingFlashcards = true }
                    Button("Importer un exercice", systemImage: "pencil.and.outline") { importingExercise = true }
                    Button("Question ouverte", systemImage: "text.book.closed") { creatingEssayAssignment = true }
                    Button("Activité Moodle ou Quizlet", systemImage: "link.badge.plus") { addingExternalActivity = true }
                    Divider()
                    Button("Lier une séance", systemImage: "link") { classifyingSessions = true }
                    Button("Affecter l’existant", systemImage: "tray.and.arrow.down") { managingExistingContent = true }
                }
                .menuStyle(.button)
                Button("Affecter l’existant", systemImage: "tray.and.arrow.down") {
                    managingExistingContent = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .deskCard()
    }

    @ViewBuilder
    private var primaryChapterAction: some View {
        if let quiz = chapterQuizzes.first {
            Button("Reprendre la révision", systemImage: "play.circle") {
                selectedQuiz = quiz
            }
            .buttonStyle(.borderedProminent)
        } else if hasChapterContent {
            Button("Réviser avec l’IA", systemImage: "brain.head.profile") {
                revisingWithAI = true
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button("Ajouter le premier contenu", systemImage: "plus") {
                importingContent = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var chapterContentCount: Int {
        chapterResources.count
            + chapterNotes.count
            + chapterQuizzes.count
            + chapterDecks.count
            + chapterExternalActivities.count
            + chapterMathExercises.count
            + chapterEssayAssignments.count
    }

    private var chapterStatusSystemImage: String {
        chapter.status == .needsReview ? "exclamationmark.circle" : "checkmark.circle"
    }

    private var chapterSummaryBadges: some View {
        HStack(spacing: 10) {
            Label("\(chapterContentCount) contenus", systemImage: "tray.full")
            Label("\(sortedSessions.count) séances liées", systemImage: "calendar")
            Label(chapter.status.title, systemImage: chapterStatusSystemImage)
        }
    }

    private var hasChapterContent: Bool {
        chapterContentCount > 0
    }

    private var sessionsSection: some View {
        chapterSection(title: "Séances", empty: "Aucune séance liée à ce chapitre.") {
            ForEach(sortedSessions) { session in
                NavigationLink {
                    SessionDetailView(session: session, quickAddTarget: $quickAddTarget)
                } label: {
                    SessionRow(session: session)
                }
                .buttonStyle(.plain)
                if session.id != sortedSessions.last?.id {
                    Divider()
                }
            }
            if !unclassifiedCourseSessions.isEmpty {
                Divider()
                DisclosureGroup("\(unclassifiedCourseSessions.count) séances à classer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UniSaver ne déduit pas le chapitre depuis la date seule. Sélectionne les séances à rattacher.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Associer en lot", systemImage: "checklist.checked") {
                            classifyingSessions = true
                        }
                    }
                }
            }
        } action: {
            HStack {
                Button("Ajouter une séance", systemImage: "calendar.badge.plus") {
                    quickAddTarget = .session(chapter.course, chapter)
                }
                Button("Lier une séance", systemImage: "link") {
                    classifyingSessions = true
                }
            }
        }
    }

    private var resourcesAndNotesSection: some View {
        chapterSection(title: "Documents et notes", empty: "Aucun document ni note lié à ce chapitre.") {
            ForEach(chapterResources) { resource in
                NavigationLink {
                    ResourceDetailView(resource: resource)
                } label: {
                    ResourceRow(resource: resource)
                }
                .buttonStyle(.plain)
            }
            ForEach(chapterNotes) { note in
                NavigationLink {
                    NoteEditorView(note: note)
                } label: {
                    Label(note.title, systemImage: "note.text")
                }
                .buttonStyle(.plain)
            }
        } action: {
            HStack {
                Button("Importer du contenu", systemImage: "square.and.arrow.down") { importingContent = true }
                Button("Nouvelle note", systemImage: "note.text") {
                    quickAddTarget = .note(chapter.course, chapter, nil, nil)
                }
            }
        }
    }

    private var recordingsAndTasksSection: some View {
        chapterSection(title: "Enregistrements, tâches et examens", empty: "Aucun enregistrement, tâche ou examen lié à ce chapitre.") {
            ForEach(chapterRecordings) { recording in
                RecordingRow(recording: recording)
            }
            ForEach(chapterTasks) { task in
                ChapterTaskRow(
                    task: task,
                    edit: { editingTask = task },
                    delete: { deletingTask = task }
                )
            }
            ForEach(chapterExams) { exam in
                HStack {
                    Label(exam.title, systemImage: "graduationcap")
                    Spacer()
                    Text(UniDateFormatters.dayMonth.string(from: exam.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } action: {
            HStack {
                Button("Enregistrer", systemImage: "waveform") {
                    quickAddTarget = .recording(chapter.course, chapter, nil)
                }
                Button("Nouvelle tâche", systemImage: "checklist") {
                    quickAddTarget = .task(chapter.course, chapter, nil)
                }
                Button("Affecter l’existant", systemImage: "tray.and.arrow.down") {
                    managingExistingContent = true
                }
            }
        }
    }

    private var studySection: some View {
        chapterSection(title: "Quiz, flashcards et activités", empty: "Aucun quiz, deck ou exercice lié à ce chapitre.") {
            ForEach(chapterEssayAssignments) { assignment in
                Button {
                    selectedEssayAssignment = assignment
                } label: {
                    EssayAssignmentRow(assignment: assignment)
                }
                .buttonStyle(.plain)
            }
            ForEach(chapterMathExercises) { exercise in
                Button {
                    selectedMathExercise = exercise
                } label: {
                    MathExerciseRow(exercise: exercise)
                }
                .buttonStyle(.plain)
            }
            ForEach(chapterExternalActivities) { activity in
                ExternalLearningActivityCard(activity: activity) {
                    selectedExternalActivity = activity
                }
            }
            ForEach(chapterQuizzes) { quiz in
                Button {
                    selectedQuiz = quiz
                } label: {
                    ChapterQuizRow(quiz: quiz)
                }
                .buttonStyle(.plain)
            }
            ForEach(chapterDecks) { deck in
                Button {
                    selectedDeck = deck
                } label: {
                    ChapterDeckRow(deck: deck)
                }
                .buttonStyle(.plain)
            }
            Text("Création à partir du contenu : aucun service IA n’est configuré ici. Le parcours manuel reste disponible et sauvegarde les vrais quiz/decks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } action: {
            HStack {
                Button("Créer un quiz", systemImage: "questionmark.app") { creatingQuiz = true }
                Button("Créer un deck", systemImage: "rectangle.stack.badge.plus") {
                    creatingDeck = true
                }
                Button("Importer un exercice", systemImage: "pencil.and.outline") {
                    importingExercise = true
                }
                Button("Question ouverte", systemImage: "text.book.closed") {
                    creatingEssayAssignment = true
                }
                Button("Importer des flashcards", systemImage: "text.badge.plus") {
                    importingFlashcards = true
                }
                Button("Ajouter une activité externe", systemImage: "link.badge.plus") {
                    addingExternalActivity = true
                }
            }
        }
    }

    private func chapterSection<Content: View, Action: View>(
        title: String,
        empty: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                action()
                    .buttonStyle(.bordered)
            }
            if sectionIsEmpty(title) {
                Text(empty)
                    .foregroundStyle(.secondary)
            } else {
                content()
            }
        }
        .padding()
        .deskCard()
    }

    private func sectionIsEmpty(_ title: String) -> Bool {
        switch title {
        case "Séances":
            sortedSessions.isEmpty && unclassifiedCourseSessions.isEmpty
        case "Documents et notes":
            chapterResources.isEmpty && chapterNotes.isEmpty
        case "Enregistrements, tâches et examens":
            chapterRecordings.isEmpty && chapterTasks.isEmpty && chapterExams.isEmpty
        case "Quiz, flashcards et activités":
            chapterQuizzes.isEmpty && chapterDecks.isEmpty && chapterExternalActivities.isEmpty && chapterMathExercises.isEmpty && chapterEssayAssignments.isEmpty
        default:
            true
        }
    }

    private func chapterMetric(_ value: String, _ label: String, _ systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(StudyDeskTheme.accentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ChapterSessionClassifierSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var chapter: Chapter
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var searchText = ""

    private var sessions: [ClassSession] {
        guard let course = chapter.course else { return [] }
        return course.sessions
            .filter { $0.chapter == nil || $0.chapter?.id == chapter.id }
            .sorted { $0.startTime < $1.startTime }
    }

    private var visibleSessions: [ClassSession] {
        sessions.filter { session in
            searchText.isEmpty
                || session.title.localizedCaseInsensitiveContains(searchText)
                || (session.room?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var groupedSessions: [(Date, [ClassSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleSessions) { session in
            calendar.startOfDay(for: session.startTime)
        }
        return grouped.keys.sorted().map { day in
            (day, grouped[day]?.sorted { $0.startTime < $1.startTime } ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sélectionne explicitement les séances à rattacher à ce chapitre. UniSaver ne déduit pas un chapitre à partir de la date seule.")
                            .foregroundStyle(.secondary)
                        TextField("Rechercher par titre ou salle", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Tout sélectionner") {
                                selectedSessionIDs.formUnion(visibleSessions.map(\.id))
                            }
                            Button("Désélectionner les visibles") {
                                selectedSessionIDs.subtract(visibleSessions.map(\.id))
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                ForEach(groupedSessions, id: \.0) { day, daySessions in
                    Section(UniDateFormatters.dayMonth.string(from: day)) {
                        ForEach(daySessions) { session in
                            Toggle(isOn: binding(for: session)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(session.title)
                                            .font(.headline)
                                        if session.chapter?.id == chapter.id {
                                            Text("déjà liée")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    Text("\(UniDateFormatters.interval(session.startTime, session.endTime))\(session.room.map { " · \($0)" } ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lier des séances")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        apply()
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedSessionIDs = Set(sessions.filter { $0.chapter?.id == chapter.id }.map(\.id))
            }
        }
        .frame(minWidth: 640, minHeight: 620)
    }

    private func binding(for session: ClassSession) -> Binding<Bool> {
        Binding {
            selectedSessionIDs.contains(session.id)
        } set: { isSelected in
            if isSelected {
                selectedSessionIDs.insert(session.id)
            } else {
                selectedSessionIDs.remove(session.id)
            }
        }
    }

    private func apply() {
        for session in sessions {
            if selectedSessionIDs.contains(session.id) {
                session.course = chapter.course ?? session.course
                session.chapter = chapter
            } else if session.chapter?.id == chapter.id {
                session.chapter = nil
            }
            session.updatedAt = .now
        }
        chapter.updatedAt = .now
        chapter.course?.updatedAt = .now
        try? modelContext.save()
    }
}

private struct ChapterContentAssociationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var chapter: Chapter
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query(sort: \Quiz.updatedAt, order: .reverse) private var quizzes: [Quiz]
    @Query(sort: \StudyDeck.updatedAt, order: .reverse) private var decks: [StudyDeck]
    @Query(sort: \ExternalLearningActivity.updatedAt, order: .reverse) private var externalActivities: [ExternalLearningActivity]
    @Query(sort: \MathExercise.updatedAt, order: .reverse) private var mathExercises: [MathExercise]
    @Query(sort: \EssayAssignment.updatedAt, order: .reverse) private var essayAssignments: [EssayAssignment]

    private var course: Course? {
        chapter.course
    }

    private var sessions: [ClassSession] {
        course?.sessions
            .filter { $0.chapter == nil || $0.chapter?.id == chapter.id }
            .sorted { $0.startTime < $1.startTime } ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Associe ou retire des éléments du chapitre sans supprimer les fichiers, notes ou activités. Les éléments sans matière seront rattachés à la matière de ce chapitre.")
                        .foregroundStyle(.secondary)
                }
                sessionSection
                resourceSection
                noteSection
                recordingSection
                taskSection
                examSection
                studySection
            }
            .navigationTitle("Affecter au chapitre")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 720)
    }

    private var sessionSection: some View {
        Section("Séances") {
            if sessions.isEmpty {
                Text("Aucune séance sans chapitre dans cette matière.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                associationRow(
                    title: session.title,
                    detail: "\(UniDateFormatters.dayMonth.string(from: session.startTime)) · \(UniDateFormatters.interval(session.startTime, session.endTime))",
                    isLinked: session.chapter?.id == chapter.id,
                    linkTitle: "Associer",
                    unlinkTitle: "Retirer"
                ) {
                    session.course = course ?? session.course
                    session.chapter = chapter
                    session.updatedAt = .now
                    save()
                } unlink: {
                    session.chapter = nil
                    session.updatedAt = .now
                    save()
                }
            }
        }
    }

    private var resourceSection: some View {
        Section("Documents") {
            ForEach(filtered(resources)) { resource in
                associationRow(title: resource.title, detail: resource.originalFileName, isLinked: resource.chapter?.id == chapter.id) {
                    resource.course = course ?? resource.course
                    resource.chapter = chapter
                    resource.updatedAt = .now
                    save()
                } unlink: {
                    resource.chapter = nil
                    resource.updatedAt = .now
                    save()
                }
            }
        }
    }

    private var noteSection: some View {
        Section("Notes") {
            ForEach(filtered(notes)) { note in
                associationRow(title: note.title, detail: note.resource?.title ?? "Note", isLinked: note.chapter?.id == chapter.id) {
                    note.course = course ?? note.course
                    note.chapter = chapter
                    note.updatedAt = .now
                    save()
                } unlink: {
                    note.chapter = nil
                    note.updatedAt = .now
                    save()
                }
            }
        }
    }

    private var recordingSection: some View {
        Section("Enregistrements") {
            ForEach(filtered(recordings)) { recording in
                associationRow(title: recording.title, detail: formattedDuration(recording.duration), isLinked: recording.chapter?.id == chapter.id) {
                    recording.course = course ?? recording.course
                    recording.chapter = chapter
                    recording.updatedAt = .now
                    save()
                } unlink: {
                    recording.chapter = nil
                    recording.updatedAt = .now
                    save()
                }
            }
        }
    }

    private var taskSection: some View {
        Section("Tâches") {
            ForEach(filtered(tasks)) { task in
                associationRow(title: task.title, detail: TaskStructureService.deadlineLabel(for: task), isLinked: task.chapter?.id == chapter.id) {
                    task.course = course ?? task.course
                    task.chapter = chapter
                    task.updatedAt = .now
                    save()
                } unlink: {
                    task.chapter = nil
                    task.updatedAt = .now
                    save()
                }
            }
        }
    }

    private var examSection: some View {
        Section("Examens") {
            ForEach(filtered(exams)) { exam in
                let linked = exam.chapters.contains { $0.id == chapter.id }
                associationRow(title: exam.title, detail: UniDateFormatters.dayMonth.string(from: exam.date), isLinked: linked) {
                    exam.course = course ?? exam.course
                    if !linked {
                        exam.chapters.append(chapter)
                    }
                    exam.updatedAt = .now
                    save()
                } unlink: {
                    exam.chapters.removeAll { $0.id == chapter.id }
                    exam.updatedAt = .now
                    save()
                }
            }
        }
    }

    private var studySection: some View {
        Group {
            Section("Quiz") {
                ForEach(filtered(quizzes)) { quiz in
                    associationRow(title: quiz.title, detail: "\(quiz.questions.count) questions", isLinked: quiz.chapter?.id == chapter.id) {
                        quiz.course = course ?? quiz.course
                        quiz.chapter = chapter
                        quiz.updatedAt = .now
                        save()
                    } unlink: {
                        quiz.chapter = nil
                        quiz.updatedAt = .now
                        save()
                    }
                }
            }
            Section("Flashcards") {
                ForEach(filtered(decks)) { deck in
                    associationRow(title: deck.title, detail: "\(deck.cards.count) cartes", isLinked: deck.chapter?.id == chapter.id) {
                        deck.course = course ?? deck.course
                        deck.chapter = chapter
                        deck.updatedAt = .now
                        save()
                    } unlink: {
                        deck.chapter = nil
                        deck.updatedAt = .now
                        save()
                    }
                }
            }
            Section("Exercices et activités externes") {
                ForEach(filtered(mathExercises)) { exercise in
                    associationRow(title: exercise.title, detail: exercise.sourceKind.title, isLinked: exercise.chapter?.id == chapter.id) {
                        exercise.course = course ?? exercise.course
                        exercise.chapter = chapter
                        exercise.updatedAt = .now
                        save()
                    } unlink: {
                        exercise.chapter = nil
                        exercise.updatedAt = .now
                        save()
                    }
                }
                ForEach(filtered(essayAssignments)) { assignment in
                    associationRow(title: assignment.title, detail: assignment.kind.title, isLinked: assignment.chapter?.id == chapter.id) {
                        assignment.course = course ?? assignment.course
                        assignment.chapter = chapter
                        assignment.updatedAt = .now
                        save()
                    } unlink: {
                        assignment.chapter = nil
                        assignment.updatedAt = .now
                        save()
                    }
                }
                ForEach(filtered(externalActivities)) { activity in
                    associationRow(title: activity.title, detail: "\(activity.platform.title) · \(activity.activityType.title)", isLinked: activity.chapter?.id == chapter.id) {
                        activity.course = course ?? activity.course
                        activity.chapter = chapter
                        activity.updatedAt = .now
                        save()
                    } unlink: {
                        activity.chapter = nil
                        activity.updatedAt = .now
                        save()
                    }
                }
            }
        }
    }

    private func associationRow(
        title: String,
        detail: String,
        isLinked: Bool,
        linkTitle: String = "Affecter",
        unlinkTitle: String = "Retirer",
        link: @escaping () -> Void,
        unlink: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLinked {
                Button(unlinkTitle, role: .destructive, action: unlink)
            } else {
                Button(linkTitle, action: link)
            }
        }
        .contentShape(Rectangle())
    }

    private func filtered(_ items: [AcademicResource]) -> [AcademicResource] {
        items.filter { isCandidate(course: $0.course, chapter: $0.chapter) }
    }

    private func filtered(_ items: [StudyNote]) -> [StudyNote] {
        items.filter { isCandidate(course: $0.course, chapter: $0.chapter) }
    }

    private func filtered(_ items: [CourseRecording]) -> [CourseRecording] {
        items.filter { isCandidate(course: $0.course, chapter: $0.chapter) }
    }

    private func filtered(_ items: [AcademicTask]) -> [AcademicTask] {
        items.filter { isCandidate(course: $0.course, chapter: $0.chapter) }
    }

    private func filtered(_ items: [Exam]) -> [Exam] {
        items.filter { exam in
            guard let course else { return exam.chapters.contains { $0.id == chapter.id } }
            return exam.course == nil || exam.course?.id == course.id || exam.chapters.contains { $0.id == chapter.id }
        }
    }

    private func filtered(_ items: [Quiz]) -> [Quiz] {
        items.filter { !$0.isArchived && isCandidate(course: $0.course, chapter: $0.chapter) }
    }

    private func filtered(_ items: [StudyDeck]) -> [StudyDeck] {
        items.filter { !$0.isArchived && isCandidate(course: $0.course, chapter: $0.chapter) }
    }

    private func filtered(_ items: [ExternalLearningActivity]) -> [ExternalLearningActivity] {
        items.filter { isCandidate(course: $0.course, chapter: $0.chapter) }
    }

    private func filtered(_ items: [MathExercise]) -> [MathExercise] {
        items.filter { isCandidate(course: $0.course, chapter: $0.chapter) }
    }

    private func filtered(_ items: [EssayAssignment]) -> [EssayAssignment] {
        items.filter { isCandidate(course: $0.course, chapter: $0.chapter) }
    }

    private func isCandidate(course itemCourse: Course?, chapter itemChapter: Chapter?) -> Bool {
        if itemChapter?.id == chapter.id {
            return true
        }
        guard let course else {
            return itemCourse == nil
        }
        return itemCourse == nil || itemCourse?.id == course.id
    }

    private func save() {
        chapter.updatedAt = .now
        chapter.course?.updatedAt = .now
        try? modelContext.save()
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ChapterAIRevisionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var chapter: Chapter
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \MathExercise.updatedAt, order: .reverse) private var exercises: [MathExercise]
    @State private var availableSources: [AIRevisionSource] = []
    @State private var selectedSourceIDs: Set<String> = []
    @State private var question = ""
    @State private var explanation = ""
    @State private var questionDrafts: [AIRevisionQuestionDraft] = []
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var savedQuiz: Quiz?
    @AppStorage(AIRevisionSettings.fundingModeKey) private var aiFundingModeRaw = AIRevisionFundingMode.personalKey.rawValue
    @AppStorage(AIRevisionSettings.activeProviderKey) private var activeAIProviderRaw = AIRevisionProviderID.openAI.rawValue
    @AppStorage("aiRevisionModel.openAI") private var openAIModel = AIRevisionProviderID.openAI.defaultModel
    @AppStorage("aiRevisionModel.claude") private var claudeModel = AIRevisionProviderID.claude.defaultModel
    @AppStorage("aiRevisionModel.gemini") private var geminiModel = AIRevisionProviderID.gemini.defaultModel
    private let fileStore = AcademicFileStore()

    private var course: Course? {
        chapter.course
    }

    private var selectedSources: [AIRevisionSource] {
        availableSources.filter { selectedSourceIDs.contains($0.id) && $0.hasUsableText }
    }

    private var providerStatus: AIRevisionProviderStatus {
        client.status()
    }

    private var client: AIRevisionAssistantClient {
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
            HSplitView {
                sourceSelectionPanel
                    .frame(minWidth: 300, idealWidth: 360)
                assistantPanel
                    .frame(minWidth: 540)
            }
            .navigationTitle("Réviser avec l’IA")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 720)
        .onAppear(perform: loadSources)
    }

    private var sourceSelectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(providerLabel, systemImage: "brain.head.profile")
                .font(.headline)
            Picker("Mode", selection: $aiFundingModeRaw) {
                Text("IA incluse").tag(AIRevisionFundingMode.included.rawValue)
                Text("Ma propre clé").tag(AIRevisionFundingMode.personalKey.rawValue)
            }
            .pickerStyle(.segmented)
            if aiSettings.fundingMode == .personalKey {
                Picker("Fournisseur", selection: $activeAIProviderRaw) {
                    ForEach(AIRevisionProviderID.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
            Text(client.paymentDisclosure())
                .font(.caption.weight(.semibold))
                .foregroundStyle(aiSettings.fundingMode == .included ? .orange : .secondary)
            Text("UniSaver envoie seulement les sources cochées ci-dessous au fournisseur configuré. Les documents sans texte fiable ne sont pas transmis.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !selectedSources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aperçu envoyé")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(selectedSources.prefix(3)) { source in
                        Text("\(source.sourceReference) · \(source.text.prefix(180))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    if selectedSources.count > 3 {
                        Text("+ \(selectedSources.count - 3) autre(s) source(s) sélectionnée(s). Chaque source est limitée avant envoi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
            }
            if case .notConfigured = providerStatus {
                Button("Ouvrir Settings", systemImage: "gearshape") {
                    NotificationCenter.default.post(name: .selectAppSection, object: AppSection.settings)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(availableSources.map(\.id), id: \.self) { sourceID in
                        if let source = availableSources.first(where: { $0.id == sourceID }) {
                            AIRevisionSourceSelectionRow(source: source, selectedSourceIDs: $selectedSourceIDs)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(StudyDeskTheme.backgroundSecondary)
    }

    private var assistantPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(course?.name ?? "Matière") · \(chapter.title)")
                    Text("Sources utilisées : \(selectedSourceLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.headline)

                TextField("Demande une explication sur un passage ou une notion", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(isWorking ? "Analyse..." : "Expliquer avec sources", systemImage: "text.magnifyingglass") {
                        Task { await explain() }
                    }
                    .disabled(!canAsk)
                    Button(isWorking ? "Préparation..." : "Préparer 3 questions", systemImage: "questionmark.app") {
                        Task { await generateQuestions() }
                    }
                    .disabled(!canGenerate)
                    if !questionDrafts.isEmpty {
                        Button("Enregistrer le quiz", systemImage: "checkmark.seal") {
                            saveQuiz()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .buttonStyle(.bordered)

                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if !explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Explication")
                            .font(.headline)
                        Text(explanation)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .deskCard()
                }

                if !questionDrafts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Brouillons de questions")
                            .font(.headline)
                        Text("Corrige les questions avant sauvegarde. L’IA ne modifie pas seule les quiz, cartes, notes ou dates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach($questionDrafts) { $draft in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Question", text: $draft.prompt, axis: .vertical)
                                TextField("Réponse attendue", text: $draft.expectedAnswer, axis: .vertical)
                                TextField("Explication", text: $draft.explanation, axis: .vertical)
                                TextField("Source", text: $draft.sourceReference)
                            }
                            .textFieldStyle(.roundedBorder)
                            .padding()
                            .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                    .deskCard()
                }

                if let savedQuiz {
                    NavigationLink {
                        QuizPracticeView(quiz: savedQuiz)
                    } label: {
                        Label("Ouvrir le quiz enregistré : \(savedQuiz.title)", systemImage: "questionmark.app")
                    }
                }
            }
            .padding()
        }
        .background(StudyDeskTheme.backgroundPrimary)
    }

    private var providerLabel: String {
        switch providerStatus {
        case .notConfigured:
            return aiSettings.fundingMode == .included ? "IA incluse bientôt disponible" : "IA non configurée"
        case .ready:
            return "IA prête · \(aiSettings.providerName) · \(aiSettings.model())"
        case .error(let message):
            return "Erreur IA · \(message)"
        }
    }

    private var selectedSourceLabel: String {
        let label = selectedSources.map(\.sourceReference).joined(separator: ", ")
        return label.isEmpty ? "aucune" : label
    }

    private var canAsk: Bool {
        if case .ready = providerStatus {
            return !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedSources.isEmpty && !isWorking
        }
        return false
    }

    private var canGenerate: Bool {
        if case .ready = providerStatus {
            return !selectedSources.isEmpty && !isWorking
        }
        return false
    }

    private func loadSources() {
        let chapterID = chapter.id
        let chapterNotes = notes
            .filter { $0.chapter?.id == chapterID || $0.resource?.chapter?.id == chapterID || $0.session?.chapter?.id == chapterID }
            .map { note in
                AIRevisionSource(
                    id: "note-\(note.id.uuidString)",
                    title: note.title,
                    kind: .note,
                    detail: "Note · \(UniDateFormatters.dayMonth.string(from: note.updatedAt))",
                    text: note.body,
                    sourceReference: "Note: \(note.title)"
                )
            }

        let chapterResources = resources
            .filter { $0.chapter?.id == chapterID || $0.session?.chapter?.id == chapterID }
            .map(resourceSource)

        let chapterExercises = exercises
            .filter { $0.chapter?.id == chapterID }
            .map { exercise in
                AIRevisionSource(
                    id: "exercise-\(exercise.id.uuidString)",
                    title: exercise.title,
                    kind: .exercise,
                    detail: "Exercice · \(exercise.recognitionStatus.title)",
                    text: [exercise.recognizedPrompt, exercise.professorSolution].filter { !$0.isEmpty }.joined(separator: "\n\nCorrigé fourni:\n"),
                    sourceReference: "Exercice: \(exercise.title)"
                )
            }

        let sessionSources = chapter.sessions.sorted { $0.startTime < $1.startTime }.map { session in
            AIRevisionSource(
                id: "session-\(session.id.uuidString)",
                title: session.title,
                kind: .session,
                detail: "Séance · \(UniDateFormatters.dayMonth.string(from: session.startTime))",
                text: [session.sessionDescription, session.learningObjectives.joined(separator: "\n"), session.importantConcepts.joined(separator: "\n")]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n"),
                sourceReference: "Séance: \(session.title)"
            )
        }

        availableSources = chapterNotes + chapterResources + chapterExercises + sessionSources
        selectedSourceIDs = Set(availableSources.filter(\.hasUsableText).prefix(2).map(\.id))
    }

    private func resourceSource(_ resource: AcademicResource) -> AIRevisionSource {
        let text = extractText(from: resource)
        let pageReference = resource.effectiveResourceKind == .pdf ? "page \(max(resource.lastPage, 1))" : resource.effectiveResourceKindTitle
        return AIRevisionSource(
            id: "resource-\(resource.id.uuidString)",
            title: resource.title,
            kind: .resource,
            detail: "\(resource.effectiveResourceKindTitle) · \(pageReference)",
            text: text,
            sourceReference: "Document: \(resource.title), \(pageReference)"
        )
    }

    private func extractText(from resource: AcademicResource) -> String {
        guard let url = try? fileStore.url(for: resource.storedRelativePath) else { return "" }
        if resource.effectiveResourceKind == .pdf {
            return PDFDocument(url: url)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if ["txt", "md", "rtf"].contains(resource.fileExtension.localizedLowercase),
           let data = try? Data(contentsOf: url),
           let string = String(data: data, encoding: .utf8) {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func explain() async {
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        do {
            explanation = try await client.explain(
                question: question,
                courseName: course?.name ?? "Matière",
                chapterTitle: chapter.title,
                sources: selectedSources
            )
            statusMessage = "Réponse reçue depuis \(aiSettings.providerName). Vérifie les sources citées avant de l’utiliser."
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func generateQuestions() async {
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        do {
            questionDrafts = try await client.generateQuestions(
                courseName: course?.name ?? "Matière",
                chapterTitle: chapter.title,
                sources: selectedSources
            )
            statusMessage = "Brouillons générés. Rien n’est enregistré avant ta confirmation."
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func saveQuiz() {
        let cleanDrafts = questionDrafts.filter { !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !cleanDrafts.isEmpty else {
            errorMessage = "Ajoute au moins une question avant d’enregistrer."
            return
        }
        let quiz = Quiz(
            title: "Révision IA — \(chapter.title)",
            quizDescription: "Brouillon IA vérifié par l’étudiant. Sources: \(selectedSources.map(\.sourceReference).joined(separator: ", "))",
            mode: .practice,
            course: course,
            chapter: chapter
        )
        modelContext.insert(quiz)
        for (index, draft) in cleanDrafts.enumerated() {
            let question = QuizQuestion(
                prompt: draft.prompt,
                type: .shortAnswer,
                correctAnswers: [draft.expectedAnswer],
                explanation: [draft.explanation, "Source: \(draft.sourceReference)"].filter { !$0.isEmpty }.joined(separator: "\n"),
                position: index,
                tags: ["ai-draft"],
                quiz: quiz
            )
            modelContext.insert(question)
        }
        do {
            try modelContext.save()
            savedQuiz = quiz
            statusMessage = "Quiz enregistré dans ce chapitre et disponible dans Study."
        } catch {
            errorMessage = "Le quiz n’a pas été enregistré : \(error.localizedDescription)"
        }
    }
}

private struct AIRevisionSourceSelectionRow: View {
    let source: AIRevisionSource
    @Binding var selectedSourceIDs: Set<String>

    var body: some View {
        Toggle(isOn: isSelected) {
            VStack(alignment: .leading, spacing: 3) {
                Text(source.title)
                    .font(.subheadline.weight(.semibold))
                Text(source.hasUsableText ? source.detail : "\(source.detail) · texte inexploitable")
                    .font(.caption)
                    .foregroundStyle(source.hasUsableText ? Color.secondary : Color.orange)
            }
        }
        .disabled(!source.hasUsableText)
    }

    private var isSelected: Binding<Bool> {
        Binding {
            selectedSourceIDs.contains(source.id)
        } set: { isSelected in
            if isSelected {
                selectedSourceIDs.insert(source.id)
            } else {
                selectedSourceIDs.remove(source.id)
            }
        }
    }
}

private struct ChapterQuizRow: View {
    let quiz: Quiz

    private var bestScore: String {
        let completed = quiz.attempts.filter { $0.isCompleted && $0.maximumScore > 0 }
        guard let best = completed.max(by: { ($0.score / $0.maximumScore) < ($1.score / $1.maximumScore) }) else {
            return "Aucune tentative"
        }
        return "\(Int((best.score / best.maximumScore * 100).rounded()))%"
    }

    var body: some View {
        HStack {
            Label(quiz.title, systemImage: "questionmark.app")
            Spacer()
            Text("\(quiz.questions.count) questions · \(bestScore)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct ChapterDeckRow: View {
    let deck: StudyDeck

    private var dueCount: Int {
        deck.cards.filter { $0.reviewState.dueDate <= .now }.count
    }

    var body: some View {
        HStack {
            Label(deck.title, systemImage: "rectangle.stack")
            Spacer()
            Text("\(deck.cards.count) cartes · \(dueCount) à revoir")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct ChapterTaskRow: View {
    let task: AcademicTask
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                    Text("\(task.priority.title) · \(task.status.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "checklist")
                    .foregroundStyle(task.status == .completed ? .green : CourseColor.amber.color)
            }
            Spacer()
            Text(TaskStructureService.deadlineLabel(for: task))
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu("Task Actions", systemImage: "ellipsis.circle") {
                Button("Edit", systemImage: "pencil", action: edit)
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
            .labelStyle(.iconOnly)
            .menuStyle(.button)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
    }
}

struct EssayAssignmentRow: View {
    let assignment: EssayAssignment

    private var latestSubmission: EssaySubmission? {
        assignment.submissions.sorted { $0.submittedAt > $1.submittedAt }.first
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .foregroundStyle(.indigo)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(assignment.kind.title) · \(assignment.status.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(latestSubmission.map { "\($0.wordCount) mots" } ?? "\(essayWordCount(assignment.draftBody)) mots")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EssayAssignmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]

    let initialCourse: Course?
    let initialChapter: Chapter?

    @State private var title = ""
    @State private var kind: EssayAssignmentKind = .openQuestion
    @State private var mode: EssayWorkMode = .training
    @State private var prompt = ""
    @State private var promptNotes = ""
    @State private var expectedWordCount = ""
    @State private var durationMinutes = ""
    @State private var usesTimer = false
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var criteria = ""
    @State private var sourcesAllowed = false
    @State private var selectedResourceIDs: Set<UUID> = []
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var selectedPromptURL: URL?
    @State private var errorMessage: String?
    @State private var fileImporterPresented = false
    @State private var isSaving = false

    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private func uiText(_ french: String, _ english: String) -> String {
        appLanguage == .english ? english : french
    }

    private var candidateResources: [AcademicResource] {
        resources.filter { resource in
            if let initialChapter {
                return resource.chapter?.id == initialChapter.id || resource.session?.chapter?.id == initialChapter.id
            }
            if let initialCourse {
                return resource.course?.id == initialCourse.id
            }
            return false
        }
    }

    private var candidateNotes: [StudyNote] {
        notes.filter { note in
            guard !QuestionBankSessionService.isProgressNote(note) else { return false }
            if let initialChapter {
                return note.chapter?.id == initialChapter.id || note.session?.chapter?.id == initialChapter.id || note.resource?.chapter?.id == initialChapter.id
            }
            if let initialCourse {
                return note.course?.id == initialCourse.id
            }
            return false
        }
    }

    var body: some View {
        CreationWindow(
            icon: "text.book.closed",
            title: uiText("Nouvelle question ouverte", "New Open Question"),
            subtitle: uiText("Prépare la consigne, le cadre de travail et les sources autorisées avant de commencer.", "Prepare the prompt, working rules, and allowed sources before starting."),
            accent: CourseColor.rose.color,
            closeAction: { dismiss() }
        ) {
            CreationCard(uiText("Consigne", "Prompt")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(uiText("Titre", "Title"), text: $title)
                        .textFieldStyle(.roundedBorder)
                    Picker(uiText("Type", "Type"), selection: $kind) {
                        ForEach(EssayAssignmentKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(uiText("Mode", "Mode"), selection: $mode) {
                        ForEach(EssayWorkMode.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        Button(uiText("Importer PDF ou image", "Import PDF or image"), systemImage: "doc.badge.plus") {
                            fileImporterPresented = true
                        }
                        if let selectedPromptURL {
                            Text(selectedPromptURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextEditor(text: $prompt)
                        .frame(minHeight: 130)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(StudyDeskTheme.borderSubtle) }
                    Text(uiText("Vérifie la transcription. UniSaver ne complète pas les symboles ou références manquants.", "Check the transcription. UniSaver does not invent missing symbols or references."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !promptNotes.isEmpty {
                        Text(promptNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            CreationCard(uiText("Contexte", "Context")) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent(uiText("Matière", "Course"), value: initialCourse?.name ?? uiText("Général", "General"))
                    LabeledContent(uiText("Chapitre", "Chapter"), value: initialChapter?.title ?? uiText("Sans chapitre", "No chapter"))
                    Toggle(uiText("Utiliser un chrono", "Use a timer"), isOn: $usesTimer)
                    if usesTimer {
                        TextField(uiText("Durée en minutes", "Duration in minutes"), text: $durationMinutes)
                            .textFieldStyle(.roundedBorder)
                    }
                    TextField(uiText("Longueur attendue en mots (facultatif)", "Expected length in words (optional)"), text: $expectedWordCount)
                        .textFieldStyle(.roundedBorder)
                    Toggle(uiText("Date limite", "Due date"), isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker(uiText("Échéance", "Due date"), selection: $dueDate)
                    }
                    TextField(uiText("Critères de correction facultatifs", "Optional correction criteria"), text: $criteria, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Text(uiText("Le chrono démarre uniquement quand l’étudiant appuie sur Commencer.", "The timer starts only when the student taps Start."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            CreationCard(uiText("Sources", "Sources")) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(uiText("Mode sources", "Source mode"), selection: $sourcesAllowed) {
                        Text(uiText("Aucune source", "No sources")).tag(false)
                        Text(uiText("Sources autorisées", "Allowed sources")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    if sourcesAllowed {
                        sourceSelectionList
                    } else {
                        Text(uiText("Pendant la rédaction, UniSaver masquera les documents, notes et outils d’étude de cette fenêtre. Cela ne contrôle pas les autres apps du Mac.", "During writing, UniSaver hides documents, notes, and study tools in this window. This does not control other Mac apps."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            CreationCard(uiText("Règle d’écriture", "Writing Rule")) {
                Text(uiText("Le corps de la réponse bloque le collage et le dépôt de texte. Les sources et métadonnées restent modifiables ici avant le début.", "The answer editor blocks pasted and dropped text. Sources and metadata remain editable here before starting."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                CreationErrorText(message: errorMessage)
            }
        } footer: {
            HStack {
                Button(uiText("Annuler", "Cancel")) { dismiss() }
                    .buttonStyle(.bordered)
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(uiText("Titre requis.", "Title required."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CreationPrimaryButton(
                    title: isSaving ? uiText("Création...", "Creating...") : uiText("Créer", "Create"),
                    systemImage: "checkmark.circle.fill",
                    accent: CourseColor.rose.color,
                    isDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving,
                    action: save
                )
            }
        }
        .fileImporter(isPresented: $fileImporterPresented, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: false) { result in
            handlePromptImport(result)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 650, idealHeight: 760)
    }

    private var sourceSelectionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if candidateResources.isEmpty && candidateNotes.isEmpty {
                Text(uiText("Aucune note ou ressource liée à cette matière/ce chapitre.", "No notes or resources are linked to this course/chapter."))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(candidateResources.enumerated()), id: \.element.id) { _, resource in
                Toggle(isOn: binding(forResource: resource)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(resource.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(resource.effectiveResourceKindTitle) · \(resourceHasUsableText(resource) ? uiText("texte descriptif disponible", "descriptive text available") : uiText("aucun texte exploitable enregistré", "no usable text stored"))")
                            .font(.caption)
                            .foregroundStyle(resourceHasUsableText(resource) ? Color.secondary : Color.orange)
                    }
                }
            }
            ForEach(Array(candidateNotes.enumerated()), id: \.element.id) { _, note in
                Toggle(isOn: binding(forNote: note)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title)
                            .font(.subheadline.weight(.semibold))
                        Text(note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? uiText("note sans texte exploitable", "note has no usable text") : uiText("note textuelle", "text note"))
                            .font(.caption)
                            .foregroundStyle(note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.orange : Color.secondary)
                    }
                }
            }
        }
    }

    private func handlePromptImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            selectedPromptURL = url
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            if url.pathExtension.localizedLowercase == "pdf",
               let document = PDFDocument(url: url) {
                let extracted = (0..<document.pageCount)
                    .compactMap { document.page(at: $0)?.string }
                    .joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                prompt = extracted
                promptNotes = extracted.isEmpty ? "Aucun texte fiable extrait du PDF. Recopie ou corrige la consigne." : "Texte extrait du PDF. Vérifie les passages et critères."
            } else {
                promptNotes = "Image importée. Vérifie manuellement la consigne ; aucune transcription incertaine n’est inventée."
            }
        } catch {
            errorMessage = "Impossible d’importer la consigne : \(error.localizedDescription)"
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        do {
            var promptResource: AcademicResource?
            if let selectedPromptURL {
                let draft = ResourceImportDraft(
                    fileURL: selectedPromptURL,
                    title: title,
                    resourceDescription: "Consigne originale",
                    course: initialCourse,
                    chapter: initialChapter,
                    session: nil,
                    tags: ["essay-prompt"]
                )
                promptResource = try ResourceImportService.submit(
                    draft: draft,
                    existingResources: resources,
                    modelContext: modelContext,
                    fileStore: AcademicFileStore(),
                    allowDuplicate: false
                )
            }
            let assignment = EssayAssignment(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind,
                mode: mode,
                prompt: prompt,
                promptRecognitionNotes: promptNotes,
                expectedWordCount: Int(expectedWordCount),
                durationMinutes: Int(durationMinutes),
                dueDate: hasDueDate ? dueDate : nil,
                evaluationCriteria: criteria,
                allowedResources: sourcesAllowed ? selectedSourceSummary : uiText("Aucune source", "No sources"),
                course: initialCourse,
                chapter: initialChapter,
                promptResource: promptResource
            )
            modelContext.insert(assignment)
            if sourcesAllowed {
                for resource in candidateResources where selectedResourceIDs.contains(resource.id) {
                    modelContext.insert(EssaySource(
                        title: resource.title,
                        page: resource.pageCount > 1 ? "1-\(resource.pageCount)" : "",
                        highlightedExcerpt: resource.resourceDescription,
                        note: resourceHasUsableText(resource) ? "" : uiText("Aucun texte exploitable stocké ; consultation locale seulement.", "No usable text stored; local consultation only."),
                        assignment: assignment,
                        resource: resource
                    ))
                }
                for note in candidateNotes where selectedNoteIDs.contains(note.id) {
                    modelContext.insert(EssaySource(
                        title: note.title,
                        highlightedExcerpt: note.body,
                        assignment: assignment,
                        studyNote: note
                    ))
                }
            }
            try modelContext.save()
            dismiss()
        } catch ResourceImportSubmitError.duplicate {
            errorMessage = "Cette consigne semble déjà importée pour cette destination."
        } catch {
            errorMessage = "La question ouverte n’a pas été créée : \(error.localizedDescription)"
        }
        isSaving = false
    }

    private var selectedSourceSummary: String {
        let count = selectedResourceIDs.count + selectedNoteIDs.count
        return count == 0 ? uiText("Sources autorisées, aucune sélection", "Sources allowed, none selected") : "\(count) \(uiText("source(s) autorisée(s)", "allowed source(s)"))"
    }

    private func resourceHasUsableText(_ resource: AcademicResource) -> Bool {
        !resource.resourceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func binding(forResource resource: AcademicResource) -> Binding<Bool> {
        Binding {
            selectedResourceIDs.contains(resource.id)
        } set: { isSelected in
            if isSelected { selectedResourceIDs.insert(resource.id) } else { selectedResourceIDs.remove(resource.id) }
        }
    }

    private func binding(forNote note: StudyNote) -> Binding<Bool> {
        Binding {
            selectedNoteIDs.contains(note.id)
        } set: { isSelected in
            if isSelected { selectedNoteIDs.insert(note.id) } else { selectedNoteIDs.remove(note.id) }
        }
    }
}

struct EssayWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var assignment: EssayAssignment
    @State private var activeStartedAt: Date?
    @State private var blockedPasteMessage: String?
    @State private var showingSubmissionConfirmation = false
    @State private var showingAbandonConfirmation = false
    @State private var showingSourceForm = false
    @State private var revisionExplanation = ""
    @State private var hasStarted = false
    @State private var timerEndDate: Date?
    @State private var now = Date()
    @State private var timeExpiredMessage: String?
    @State private var correctingSubmissionID: UUID?
    @State private var feedbackError: String?
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private func uiText(_ french: String, _ english: String) -> String {
        appLanguage == .english ? english : french
    }

    private var sortedSources: [EssaySource] {
        assignment.sources.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var sortedSubmissions: [EssaySubmission] {
        assignment.submissions.sorted { $0.versionNumber < $1.versionNumber }
    }

    private var wordCount: Int {
        essayWordCount(assignment.draftBody)
    }

    private var sourcesAllowed: Bool {
        !assignment.allowedResources.localizedCaseInsensitiveContains("aucune source")
            && !assignment.allowedResources.localizedCaseInsensitiveContains("no sources")
            && !sortedSources.isEmpty
    }

    private var remainingSeconds: Int? {
        guard let timerEndDate else { return nil }
        return max(0, Int(timerEndDate.timeIntervalSince(now)))
    }

    private var isExpired: Bool {
        remainingSeconds == 0 && assignment.durationMinutes != nil
    }

    var body: some View {
        NavigationStack {
            workspaceBody
            .navigationTitle(assignment.title)
            .toolbar {
                ToolbarItemGroup {
                    Text("\(wordCount) mots")
                    if sourcesAllowed {
                        Button(uiText("Ajouter une source", "Add source"), systemImage: "quote.bubble") { showingSourceForm = true }
                    }
                    Button(uiText("Terminer", "Finish"), systemImage: "tray.and.arrow.up") {
                        showingSubmissionConfirmation = true
                    }
                    .disabled(assignment.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(uiText("Abandonner", "Abandon"), systemImage: "xmark.circle", role: .destructive) {
                        showingAbandonConfirmation = true
                    }
                    .disabled(assignment.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showingSourceForm) {
                EssaySourceFormView(assignment: assignment)
            }
            .confirmationDialog(uiText("Remettre cette version ?", "Submit this version?"), isPresented: $showingSubmissionConfirmation) {
                Button(uiText("Créer une version non modifiable", "Create locked version")) {
                    submit(reason: .manual)
                }
                Button(uiText("Annuler", "Cancel"), role: .cancel) {}
            } message: {
                Text(uiText("La copie remise restera consultable. Tu pourras ensuite commencer une nouvelle version manuelle.", "The submitted answer remains available. You can then start a new manual version."))
            }
            .confirmationDialog(uiText("Abandonner la rédaction ?", "Abandon writing?"), isPresented: $showingAbandonConfirmation) {
                Button(uiText("Abandonner le brouillon", "Abandon draft"), role: .destructive) {
                    assignment.draftBody = ""
                    assignment.updatedAt = .now
                    clearTimer()
                    try? modelContext.save()
                }
                Button(uiText("Continuer à écrire", "Keep writing"), role: .cancel) {}
            } message: {
                Text(uiText("Le brouillon actuel sera effacé. Les remises précédentes et les sources restent conservées.", "The current draft will be cleared. Previous submissions and sources are preserved."))
            }
            .onAppear {
                restoreTimer()
            }
            .onDisappear {
                persistActiveTime()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    activeStartedAt = .now
                } else {
                    persistActiveTime()
                }
            }
            .task(id: hasStarted) {
                while hasStarted && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await MainActor.run {
                        now = .now
                        autoSubmitIfExpired()
                    }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 680)
    }

    @ViewBuilder
    private var workspaceBody: some View {
        if !hasStarted && sortedSubmissions.isEmpty && assignment.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startPanel
        } else {
            writingPanel
        }
    }

    private var startPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(assignment.prompt.isEmpty ? uiText("Aucune consigne transcrite.", "No prompt transcribed.") : assignment.prompt)
                .font(.title3)
                .lineSpacing(4)
                .textSelection(.enabled)
            CreationCard(uiText("Avant de commencer", "Before You Start")) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(timerRuleText, systemImage: "timer")
                    Label(sourcesAllowed ? uiText("Seules les sources sélectionnées seront visibles.", "Only selected sources will be visible.") : uiText("Aucune source ne sera affichée dans UniSaver pendant la rédaction.", "No sources will be shown in UniSaver during writing."), systemImage: sourcesAllowed ? "books.vertical" : "eye.slash")
                    Label(uiText("Le collage et le dépôt de texte sont bloqués dans la réponse.", "Paste and text drops are blocked in the answer."), systemImage: "doc.on.clipboard")
                }
                .foregroundStyle(.secondary)
            }
            Button {
                startWriting()
            } label: {
                Label(uiText("Commencer", "Start"), systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(28)
        .background(StudyDeskTheme.backgroundPrimary)
    }

    private var writingPanel: some View {
        GeometryReader { proxy in
            let isNarrow = proxy.size.width < 900
            Group {
                if isNarrow || !sourcesAllowed {
                    VStack(spacing: 12) {
                        compactPrompt
                        editorPanel
                        if sourcesAllowed { promptAndSources }
                    }
                } else {
                    HStack(spacing: 12) {
                        promptAndSources
                            .frame(width: min(390, proxy.size.width * 0.34))
                        editorPanel
                    }
                }
            }
            .padding()
        }
        .background(StudyDeskTheme.backgroundPrimary)
    }

    private var compactPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(uiText("Consigne", "Prompt"))
                .font(.headline)
            Text(assignment.prompt.isEmpty ? uiText("Aucune consigne transcrite.", "No prompt transcribed.") : assignment.prompt)
                .lineLimit(5)
                .textSelection(.enabled)
            if !sourcesAllowed {
                Text(uiText("Mode aucune source : UniSaver masque les documents et notes dans cette fenêtre. Cela ne contrôle pas les autres apps du Mac.", "No-source mode: UniSaver hides documents and notes in this window. This does not control other Mac apps."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var promptAndSources: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(assignment.kind.title, systemImage: "text.book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(assignment.prompt.isEmpty ? "Aucune consigne transcrite." : assignment.prompt)
                    .textSelection(.enabled)
                if !assignment.promptRecognitionNotes.isEmpty {
                    Text(assignment.promptRecognitionNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Group {
                    LabeledContent("Mode", value: assignment.mode.title)
                    if let expected = assignment.expectedWordCount {
                        LabeledContent("Cible", value: "\(expected) mots")
                    }
                    if let duration = assignment.durationMinutes {
                        LabeledContent("Durée", value: "\(duration) min")
                    }
                    if let dueDate = assignment.dueDate {
                        LabeledContent("Échéance", value: UniDateFormatters.dayMonth.string(from: dueDate))
                    }
                }
                .font(.caption)
                if !assignment.evaluationCriteria.isEmpty {
                    Divider()
                    Text("Critères")
                        .font(.headline)
                    Text(assignment.evaluationCriteria)
                }
                if !assignment.allowedResources.isEmpty {
                    Text("Ressources autorisées")
                        .font(.headline)
                    Text(assignment.allowedResources)
                }
                Divider()
                if sourcesAllowed {
                    Divider()
                    Text(uiText("Sources autorisées", "Allowed Sources"))
                        .font(.headline)
                    ForEach(sortedSources) { source in
                        EssaySourceCard(source: source)
                    }
                }
                if !sortedSubmissions.isEmpty {
                    Divider()
                    Text(uiText("Versions remises", "Submitted Versions"))
                        .font(.headline)
                    ForEach(sortedSubmissions) { submission in
                        EssaySubmissionCard(
                            submission: submission,
                            isCorrecting: correctingSubmissionID == submission.id,
                            requestAIFeedback: { requestAIFeedback(for: submission) },
                            flagComment: { flagFeedback(for: submission) }
                        )
                    }
                }
                if let feedbackError {
                    Text(feedbackError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(uiText("Réponse de l’étudiant", "Student Answer"))
                        .font(.headline)
                    Text(uiText("Collage et glisser-déposer de texte bloqués. Ce n’est pas une preuve infaillible d’écriture humaine.", "Paste and text drops are blocked. This is not proof of human authorship."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if let remainingSeconds {
                        Text(timeLabel(remainingSeconds))
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(remainingSeconds == 0 ? .orange : .primary)
                    }
                    Text("\(wordCount) mots")
                        .font(.headline)
                    if let expected = assignment.expectedWordCount {
                        Text("Cible \(expected)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            NoPasteEssayEditor(
                text: Binding(
                    get: { assignment.draftBody },
                    set: { value in
                        assignment.draftBody = value
                        assignment.updatedAt = .now
                        try? modelContext.save()
                    }
                ),
                blockedMessage: $blockedPasteMessage
            )
            .frame(minHeight: 320)
            .disabled(isExpired)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(StudyDeskTheme.borderSubtle)
            }
            if let timeExpiredMessage {
                Text(timeExpiredMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let blockedPasteMessage {
                Text(blockedPasteMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            DisclosureGroup("Plan facultatif") {
                TextField("Thèse", text: bindAssignment(\.outlineThesis), axis: .vertical)
                TextField("Arguments", text: bindAssignment(\.outlineArguments), axis: .vertical)
                TextField("Preuves", text: bindAssignment(\.outlineEvidence), axis: .vertical)
                TextField("Objections", text: bindAssignment(\.outlineObjections), axis: .vertical)
                Text("Le plan n’insère aucune phrase dans la réponse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if sortedSubmissions.count > 0 {
                TextField("Explique les principales révisions pour la prochaine version", text: $revisionExplanation, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func bindAssignment(_ keyPath: ReferenceWritableKeyPath<EssayAssignment, String>) -> Binding<String> {
        Binding {
            assignment[keyPath: keyPath]
        } set: { newValue in
            assignment[keyPath: keyPath] = newValue
            assignment.updatedAt = .now
            try? modelContext.save()
        }
    }

    private enum SubmissionReason {
        case manual
        case timerExpired
    }

    private func submit(reason: SubmissionReason) {
        persistActiveTime()
        let version = (assignment.submissions.map(\.versionNumber).max() ?? 0) + 1
        let local = localFeedback(for: assignment.draftBody, reason: reason)
        let submission = EssaySubmission(
            versionNumber: version,
            body: assignment.draftBody,
            wordCount: wordCount,
            activeDuration: assignment.activeDuration,
            revisionExplanation: revisionExplanation,
            feedbackStatus: .unavailable,
            feedbackSourceLabel: uiText("Retour local UniSaver", "UniSaver local feedback"),
            feedbackObservations: local.observations,
            feedbackSuggestions: local.suggestions,
            feedbackUncertainties: local.uncertainties,
            revisionPlan: local.revisionPlan,
            assignment: assignment
        )
        modelContext.insert(submission)
        assignment.status = version == 1 ? .submitted : .revised
        assignment.draftBody = ""
        assignment.updatedAt = .now
        clearTimer()
        try? modelContext.save()
    }

    private func persistActiveTime() {
        guard let activeStartedAt else { return }
        assignment.activeDuration += Date().timeIntervalSince(activeStartedAt)
        assignment.updatedAt = .now
        self.activeStartedAt = nil
        try? modelContext.save()
    }

    private var timerRuleText: String {
        if let duration = assignment.durationMinutes {
            return uiText("Durée : \(duration) min. À expiration, la copie est remise automatiquement avec le texte présent.", "Duration: \(duration) min. At expiration, the current answer is submitted automatically.")
        }
        return uiText("Sans chrono.", "No timer.")
    }

    private func startWriting() {
        hasStarted = true
        activeStartedAt = .now
        if let duration = assignment.durationMinutes, timerEndDate == nil {
            timerEndDate = Date().addingTimeInterval(TimeInterval(duration * 60))
            UserDefaults.standard.set(timerEndDate, forKey: timerKey)
        }
    }

    private func restoreTimer() {
        if let savedEnd = UserDefaults.standard.object(forKey: timerKey) as? Date {
            timerEndDate = savedEnd
            hasStarted = true
            activeStartedAt = .now
            autoSubmitIfExpired()
        } else if !assignment.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasStarted = true
            activeStartedAt = .now
        }
    }

    private func clearTimer() {
        timerEndDate = nil
        hasStarted = false
        activeStartedAt = nil
        UserDefaults.standard.removeObject(forKey: timerKey)
    }

    private var timerKey: String {
        "essayTimerEnd.\(assignment.id.uuidString)"
    }

    private func autoSubmitIfExpired() {
        guard isExpired, !assignment.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        timeExpiredMessage = uiText("Temps écoulé : la réponse a été remise avec le texte présent.", "Time expired: the current answer was submitted.")
        submit(reason: .timerExpired)
    }

    private func localFeedback(for body: String, reason: SubmissionReason) -> (observations: String, suggestions: String, uncertainties: String, revisionPlan: [String]) {
        let paragraphs = body.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let intro = reason == .timerExpired ? uiText("Remise automatique à expiration du chrono.", "Submitted automatically when the timer expired.") : uiText("Remise manuelle.", "Submitted manually.")
        let lengthObservation: String
        if let expected = assignment.expectedWordCount {
            let delta = wordCount - expected
            lengthObservation = abs(delta) <= max(50, expected / 10)
                ? uiText("Longueur proche de la cible : \(wordCount)/\(expected) mots.", "Length is close to target: \(wordCount)/\(expected) words.")
                : uiText("Longueur à vérifier : \(wordCount)/\(expected) mots.", "Length needs review: \(wordCount)/\(expected) words.")
        } else {
            lengthObservation = uiText("Aucune longueur cible fournie ; compteur final : \(wordCount) mots.", "No target length provided; final count: \(wordCount) words.")
        }
        let structure = paragraphs.count >= 3
            ? uiText("Structure repérable : \(paragraphs.count) paragraphes non vides.", "Visible structure: \(paragraphs.count) non-empty paragraphs.")
            : uiText("Structure possiblement courte : \(paragraphs.count) paragraphe(s). Ce n’est qu’un indice, pas un jugement certain.", "Possibly short structure: \(paragraphs.count) paragraph(s). This is only a signal, not a certain judgment.")
        return (
            "\(intro)\n\(lengthObservation)\n\(structure)",
            uiText("Relis la consigne, souligne ta thèse, puis vérifie qu’au moins un passage soutient chaque affirmation importante.", "Reread the prompt, mark your thesis, then check that at least one passage supports each important claim."),
            uiText("Le retour local ne vérifie pas la vérité des affirmations ni les citations. Une comparaison aux sources nécessite une correction IA configurée et ton accord.", "Local feedback does not verify factual claims or citations. Source comparison requires configured AI feedback and your consent."),
            [
                uiText("Identifier la phrase qui répond directement à la consigne.", "Identify the sentence that directly answers the prompt."),
                uiText("Choisir un passage à réécrire plus précisément.", "Choose one passage to rewrite more precisely."),
                uiText("Comparer chaque affirmation majeure aux sources autorisées.", "Compare each major claim against allowed sources.")
            ]
        )
    }

    private func requestAIFeedback(for submission: EssaySubmission) {
        guard correctingSubmissionID == nil else { return }
        feedbackError = nil
        correctingSubmissionID = submission.id
        submission.feedbackStatus = .notRequested
        try? modelContext.save()
        Task {
            do {
                let client = AIRevisionAssistantClient()
                guard case .ready = client.status() else {
                    throw AIRevisionError.notConfigured
                }
                let sources = aiSourcesForSubmission()
                let prompt = """
                Corrige cette question ouverte après remise. Ne donne pas de note chiffrée sauf si le barème ci-dessous l'impose explicitement.

                Consigne:
                \(assignment.prompt)

                Critères:
                \(assignment.evaluationCriteria.isEmpty ? "Aucun critère fourni." : assignment.evaluationCriteria)

                Réponse de l'élève:
                \(submission.body)

                Retour attendu:
                1. Ce que la réponse fait bien, avec courts extraits exacts de l'élève.
                2. Affirmations imprécises, erreurs ou étapes manquantes, liées à des extraits exacts.
                3. Écarts avec les sources. Si non vérifiable, écris exactement: non vérifiable avec les sources disponibles.
                4. Deux ou trois priorités d'amélioration concrètes.
                5. Exercice de reprise: un passage ciblé à réécrire par l'étudiant.
                """
                let answer = try await client.explain(
                    question: prompt,
                    courseName: assignment.course?.name ?? "UniSaver",
                    chapterTitle: assignment.chapter?.title ?? assignment.title,
                    sources: sources
                )
                await MainActor.run {
                    submission.feedbackStatus = .available
                    submission.feedbackSourceLabel = AIRevisionSettings.current.providerName
                    submission.feedbackGeneratedAt = .now
                    submission.feedbackObservations = answer
                    submission.feedbackSuggestions = uiText("Relis le retour, signale les commentaires inexacts, puis réécris seulement le passage ciblé.", "Review the feedback, flag inaccurate comments, then rewrite only the targeted passage.")
                    submission.feedbackUncertainties = sources.isEmpty ? uiText("Aucune source textuelle exploitable n’a été envoyée.", "No usable text source was sent.") : ""
                    assignment.status = .feedbackAvailable
                    try? modelContext.save()
                    correctingSubmissionID = nil
                }
            } catch {
                await MainActor.run {
                    submission.feedbackStatus = .failed
                    submission.feedbackUncertainties = error.localizedDescription
                    feedbackError = error.localizedDescription
                    try? modelContext.save()
                    correctingSubmissionID = nil
                }
            }
        }
    }

    private func aiSourcesForSubmission() -> [AIRevisionSource] {
        sortedSources.compactMap { source in
            let text = sourceText(source)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return AIRevisionSource(
                id: source.id.uuidString,
                title: source.title,
                kind: source.studyNote == nil ? .resource : .note,
                detail: source.page.isEmpty ? source.note : "p. \(source.page)",
                text: text,
                sourceReference: source.page.isEmpty ? source.title : "\(source.title), p. \(source.page)"
            )
        }
    }

    private func sourceText(_ source: EssaySource) -> String {
        if let note = source.studyNote {
            return note.body
        }
        return [source.highlightedExcerpt, source.note, source.resource?.resourceDescription ?? ""]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private func flagFeedback(for submission: EssaySubmission) {
        submission.feedbackUncertainties += submission.feedbackUncertainties.isEmpty
            ? uiText("L’étudiant a signalé au moins un commentaire à vérifier.", "The student flagged at least one comment for review.")
            : "\n\(uiText("L’étudiant a signalé au moins un commentaire à vérifier.", "The student flagged at least one comment for review."))"
        try? modelContext.save()
    }

    private func timeLabel(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

struct EssaySourceFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var assignment: EssayAssignment
    @State private var author = ""
    @State private var title = ""
    @State private var year = ""
    @State private var page = ""
    @State private var urlString = ""
    @State private var excerpt = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Auteur", text: $author)
                TextField("Titre", text: $title)
                TextField("Année", text: $year)
                TextField("Page", text: $page)
                TextField("URL", text: $urlString)
                TextField("Passage surligné ou extrait", text: $excerpt, axis: .vertical)
                TextField("Note personnelle", text: $note, axis: .vertical)
                Text("Le collage est autorisé ici. UniSaver ne fabrique pas les références manquantes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Ajouter une source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let source = EssaySource(
                            author: author,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Source sans titre" : title,
                            year: year,
                            page: page,
                            urlString: urlString,
                            highlightedExcerpt: excerpt,
                            note: note,
                            assignment: assignment
                        )
                        modelContext.insert(source)
                        assignment.updatedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 520)
    }
}

private struct EssaySourceCard: View {
    let source: EssaySource

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(source.title)
                .font(.subheadline.weight(.semibold))
            Text([source.author, source.year, source.page.isEmpty ? "" : "p. \(source.page)"].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !source.highlightedExcerpt.isEmpty {
                Text("“\(source.highlightedExcerpt)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EssaySubmissionCard: View {
    @Bindable var submission: EssaySubmission
    let isCorrecting: Bool
    let requestAIFeedback: () -> Void
    let flagComment: () -> Void

    var body: some View {
        DisclosureGroup("Version \(submission.versionNumber) · \(submission.wordCount) mots") {
            VStack(alignment: .leading, spacing: 8) {
                Text(submission.body)
                    .textSelection(.enabled)
                Divider()
                Text("Retour")
                    .font(.headline)
                Label(submission.feedbackStatus.title, systemImage: statusImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                if !submission.feedbackSourceLabel.isEmpty {
                    Text(submission.feedbackSourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(submission.feedbackObservations)
                if !submission.feedbackSuggestions.isEmpty {
                    Text(submission.feedbackSuggestions)
                        .foregroundStyle(.secondary)
                }
                if !submission.feedbackUncertainties.isEmpty {
                    Text(submission.feedbackUncertainties)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !submission.revisionPlan.isEmpty {
                    Text("Plan de reprise")
                        .font(.subheadline.weight(.semibold))
                    ForEach(submission.revisionPlan, id: \.self) { item in
                        Label(item, systemImage: "arrow.right.circle")
                    }
                    .font(.caption)
                }
                HStack {
                    Button(isCorrecting ? "Correction..." : "Demander retour IA", systemImage: "sparkles") {
                        requestAIFeedback()
                    }
                    .disabled(isCorrecting)
                    Button("Signaler un commentaire inexact", systemImage: "flag") {
                        flagComment()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 6)
        }
        .font(.caption)
    }

    private var statusImage: String {
        switch submission.feedbackStatus {
        case .notRequested: "clock"
        case .unavailable: "info.circle"
        case .available: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch submission.feedbackStatus {
        case .notRequested, .unavailable: .secondary
        case .available: .green
        case .failed: .red
        }
    }
}

struct NoPasteEssayEditor: View {
    @Binding var text: String
    @Binding var blockedMessage: String?

    var body: some View {
        #if os(macOS)
        NoPasteTextView(text: $text, blockedMessage: $blockedMessage)
        #elseif os(iOS)
        NoPasteTextView(text: $text, blockedMessage: $blockedMessage)
        #else
        TextEditor(text: $text)
        #endif
    }
}

#if os(macOS)
struct NoPasteTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var blockedMessage: String?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = BlockingPasteNSTextView()
        textView.string = text
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.onBlockedPaste = {
            blockedMessage = "Collage et dépôt de texte bloqués dans le corps de l’essai."
        }
        textView.unregisterDraggedTypes()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? BlockingPasteNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onBlockedPaste = {
            blockedMessage = "Collage et dépôt de texte bloqués dans le corps de l’essai."
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

final class BlockingPasteNSTextView: NSTextView {
    var onBlockedPaste: (() -> Void)?

    override func paste(_ sender: Any?) {
        onBlockedPaste?()
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        onBlockedPaste?()
        return false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onBlockedPaste?()
        return false
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)) {
            return false
        }
        return super.validateUserInterfaceItem(item)
    }
}
#endif

#if os(iOS)
struct NoPasteTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var blockedMessage: String?

    func makeUIView(context: Context) -> BlockingPasteUITextView {
        let textView = BlockingPasteUITextView()
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.dragInteractionEnabled = false
        textView.onBlockedPaste = {
            blockedMessage = "Collage et dépôt de texte bloqués dans le corps de l’essai."
        }
        return textView
    }

    func updateUIView(_ uiView: BlockingPasteUITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.onBlockedPaste = {
            blockedMessage = "Collage et dépôt de texte bloqués dans le corps de l’essai."
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}

final class BlockingPasteUITextView: UITextView {
    var onBlockedPaste: (() -> Void)?

    override func paste(_ sender: Any?) {
        onBlockedPaste?()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
#endif

private func essayWordCount(_ text: String) -> Int {
    text.split { $0.isWhitespace || $0.isNewline }.count
}

struct MathExerciseRow: View {
    let exercise: MathExercise

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "function")
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(exercise.sourceKind.title) · \(exercise.recognitionStatus.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(exercise.attempts.count) tentative\(exercise.attempts.count > 1 ? "s" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum ExerciseImportKind: String, CaseIterable, Identifiable {
    case openWork
    case classification

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openWork: "Exercice libre"
        case .classification: "Classer des éléments"
        }
    }
}

private struct ClassificationExercisePayload: Codable {
    static let marker = "__UNISAVER_CLASSIFICATION_EXERCISE_V1__"

    var instructions: String
    var categories: [ClassificationCategory]
    var items: [ClassificationItem]
    var sourceNote: String
    var allowsAnswerPreview: Bool

    var encodedPrompt: String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return instructions
        }
        return "\(Self.marker)\n\(json)"
    }

    static func decode(from prompt: String) -> ClassificationExercisePayload? {
        guard prompt.hasPrefix(marker),
              let data = prompt.components(separatedBy: "\n").dropFirst().joined(separator: "\n").data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ClassificationExercisePayload.self, from: data)
    }
}

private struct ClassificationCategory: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var explanation: String = ""
}

private struct ClassificationItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    var correctCategoryID: String?
    var explanation: String = ""
}

struct MathExerciseImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \ExternalLearningActivity.updatedAt, order: .reverse) private var externalActivities: [ExternalLearningActivity]

    let initialCourse: Course?
    let initialChapter: Chapter?

    @State private var selectedURL: URL?
    @State private var importKind: ExerciseImportKind = .openWork
    @State private var title = ""
    @State private var pageText = "1"
    @State private var regionDescription = ""
    @State private var recognizedPrompt = ""
    @State private var professorSolution = ""
    @State private var classificationInstructions = ""
    @State private var classificationCategories: [ClassificationCategory] = [
        ClassificationCategory(title: "Catégorie 1"),
        ClassificationCategory(title: "Catégorie 2")
    ]
    @State private var classificationItems: [ClassificationItem] = [
        ClassificationItem(text: "Élément à classer", correctCategoryID: nil)
    ]
    @State private var selectedExternalActivity: ExternalLearningActivity?
    @State private var errorMessage: String?
    @State private var recognitionNote = "Choisis un PDF ou une image. Le texte reconnu reste modifiable avant sauvegarde."
    @State private var recognitionStatus: MathExerciseRecognitionStatus = .notStarted
    @State private var isImporterPresented = false
    @State private var isSaving = false

    private let fileStore = AcademicFileStore()

    private var page: Int {
        max(Int(pageText) ?? 1, 1)
    }

    private var courseActivities: [ExternalLearningActivity] {
        externalActivities.filter { activity in
            guard let initialCourse else { return true }
            return activity.course?.id == initialCourse.id
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (selectedURL != nil || !recognizedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importKind == .classification)
            && (importKind != .classification || classificationIsSavable)
    }

    private var classificationIsSavable: Bool {
        !classificationInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && classificationCategories.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && classificationItems.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fichier original") {
                    Button(selectedURL == nil ? "Choisir PDF ou image" : "Changer le fichier", systemImage: "doc.badge.plus") {
                        isImporterPresented = true
                    }
                    if let selectedURL {
                        LabeledContent("Fichier", value: selectedURL.lastPathComponent)
                    }
                    Text("UniSaver garde le fichier original dans son stockage privé. Les annotations et brouillons sont enregistrés séparément.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tu peux aussi créer un exercice à partir d’un énoncé saisi ci-dessous. Dans ce cas, aucun fichier source n’est inventé.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Exercice") {
                    Picker("Type", selection: $importKind) {
                        ForEach(ExerciseImportKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Titre", text: $title)
                    TextField("Page", text: $pageText)
                    TextField("Zone ou question", text: $regionDescription, axis: .vertical)
                    Picker("Activité Moodle liée", selection: $selectedExternalActivity) {
                        Text("Aucune").tag(ExternalLearningActivity?.none)
                        ForEach(courseActivities) { activity in
                            Text(activity.title).tag(Optional(activity))
                        }
                    }
                }

                Section("Énoncé reconnu") {
                    TextEditor(text: $recognizedPrompt)
                        .frame(minHeight: 120)
                    LabeledContent("État", value: recognitionStatus.title)
                    Text(recognitionNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if importKind == .classification {
                    classificationPreviewSection
                }

                Section("Corrigé professeur") {
                    TextEditor(text: $professorSolution)
                        .frame(minHeight: 90)
                    Text("Ce champ est identifié comme corrigé fourni. Il reste distinct d’une correction générée ou d’un indice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Importer un exercice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Import..." : "Importer") {
                        save()
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                handleImportSelection(result)
            }
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 720)
    }

    private var classificationPreviewSection: some View {
        Section("Prévisualisation classification") {
            Text("Vérifie les consignes, les catégories et la clé de réponse. UniSaver laisse vides les réponses incertaines au lieu de les inventer.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Consignes", text: $classificationInstructions, axis: .vertical)
            LabeledContent("Catégories") {
                Button("Ajouter", systemImage: "plus.circle") {
                    classificationCategories.append(ClassificationCategory(title: "Nouvelle catégorie"))
                }
            }
            ForEach($classificationCategories) { $category in
                HStack {
                    TextField("Catégorie", text: $category.title)
                    Button(role: .destructive) {
                        classificationItems = classificationItems.map { item in
                            var copy = item
                            if copy.correctCategoryID == category.id {
                                copy.correctCategoryID = nil
                            }
                            return copy
                        }
                        classificationCategories.removeAll { $0.id == category.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            LabeledContent("Éléments") {
                Button("Ajouter", systemImage: "plus.circle") {
                    classificationItems.append(ClassificationItem(text: "", correctCategoryID: nil))
                }
            }
            ForEach($classificationItems) { $item in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Élément à classer", text: $item.text, axis: .vertical)
                    Picker("Bonne catégorie", selection: $item.correctCategoryID) {
                        Text("À vérifier").tag(String?.none)
                        ForEach(classificationCategories) { category in
                            Text(category.title).tag(Optional(category.id))
                        }
                    }
                    TextField("Explication facultative", text: $item.explanation, axis: .vertical)
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        classificationItems.removeAll { $0.id == item.id }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                errorMessage = "Aucun fichier sélectionné."
                return
            }
            selectedURL = url
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
            extractPreview(from: url)
        } catch {
            errorMessage = "Impossible de recevoir le fichier sélectionné : \(error.localizedDescription)"
        }
    }

    private func extractPreview(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.localizedLowercase
        if ext == "pdf", let document = PDFDocument(url: url), let page = document.page(at: max(self.page - 1, 0)) {
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            recognizedPrompt = text
            recognitionStatus = text.isEmpty ? .needsReview : .extracted
            recognitionNote = text.isEmpty
                ? "Aucun texte fiable n’a été extrait de cette page PDF. Vérifie l’image source et recopie l’énoncé."
                : "Texte extrait du PDF. Vérifie les équations et symboles avant de sauvegarder."
            seedClassificationPreview(from: text)
        } else {
            recognizedPrompt = ""
            recognitionStatus = .needsReview
            recognitionNote = "Image importée. La reconnaissance des équations n’est pas considérée fiable ici ; vérifie l’énoncé à partir de l’image originale."
        }
    }

    private func seedClassificationPreview(from text: String) {
        let lower = text.localizedLowercase
        guard importKind == .classification || lower.contains("class") || lower.contains("categor") || lower.contains("catégor") else {
            return
        }
        importKind = .classification
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        classificationInstructions = lines.prefix(5).joined(separator: "\n")
        let categoryCandidates = lines
            .filter { line in
                line.localizedCaseInsensitiveContains("category")
                    || line.localizedCaseInsensitiveContains("catégorie")
                    || line.localizedCaseInsensitiveContains("type:")
            }
            .prefix(6)
            .map { line in
                line
                    .replacingOccurrences(of: "Category:", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Catégorie :", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Type:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        if !categoryCandidates.isEmpty {
            classificationCategories = categoryCandidates.map { ClassificationCategory(title: $0) }
        }
        let itemCandidates = lines
            .filter { line in
                line.count > 12
                    && !line.localizedCaseInsensitiveContains("category")
                    && !line.localizedCaseInsensitiveContains("catégorie")
            }
            .prefix(30)
            .map { ClassificationItem(text: $0, correctCategoryID: nil) }
        if !itemCandidates.isEmpty {
            classificationItems = itemCandidates
        }
        recognitionStatus = .needsReview
        recognitionNote = "Prévisualisation de classification extraite du document. Les catégories et bonnes réponses doivent être vérifiées avant sauvegarde."
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        do {
            let resource: AcademicResource?
            if let selectedURL {
                let draft = ResourceImportDraft(
                    fileURL: selectedURL,
                    title: title,
                    resourceDescription: "Source originale de l’exercice",
                    course: initialCourse,
                    chapter: initialChapter,
                    session: nil,
                    tags: ["exercise"]
                )
                resource = try ResourceImportService.submit(
                    draft: draft,
                    existingResources: resources,
                    modelContext: modelContext,
                    fileStore: fileStore,
                    allowDuplicate: false
                )
            } else {
                resource = nil
            }
            let exercise = MathExercise(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceKind: resource.map(sourceKind(for:)) ?? .other,
                selectedPage: page,
                selectedRegionDescription: regionDescription,
                recognizedPrompt: importKind == .classification ? classificationPayload.encodedPrompt : recognizedPrompt,
                recognitionStatus: importKind == .classification ? .needsReview : recognitionStatus,
                recognitionNotes: recognitionNote,
                professorSolution: professorSolution,
                course: initialCourse,
                chapter: initialChapter,
                sourceResource: resource,
                externalActivity: selectedExternalActivity
            )
            modelContext.insert(exercise)
            try modelContext.save()
            dismiss()
        } catch ResourceImportSubmitError.duplicate {
            errorMessage = "Ce fichier semble déjà importé pour cette destination. Ouvre l’exercice existant ou choisis un autre fichier."
        } catch {
            errorMessage = "L’exercice n’a pas été sauvegardé : \(error.localizedDescription)"
        }
        isSaving = false
    }

    private var classificationPayload: ClassificationExercisePayload {
        ClassificationExercisePayload(
            instructions: classificationInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
            categories: classificationCategories.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            items: classificationItems.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            sourceNote: recognitionNote,
            allowsAnswerPreview: false
        )
    }

    private func sourceKind(for resource: AcademicResource) -> MathExerciseSourceKind {
        switch resource.effectiveResourceKind {
        case .pdf: .pdf
        case .image: .image
        default: .other
        }
    }
}

struct MathExerciseWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var exercise: MathExercise
    @State private var selectedAttempt: MathExerciseAttempt?
    @State private var selectedMode: MathExerciseWorkMode = .autonomy
    @State private var activeStartedAt: Date?
    @State private var helpMessage: String?
    @State private var selectedTool = "stylet"

    private var currentAttempt: MathExerciseAttempt {
        if let selectedAttempt {
            return selectedAttempt
        }
        if let existing = exercise.attempts.sorted(by: { $0.updatedAt > $1.updatedAt }).first(where: { $0.status == .inProgress }) {
            return existing
        }
        let attempt = MathExerciseAttempt(workMode: selectedMode, exercise: exercise)
        modelContext.insert(attempt)
        try? modelContext.save()
        selectedAttempt = attempt
        return attempt
    }

    var body: some View {
        if let payload = ClassificationExercisePayload.decode(from: exercise.recognizedPrompt) {
            ClassificationExerciseWorkspaceView(exercise: exercise, payload: payload)
        } else {
        NavigationStack {
            GeometryReader { proxy in
                let isNarrow = proxy.size.width < 760
                Group {
                    if isNarrow {
                        VStack(spacing: 12) {
                            promptPanel
                            workPanel
                        }
                    } else {
                        HStack(spacing: 12) {
                            promptPanel
                                .frame(width: min(380, proxy.size.width * 0.36))
                            workPanel
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(exercise.title)
            .toolbar {
                ToolbarItemGroup {
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(MathExerciseWorkMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .disabled(currentAttempt.status != .inProgress || currentAttempt.activeDuration > 0)
                    Button("Remettre", systemImage: "tray.and.arrow.up") {
                        submitAttempt()
                    }
                    .disabled(currentAttempt.status != .inProgress)
                }
            }
            .onAppear {
                selectedMode = currentAttempt.workMode
                activeStartedAt = .now
            }
            .onDisappear {
                persistActiveTime()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    activeStartedAt = .now
                } else {
                    persistActiveTime()
                }
            }
            .onChange(of: selectedMode) { _, newValue in
                guard currentAttempt.activeDuration == 0 else { return }
                currentAttempt.workMode = newValue
                currentAttempt.updatedAt = .now
                try? modelContext.save()
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        }
    }

    private var promptPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(exercise.sourceKind.title, systemImage: "doc.text.image")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(exercise.recognizedPrompt.isEmpty ? "Aucun énoncé reconnu. Utilise le fichier original comme référence et complète l’énoncé manuellement." : exercise.recognizedPrompt)
                    .font(.body)
                    .textSelection(.enabled)
                if !exercise.recognitionNotes.isEmpty {
                    Text(exercise.recognitionNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text("Mode \(currentAttempt.workMode.title)")
                    .font(.headline)
                Text(currentAttempt.workMode.explanation)
                    .foregroundStyle(.secondary)
                if !exercise.professorSolution.isEmpty && currentAttempt.status != .inProgress {
                    Divider()
                    Text("Corrigé fourni")
                        .font(.headline)
                    Text(exercise.professorSolution)
                        .textSelection(.enabled)
                }
                if let helpMessage {
                    Divider()
                    Text(helpMessage)
                        .font(.callout)
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var workPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Feuille de travail")
                    .font(.headline)
                Spacer()
                Text("Temps actif \(exerciseMinutesLabel(currentAttempt.activeDuration))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Picker("Outil", selection: $selectedTool) {
                Text("Stylet").tag("stylet")
                Text("Gomme").tag("gomme")
                Text("Sélection").tag("selection")
            }
            .pickerStyle(.segmented)
            #if os(iOS)
            PencilMathCanvas(drawingData: Binding(
                get: { currentAttempt.pencilDrawingData },
                set: { data in
                    currentAttempt.pencilDrawingData = data
                    currentAttempt.updatedAt = .now
                    try? modelContext.save()
                }
            ))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            #else
            TextEditor(text: Binding(
                get: { currentAttempt.typedScratch },
                set: { value in
                    currentAttempt.typedScratch = value
                    currentAttempt.updatedAt = .now
                    try? modelContext.save()
                }
            ))
            .font(.body.monospaced())
            .frame(minHeight: 300)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(StudyDeskTheme.borderSubtle)
            }
            Text("Le canevas Apple Pencil sera actif sur iPad. Sur macOS, ce brouillon texte permet de vérifier la sauvegarde et le suivi.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
            assistanceControls
        }
        .padding()
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var assistanceControls: some View {
        HStack {
            Button("Vérifie") { requestHelp("Vérifie ma zone sélectionnée") }
                .disabled(currentAttempt.workMode == .exam)
            Button("Indice") { requestHelp("Donne un indice progressif") }
                .disabled(currentAttempt.workMode == .exam)
            Button("Explique mon erreur") { requestHelp("Explique mon erreur") }
                .disabled(currentAttempt.workMode == .exam)
            Spacer()
            Text(currentAttempt.workMode == .exam ? "Aide verrouillée avant remise." : "Aucune IA réelle configurée : les demandes sont journalisées sans réponse simulée.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func requestHelp(_ request: String) {
        currentAttempt.helpRequests.append(request)
        currentAttempt.updatedAt = .now
        helpMessage = "Demande enregistrée : \(request). Configure un fournisseur IA réel pour obtenir une réponse contextualisée."
        try? modelContext.save()
    }

    private func submitAttempt() {
        persistActiveTime()
        currentAttempt.status = .submitted
        currentAttempt.submittedAt = .now
        currentAttempt.updatedAt = .now
        try? modelContext.save()
    }

    private func persistActiveTime() {
        guard let activeStartedAt else { return }
        currentAttempt.activeDuration += Date().timeIntervalSince(activeStartedAt)
        currentAttempt.updatedAt = .now
        self.activeStartedAt = nil
        try? modelContext.save()
    }

    private func exerciseMinutesLabel(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

#if os(iOS)
struct PencilMathCanvas: UIViewRepresentable {
    @Binding var drawingData: Data?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .systemBackground
        canvas.delegate = context.coordinator
        if let drawingData, let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if let drawingData,
           let drawing = try? PKDrawing(data: drawingData),
           uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingData: $drawingData)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawingData: Data?

        init(drawingData: Binding<Data?>) {
            _drawingData = drawingData
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawingData = canvasView.drawing.dataRepresentation()
        }
    }
}
#endif

private struct ClassificationExerciseWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var exercise: MathExercise
    let payload: ClassificationExercisePayload
    @State private var assignments: [String: String] = [:]
    @State private var history: [[String: String]] = []
    @State private var selectedItemID: String?
    @State private var activeAttempt: MathExerciseAttempt?
    @State private var feedbackMessage: String?
    @State private var submitted = false

    private var attempt: MathExerciseAttempt {
        if let activeAttempt { return activeAttempt }
        if let existing = exercise.attempts.sorted(by: { $0.updatedAt > $1.updatedAt }).first(where: { $0.status == .inProgress }) {
            return existing
        }
        let created = MathExerciseAttempt(workMode: .autonomy, exercise: exercise)
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    private var unassignedItems: [ClassificationItem] {
        payload.items.filter { assignments[$0.id] == nil }
    }

    private var allItemsAssigned: Bool {
        payload.items.allSatisfy { assignments[$0.id] != nil }
    }

    private var score: Int {
        payload.items.filter { item in
            guard let expected = item.correctCategoryID else { return false }
            return assignments[item.id] == expected
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    instructionsCard
                    unassignedTray
                    categoryGrid
                    if let feedbackMessage {
                        Label(feedbackMessage, systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if submitted {
                        reviewCard
                    }
                }
                .padding(24)
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .frame(minWidth: 840, idealWidth: 1040, minHeight: 700, idealHeight: 820)
        .onAppear {
            loadAttempt()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.3.group.bubble.left")
                .font(.title2.weight(.semibold))
                .foregroundStyle(StudyDeskTheme.accentPrimary)
                .frame(width: 44, height: 44)
                .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.title)
                    .font(.title2.weight(.bold))
                Text("\(payload.items.count) éléments · \(payload.categories.count) catégories")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let resource = exercise.sourceResource {
                Text(resource.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(20)
        .background(StudyDeskTheme.surfacePrimary)
    }

    private var instructionsCard: some View {
        CreationCard("Consignes") {
            Text(payload.instructions.isEmpty ? "Classe chaque élément dans la catégorie qui convient." : payload.instructions)
                .font(.title3)
                .lineSpacing(4)
                .textSelection(.enabled)
            if !payload.sourceNote.isEmpty {
                Text(payload.sourceNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unassignedTray: some View {
        CreationCard("À classer", subtitle: selectedItemID == nil ? "Glisse une carte vers une catégorie, ou sélectionne-la puis choisis une catégorie." : "Choisis une catégorie pour déplacer la carte sélectionnée.") {
            if unassignedItems.isEmpty {
                Text("Tous les éléments ont été placés.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(unassignedItems) { item in
                        classificationItemCard(item, isSelected: selectedItemID == item.id)
                            .draggable(item.id)
                    }
                }
            }
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
            ForEach(payload.categories) { category in
                categoryColumn(category)
            }
        }
    }

    private func categoryColumn(_ category: ClassificationCategory) -> some View {
        let items = payload.items.filter { assignments[$0.id] == category.id }
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                assignSelectedItem(to: category)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.title)
                            .font(.headline)
                        if !category.explanation.isEmpty {
                            Text(category.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(items.count)")
                        .font(.headline.monospacedDigit())
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, payload.items.contains(where: { $0.id == id }) else {
                    feedbackMessage = "Cette carte ne fait pas partie de l’exercice."
                    return false
                }
                move(itemID: id, to: category.id)
                feedbackMessage = "Carte déplacée vers \(category.title)."
                return true
            }

            if items.isEmpty {
                Text("Dépose des cartes ici.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ForEach(items) { item in
                    classificationItemCard(item, isSelected: selectedItemID == item.id)
                        .draggable(item.id)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private func classificationItemCard(_ item: ClassificationItem, isSelected: Bool) -> some View {
        Button {
            selectedItemID = selectedItemID == item.id ? nil : item.id
            feedbackMessage = "Carte sélectionnée. Choisis une catégorie pour la déplacer."
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? StudyDeskTheme.accentPrimary : .secondary)
                Text(item.text)
                    .font(.body.weight(.medium))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? StudyDeskTheme.accentPrimary.opacity(0.10) : StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? StudyDeskTheme.accentPrimary : StudyDeskTheme.borderSubtle, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focusable(true)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Annuler le dernier geste", systemImage: "arrow.uturn.backward") {
                undo()
            }
            .disabled(history.isEmpty || submitted)
            Button("Réinitialiser", systemImage: "arrow.counterclockwise") {
                pushHistory()
                assignments = [:]
                selectedItemID = nil
                submitted = false
                saveProgress()
            }
            .disabled(assignments.isEmpty)
            Spacer()
            Text("\(assignments.count) / \(payload.items.count) classés")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            CreationPrimaryButton(title: submitted ? "Réessayer" : "Vérifier", systemImage: submitted ? "arrow.counterclockwise" : "checkmark.circle.fill", accent: StudyDeskTheme.accentPrimary, isDisabled: !submitted && !allItemsAssigned) {
                submitted ? retry() : submit()
            }
        }
        .padding(16)
        .background(StudyDeskTheme.surfacePrimary)
    }

    private var reviewCard: some View {
        CreationCard("Résultat", subtitle: "\(score) / \(payload.items.count) bonnes réponses") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(payload.items) { item in
                    let assigned = payload.categories.first { $0.id == assignments[item.id] }?.title ?? "Non classé"
                    let expected = payload.categories.first { $0.id == item.correctCategoryID }?.title ?? "À vérifier"
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text)
                            .font(.callout.weight(.semibold))
                        Text("Ta réponse : \(assigned)")
                            .foregroundStyle(.secondary)
                        Text("Réponse attendue : \(expected)")
                            .foregroundStyle(item.correctCategoryID == nil ? .orange : .secondary)
                        if !item.explanation.isEmpty {
                            Text(item.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private func assignSelectedItem(to category: ClassificationCategory) {
        guard let selectedItemID else {
            feedbackMessage = "Sélectionne d’abord une carte."
            return
        }
        move(itemID: selectedItemID, to: category.id)
        self.selectedItemID = nil
        feedbackMessage = "Carte déplacée vers \(category.title)."
    }

    private func move(itemID: String, to categoryID: String) {
        guard !submitted else { return }
        pushHistory()
        assignments[itemID] = categoryID
        saveProgress()
    }

    private func pushHistory() {
        history.append(assignments)
        if history.count > 20 {
            history.removeFirst()
        }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        assignments = previous
        selectedItemID = nil
        saveProgress()
    }

    private func submit() {
        guard allItemsAssigned else {
            feedbackMessage = "Il reste des éléments à classer."
            return
        }
        submitted = true
        let attempt = attempt
        attempt.status = .submitted
        attempt.submittedAt = .now
        attempt.updatedAt = .now
        attempt.typedScratch = encodeAssignments()
        attempt.selfAssessment = "\(score)/\(payload.items.count)"
        try? modelContext.save()
    }

    private func retry() {
        let next = MathExerciseAttempt(workMode: .autonomy, exercise: exercise)
        modelContext.insert(next)
        activeAttempt = next
        assignments = [:]
        history = []
        selectedItemID = nil
        submitted = false
        feedbackMessage = nil
        try? modelContext.save()
    }

    private func loadAttempt() {
        let attempt = attempt
        activeAttempt = attempt
        submitted = attempt.status != .inProgress
        assignments = decodeAssignments(from: attempt.typedScratch)
    }

    private func saveProgress() {
        let attempt = attempt
        attempt.typedScratch = encodeAssignments()
        attempt.updatedAt = .now
        try? modelContext.save()
    }

    private func encodeAssignments() -> String {
        guard let data = try? JSONEncoder().encode(assignments),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func decodeAssignments(from text: String) -> [String: String] {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

struct ExternalLearningActivityCard: View {
    @Bindable var activity: ExternalLearningActivity
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.title)
                        .font(.headline)
                    Text("\(activity.platform.title) · \(activity.activityType.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(activity.status.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(StudyDeskTheme.surfaceTinted, in: Capsule())
            }
            HStack {
                Text(activity.lastOpenedAt.map { "Dernier accès \(UniDateFormatters.dayMonth.string(from: $0))" } ?? "Pas encore ouvert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Faire l’exercice", systemImage: "play.fill", action: openAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }
}

struct ExternalLearningActivityFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let initialCourse: Course?
    let initialChapter: Chapter?
    let existingActivities: [ExternalLearningActivity]
    private let editingActivity: ExternalLearningActivity?

    @Query(sort: \Course.name) private var courses: [Course]
    @State private var title: String
    @State private var urlString: String
    @State private var platform: ExternalLearningPlatform
    @State private var activityType: ExternalLearningActivityType
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var errorMessage: String?

    init(initialCourse: Course?, initialChapter: Chapter?, existingActivities: [ExternalLearningActivity], activity: ExternalLearningActivity? = nil) {
        self.initialCourse = initialCourse
        self.initialChapter = initialChapter
        self.existingActivities = existingActivities
        self.editingActivity = activity
        _title = State(initialValue: activity?.title ?? "")
        _urlString = State(initialValue: activity?.originalURLString ?? "")
        _platform = State(initialValue: activity?.platform ?? .moodle)
        _activityType = State(initialValue: activity?.activityType ?? .exercise)
        _selectedCourseID = State(initialValue: activity?.course?.id ?? initialCourse?.id)
        _selectedChapterID = State(initialValue: activity?.chapter?.id ?? initialChapter?.id)
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    private var chapters: [Chapter] {
        selectedCourse?.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order } ?? []
    }

    var body: some View {
        CreationWindow(
            icon: "link.badge.plus",
            title: editingActivity == nil ? "Ajouter une activité externe" : "Modifier l’activité",
            subtitle: "Conserve le lien exact vers Moodle, eCampus ou Quizlet sans copier l’exercice.",
            accent: CourseColor.indigo.color,
            closeAction: { dismiss() }
        ) {
            CreationCard("Activité originale", subtitle: "Le lien doit ouvrir l’exercice précis dans la plateforme d’origine.") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("URL Moodle ou Quizlet", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                    if let errorMessage, urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || errorMessage.localizedCaseInsensitiveContains("url") {
                        CreationErrorText(message: errorMessage)
                    }
                    TextField("Titre", text: $title)
                        .textFieldStyle(.roundedBorder)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            Text("Plateforme")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("Plateforme", selection: $platform) {
                                ForEach(ExternalLearningPlatform.allCases) { platform in
                                    Text(platform.title).tag(platform)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Type")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("Type", selection: $activityType) {
                                ForEach(ExternalLearningActivityType.allCases) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }

            CreationCard("Classement UniSaver") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Cours", selection: $selectedCourseID) {
                        Text("Non associé").tag(UUID?.none)
                        ForEach(courses.filter { !$0.isArchived }) { course in
                            Text(externalActivityCourseTitle(course)).tag(Optional(course.id))
                        }
                    }
                    Picker("Chapitre", selection: $selectedChapterID) {
                        Text("Sans chapitre").tag(UUID?.none)
                        ForEach(chapters) { chapter in
                            Text("\(chapter.number). \(chapter.title)").tag(Optional(chapter.id))
                        }
                    }
                    .disabled(selectedCourse == nil)
                }
            }

            CreationCard("Confidentialité") {
                Text("UniSaver conserve uniquement le lien et ton suivi personnel. Le mot de passe Moodle/Quizlet n’est pas stocké.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage, !(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || errorMessage.localizedCaseInsensitiveContains("url")) {
                CreationErrorText(message: errorMessage)
            }
        } footer: {
            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.bordered)
                if urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("URL requise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CreationPrimaryButton(
                    title: "Enregistrer",
                    systemImage: "checkmark.circle.fill",
                    accent: CourseColor.indigo.color,
                    isDisabled: urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: save
                )
            }
        }
        .frame(minWidth: 620, idealWidth: 740, minHeight: 520, idealHeight: 620)
        .onChange(of: selectedCourseID) { _, _ in
            if selectedCourse == nil || !chapters.contains(where: { $0.id == selectedChapterID }) {
                selectedChapterID = nil
            }
        }
        .onChange(of: urlString) { _, newValue in
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = suggestedTitle(from: newValue)
            }
            platform = suggestedPlatform(from: newValue)
        }
    }

    private func save() {
        errorMessage = nil
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else {
            errorMessage = "Colle une URL web valide vers l’activité précise."
            return
        }
        guard !normalizedActivityURL(trimmedURL).isEmpty else {
            errorMessage = "L’URL ne peut pas être vide."
            return
        }
        let duplicate = existingActivities.contains { existing in
            existing.id != editingActivity?.id && normalizedActivityURL(existing.originalURLString) == normalizedActivityURL(trimmedURL)
        }
        if duplicate {
            errorMessage = "Cette activité semble déjà ajoutée dans UniSaver."
            return
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = editingActivity ?? ExternalLearningActivity(
            title: cleanTitle.isEmpty ? suggestedTitle(from: trimmedURL) : cleanTitle,
            originalURLString: trimmedURL,
            platform: platform,
            activityType: activityType,
            course: selectedCourse,
            chapter: chapters.first { $0.id == selectedChapterID }
        )
        if editingActivity == nil {
            modelContext.insert(target)
        }
        target.title = cleanTitle.isEmpty ? suggestedTitle(from: trimmedURL) : cleanTitle
        target.originalURLString = trimmedURL
        target.platform = platform
        target.activityType = activityType
        target.course = selectedCourse
        target.chapter = chapters.first { $0.id == selectedChapterID }
        target.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func suggestedTitle(from value: String) -> String {
        guard let url = URL(string: value), let host = url.host else { return "" }
        let last = url.deletingPathExtension().lastPathComponent
        if !last.isEmpty && last != "/" { return last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ") }
        return host
    }
}

struct ExternalLearningActivityWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var activity: ExternalLearningActivity
    @State private var editingActivity = false
    @State private var confirmRemove = false
    @State private var webErrorMessage: String?
    @State private var difficultConceptsText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                activityToolbar
                Divider()
                if let url = activity.originalURL {
                    ExternalActivityWebView(url: url, errorMessage: $webErrorMessage)
                        .frame(minHeight: 460)
                } else {
                    EmptyStateView(title: "URL invalide", message: "Modifie le lien de cette activité.", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                trackingPanel
            }
            .navigationTitle(activity.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItemGroup {
                    Button("Modifier", systemImage: "pencil") { editingActivity = true }
                    Button("Retirer de UniSaver", systemImage: "link.badge.minus", role: .destructive) { confirmRemove = true }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 760)
        .onAppear {
            activity.lastOpenedAt = .now
            if activity.status == .todo {
                activity.status = .inProgress
            }
            difficultConceptsText = activity.difficultConcepts.joined(separator: "\n")
            try? modelContext.save()
        }
        .sheet(isPresented: $editingActivity) {
            ExternalLearningActivityFormView(initialCourse: activity.course, initialChapter: activity.chapter, existingActivities: [activity], activity: activity)
        }
        .confirmationDialog("Retirer cette activité de UniSaver ?", isPresented: $confirmRemove) {
            Button("Retirer le lien", role: .destructive) {
                modelContext.delete(activity)
                try? modelContext.save()
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cela ne supprime rien sur Moodle, eCampus ou Quizlet.")
        }
    }

    private var activityToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.platform.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(activity.originalURLString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer()
            if let url = activity.originalURL {
                Link("Ouvrir dans le navigateur", destination: url)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var trackingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let webErrorMessage {
                Text(webErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Text("Qu’as-tu trouvé difficile ?")
                .font(.headline)
            HStack {
                Picker("État", selection: Binding(
                    get: { activity.status },
                    set: { activity.status = $0; saveTracking() }
                )) {
                    ForEach(ExternalLearningActivityStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Score observé, ex. 8/10 ou 80%", text: Binding(
                    get: { activity.observedScore },
                    set: { activity.observedScore = $0; saveTracking() }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            }
            TextField("Note personnelle", text: Binding(
                get: { activity.personalNote },
                set: { activity.personalNote = $0; saveTracking() }
            ), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            TextField("Notions ratées, une par ligne", text: $difficultConceptsText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onChange(of: difficultConceptsText) { _, value in
                    activity.difficultConcepts = value.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    saveTracking()
                }
        }
        .padding()
        .background(StudyDeskTheme.backgroundSecondary)
    }

    private func saveTracking() {
        activity.updatedAt = .now
        try? modelContext.save()
    }
}

struct ExternalActivityWebView: NSViewRepresentable {
    let url: URL
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(errorMessage: $errorMessage)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var errorMessage: String?

        init(errorMessage: Binding<String?>) {
            _errorMessage = errorMessage
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            errorMessage = "La vue intégrée n’a pas pu charger cette activité. Utilise “Ouvrir dans le navigateur” si le SSO, les cookies ou la plateforme bloquent l’intégration."
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            errorMessage = "La vue intégrée n’a pas pu charger cette activité. Utilise “Ouvrir dans le navigateur” si le SSO, les cookies ou la plateforme bloquent l’intégration."
        }
    }
}

private func normalizedActivityURL(_ value: String) -> String {
    guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return ""
    }
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    components.fragment = nil
    return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? value.lowercased()
}

private func suggestedPlatform(from value: String) -> ExternalLearningPlatform {
    guard let host = URL(string: value)?.host?.lowercased() else { return .other }
    if host.contains("quizlet") { return .quizlet }
    if host.contains("moodle") || host.contains("ecampus") || host.contains("esade") { return .moodle }
    return .other
}

private func externalActivityCourseTitle(_ course: Course) -> String {
    course.code.isEmpty ? course.name : "\(course.code) · \(course.name)"
}
