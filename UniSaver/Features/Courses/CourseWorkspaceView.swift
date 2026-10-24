import AppKit
import EventKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum CourseWorkspaceTab: String, CaseIterable, Identifiable {
    case overview
    case sessions
    case chapters
    case materials
    case recordings
    case study

    var id: String { rawValue }
    var title: String {
        title(for: AppLanguage.current)
    }

    func title(for language: AppLanguage) -> String {
        let english = language == .english || (language == .system && Locale.current.language.languageCode?.identifier != "fr")
        return switch self {
        case .overview: english ? "Overview" : "Vue d’ensemble"
        case .sessions: english ? "Sessions" : "Séances"
        case .chapters: english ? "Chapters" : "Chapitres"
        case .materials: english ? "Resources" : "Ressources"
        case .recordings: english ? "Recordings" : "Enregistrements"
        case .study: english ? "Revision" : "Révision"
        }
    }
}

struct CourseWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation
    @Query(sort: \ExternalLearningActivity.updatedAt, order: .reverse) private var externalActivities: [ExternalLearningActivity]
    @Query(sort: \MathExercise.updatedAt, order: .reverse) private var mathExercises: [MathExercise]
    @Query(sort: \EssayAssignment.updatedAt, order: .reverse) private var essayAssignments: [EssayAssignment]
    @Bindable var course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var tab: CourseWorkspaceTab = .overview
    @State private var editingCourse = false
    @State private var deleteConfirmation = false
    @State private var archiveConfirmation = false
    @State private var importingResource = false
    @State private var importingContent = false
    @State private var importingSyllabus = false
    @State private var importingExercise = false
    @State private var creatingEssayAssignment = false
    @State private var creatingResearchPaper = false
    @State private var creatingAssignmentPlan = false
    @State private var creatingGroupProject = false
    @State private var showingChangeMonitor = false
    @State private var selectedAssignmentPlan: StudyNote?
    @State private var selectedGroupProject: StudyNote?
    @State private var selectedResearchPaper: StudyNote?
    @State private var addingExternalActivity = false
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private func uiText(_ french: String, _ english: String) -> String {
        (appLanguage == .english || (appLanguage == .system && Locale.current.language.languageCode?.identifier != "fr")) ? english : french
    }

    private var visibleChapters: [Chapter] {
        course.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order }
    }

    private var sortedSessions: [ClassSession] {
        course.sessions.sorted { $0.startTime < $1.startTime }
    }

    private var nextSession: ClassSession? {
        sortedSessions.first { $0.startTime >= .now }
    }

    private var hasResumeTarget: Bool {
        nextSession != nil || !visibleChapters.isEmpty || !course.sessions.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            courseTabs

            Group {
                switch tab {
                case .overview:
                    CourseOverviewView(course: course, nextSession: nextSession, selectedTab: $tab, quickAddTarget: $quickAddTarget)
                case .sessions:
                    SessionListView(course: course, quickAddTarget: $quickAddTarget)
                case .chapters:
                    ChapterListView(course: course, quickAddTarget: $quickAddTarget)
                case .materials:
                    CourseMaterialsView(course: course, quickAddTarget: $quickAddTarget)
                case .recordings:
                    CourseRecordingsView(course: course, quickAddTarget: $quickAddTarget)
                case .study:
                    CourseStudyView(course: course)
                }
            }
            .id(tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .navigationTitle(course.name)
        .accessibilityIdentifier("courseWorkspace_\(course.id.uuidString)")
        .toolbar {
            ToolbarItemGroup {
                Button(uiText("Modifier", "Edit"), systemImage: "pencil") { editingCourse = true }
                    .help(uiText("Modifier les informations de la matière", "Edit this class"))
            }
        }
        .sheet(isPresented: $editingCourse) {
            CourseFormView(mode: .edit(course))
        }
        .sheet(isPresented: $importingContent) {
            CourseContentImportSheet(initialCourse: course)
        }
        .sheet(isPresented: $importingSyllabus) {
            CourseSyllabusImportSheet(course: course)
        }
        .sheet(isPresented: $addingExternalActivity) {
            ExternalLearningActivityFormView(initialCourse: course, initialChapter: nil, existingActivities: externalActivities)
        }
        .sheet(isPresented: $importingExercise) {
            MathExerciseImportSheet(initialCourse: course, initialChapter: nil)
        }
        .sheet(isPresented: $creatingEssayAssignment) {
            EssayAssignmentFormView(initialCourse: course, initialChapter: nil)
        }
        .sheet(isPresented: $creatingResearchPaper) {
            ResearchPaperCreationView(course: course, chapters: visibleChapters) { note in
                selectedResearchPaper = note
            }
        }
        .sheet(isPresented: $creatingAssignmentPlan) {
            AssignmentPlannerSheet(course: course, chapters: visibleChapters) { note in
                selectedAssignmentPlan = note
            }
        }
        .sheet(isPresented: $showingChangeMonitor) {
            AcademicChangeMonitorView(course: course)
        }
        .sheet(isPresented: $creatingGroupProject) {
            GroupProjectCreationSheet(course: course) { note in
                selectedGroupProject = note
            }
        }
        .sheet(item: $selectedResearchPaper) { note in
            ResearchPaperWorkspaceView(projectNote: note)
        }
        .navigationDestination(item: $selectedAssignmentPlan) { note in
            AssignmentWorkspaceView(note: note)
        }
        .sheet(item: $selectedGroupProject) { note in
            GroupProjectWorkspaceView(note: note)
        }
        .confirmationDialog(uiText("Archiver cette matière ?", "Archive this class?"), isPresented: $archiveConfirmation) {
            Button(course.isArchived ? uiText("Restaurer la matière", "Restore Class") : uiText("Archiver la matière", "Archive Class")) {
                course.isArchived.toggle()
                course.updatedAt = .now
                try? modelContext.save()
            }
            Button(uiText("Annuler", "Cancel"), role: .cancel) {}
        } message: {
            Text(uiText("L’archivage conserve chapitres et séances sans afficher cette matière dans les listes actives.", "Archiving keeps chapters and sessions available without showing this class in active lists."))
        }
        .confirmationDialog(uiText("Supprimer cette matière ?", "Delete this class?"), isPresented: $deleteConfirmation) {
            Button(uiText("Supprimer la matière", "Delete Class"), role: .destructive) {
                modelContext.delete(course)
                try? modelContext.save()
            }
            Button(uiText("Annuler", "Cancel"), role: .cancel) {}
        } message: {
            Text(AcademicValidationService.shouldPreferArchive(course: course) ? uiText("Cette matière contient des données. L’archivage est plus sûr sauf si tu es certain.", "This class has associated data. Archive is safer unless you are certain.") : uiText("Cette action est définitive.", "This cannot be undone."))
        }
        .background(Color.studyDeskBackground)
        .onAppear {
            applyRequestedTab()
        }
        .onChange(of: navigation.requestedCourseTab) { _, _ in
            applyRequestedTab()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CourseColor.color(for: course.colorIdentifier).opacity(0.82), CourseColor.indigo.color.opacity(0.64)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 56)
                .overlay {
                    Image(systemName: CourseIconCatalog.sanitizedSymbolName(course.symbolName))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(course.name)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .lineLimit(2)
                Text(courseMetadata)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let nextSession {
                    Text("\(uiText("Prochaine séance", "Next session")) : \(nextSession.title), \(UniDateFormatters.dayMonth.string(from: nextSession.startTime)) \(UniDateFormatters.interval(nextSession.startTime, nextSession.endTime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                performPrimaryHeaderAction()
            } label: {
                Label(hasResumeTarget ? uiText("Continuer", "Continue") : uiText("Ajouter du contenu", "Add content"), systemImage: hasResumeTarget ? "arrow.right.circle.fill" : "square.and.arrow.down")
            }
            .buttonStyle(SoftPrimaryCourseButtonStyle())
            addMenu
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(StudyDeskTheme.surfacePrimary)
    }

    private var courseMetadata: String {
        let rawValues: [String?] = [course.code, course.semester?.name, course.professorName, course.defaultRoom]
        let values = rawValues.compactMap { $0 }.filter { !$0.isEmpty }
        return values.isEmpty ? uiText("Aucun détail confirmé", "No confirmed details") : values.joined(separator: " · ")
    }

    private var courseTabs: some View {
        HStack(spacing: 4) {
            ForEach(CourseWorkspaceTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 6) {
                        Text(item.title(for: appLanguage))
                            .font(.subheadline.weight(tab == item ? .semibold : .medium))
                            .foregroundStyle(tab == item ? .primary : .secondary)
                            .lineLimit(1)
                        Capsule()
                            .fill(tab == item ? CourseColor.indigo.color : .clear)
                            .frame(height: 2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .background(StudyDeskTheme.surfacePrimary)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var addMenu: some View {
        Menu {
            Button(uiText("Nouveau chapitre", "New Chapter"), systemImage: "list.number") { quickAddTarget = .chapter(course) }
            Button(uiText("Nouvelle séance", "New Session"), systemImage: "calendar.badge.plus") { quickAddTarget = .session(course, nil) }
            Button(uiText("Importer un document", "Import Document"), systemImage: "square.and.arrow.down") { quickAddTarget = .resource(course, nil, nil) }
            Button(uiText("Importer du contenu", "Import Content"), systemImage: "tray.and.arrow.down") { importingContent = true }
            Button(uiText("Importer un syllabus / planning", "Import Syllabus / Plan"), systemImage: "doc.text.magnifyingglass") { importingSyllabus = true }
            Button(uiText("Importer un exercice", "Import Exercise"), systemImage: "pencil.and.outline") { importingExercise = true }
            Button(uiText("Ajouter un assignment", "Add Assignment"), systemImage: "doc.badge.clock") { creatingAssignmentPlan = true }
            Divider()
            Button(uiText("Nouvelle note", "New Note"), systemImage: "note.text") { quickAddTarget = .note(course, nil, nil, nil) }
            Button(uiText("Nouvel enregistrement", "New Recording"), systemImage: "waveform") { quickAddTarget = .recording(course, nil, nil) }
            Button(uiText("Nouveau quiz", "New Quiz"), systemImage: "questionmark.app") { quickAddTarget = .quiz(course, nil, nil) }
            Button(uiText("Importer des flashcards", "Import Flashcards"), systemImage: "text.badge.plus") { quickAddTarget = .bulkFlashcards(course, nil) }
            Button(uiText("Question ouverte", "Open Question"), systemImage: "text.book.closed") { creatingEssayAssignment = true }
            Button("Research Paper", systemImage: "doc.text.magnifyingglass") { creatingResearchPaper = true }
            Button(uiText("Projet de groupe", "Group Project"), systemImage: "person.3") { creatingGroupProject = true }
            Button(uiText("Ajouter une activité externe", "Add External Activity"), systemImage: "link.badge.plus") { addingExternalActivity = true }
            Divider()
            Button(uiText("Boîte des changements", "Changes Inbox"), systemImage: "tray.full") { showingChangeMonitor = true }
            Button(uiText("Voir dans Library", "Show in Library"), systemImage: "folder") { navigation.openLibrary(course: course) }
            Button(course.isArchived ? uiText("Restaurer", "Restore") : uiText("Archiver", "Archive"), systemImage: "archivebox") { archiveConfirmation = true }
            Button(uiText("Supprimer", "Delete"), systemImage: "trash", role: .destructive) { deleteConfirmation = true }
        } label: {
            Label(uiText("Ajouter", "Add"), systemImage: "plus")
        }
        .buttonStyle(.bordered)
    }

    private func performPrimaryHeaderAction() {
        if nextSession != nil {
            tab = .sessions
        } else if !visibleChapters.isEmpty {
            tab = .chapters
        } else {
            importingContent = true
        }
    }

    private func applyRequestedTab() {
        guard navigation.openedCourseID == course.id,
              let requestedTab = navigation.requestedCourseTab else {
            return
        }
        tab = requestedTab
    }
}

struct CourseOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    let course: Course
    let nextSession: ClassSession?
    @Binding var selectedTab: CourseWorkspaceTab
    @Binding var quickAddTarget: QuickAddTarget?
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \ExternalLearningActivity.updatedAt, order: .reverse) private var externalActivities: [ExternalLearningActivity]
    @Query(sort: \MathExercise.updatedAt, order: .reverse) private var mathExercises: [MathExercise]
    @Query(sort: \EssayAssignment.updatedAt, order: .reverse) private var essayAssignments: [EssayAssignment]
    @Query(sort: \ExternalCalendarEventLink.updatedAt, order: .reverse) private var calendarLinks: [ExternalCalendarEventLink]
    @AppStorage("appleCalendarSeriesRules") private var appleCalendarSeriesRulesData = ""
    @State private var importingContent = false
    @State private var importingSyllabus = false
    @State private var importingExercise = false
    @State private var creatingEssayAssignment = false
    @State private var creatingResearchPaper = false
    @State private var creatingAssignmentPlan = false
    @State private var addingExternalActivity = false
    @State private var confirmDissociateSeries = false
    @State private var selectedExternalActivity: ExternalLearningActivity?
    @State private var selectedMathExercise: MathExercise?
    @State private var selectedEssayAssignment: EssayAssignment?
    @State private var selectedResearchPaper: StudyNote?
    @State private var selectedAssignmentPlan: StudyNote?
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private func uiText(_ french: String, _ english: String) -> String {
        appLanguage == .english ? english : french
    }

    private var visibleChapters: [Chapter] {
        course.chapters.filter { !$0.isArchived }
    }

    private var pastSessions: [ClassSession] {
        course.sessions.filter { $0.startTime < .now }.sorted { $0.startTime > $1.startTime }
    }

    private var upcomingSessions: [ClassSession] {
        course.sessions.filter { $0.startTime >= .now }.sorted { $0.startTime < $1.startTime }
    }

    private var courseTasks: [AcademicTask] {
        tasks.filter { $0.course?.id == course.id && $0.status != .completed }.prefix(5).map(\.self)
    }

    private var courseNotes: [StudyNote] {
        notes.filter { $0.course?.id == course.id && !ResearchPaperStore.isResearchPaper($0) && !QuestionBankSessionService.isProgressNote($0) }.prefix(4).map(\.self)
    }

    private var researchPapers: [StudyNote] {
        notes.filter { $0.course?.id == course.id && ResearchPaperStore.isResearchPaper($0) }
    }

    private var assignmentPlans: [StudyNote] {
        notes.filter { $0.course?.id == course.id && AssignmentPlanStore.isAssignmentPlan($0) }
    }

    private var courseResources: [AcademicResource] {
        resources.filter { $0.course?.id == course.id }.prefix(4).map(\.self)
    }

    private var courseExternalActivities: [ExternalLearningActivity] {
        externalActivities.filter { $0.course?.id == course.id }.prefix(5).map(\.self)
    }

    private var courseMathExercises: [MathExercise] {
        mathExercises.filter { $0.course?.id == course.id }.prefix(5).map(\.self)
    }

    private var courseEssayAssignments: [EssayAssignment] {
        essayAssignments.filter { $0.course?.id == course.id }.prefix(5).map(\.self)
    }

    private var isFreshCourse: Bool {
        course.chapters.isEmpty &&
            course.sessions.isEmpty &&
            courseNotes.isEmpty &&
            researchPapers.isEmpty &&
            courseResources.isEmpty &&
            courseExternalActivities.isEmpty &&
            courseMathExercises.isEmpty &&
            courseEssayAssignments.isEmpty
    }

    private var upcomingPreviewSessions: [ClassSession] {
        Array(upcomingSessions.prefix(2))
    }

    private var recentChapter: Chapter? {
        visibleChapters.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isFreshCourse {
                    CourseGettingStartedView(course: course, quickAddTarget: $quickAddTarget) {
                        importingSyllabus = true
                    }
                } else {
                    resumeWorkSection
                    upcomingWorkSection
                    recentResourcesSection
                    compactChaptersSection
                }
            }
            .frame(maxWidth: 1040, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $importingContent) {
            CourseContentImportSheet(initialCourse: course)
        }
        .sheet(isPresented: $importingSyllabus) {
            CourseSyllabusImportSheet(course: course)
        }
        .sheet(isPresented: $addingExternalActivity) {
            ExternalLearningActivityFormView(initialCourse: course, initialChapter: nil, existingActivities: externalActivities)
        }
        .sheet(isPresented: $importingExercise) {
            MathExerciseImportSheet(initialCourse: course, initialChapter: nil)
        }
        .sheet(isPresented: $creatingEssayAssignment) {
            EssayAssignmentFormView(initialCourse: course, initialChapter: nil)
        }
        .sheet(isPresented: $creatingResearchPaper) {
            ResearchPaperCreationView(course: course, chapters: visibleChapters) { note in
                selectedResearchPaper = note
            }
        }
        .sheet(isPresented: $creatingAssignmentPlan) {
            AssignmentPlannerSheet(course: course, chapters: visibleChapters) { note in
                selectedAssignmentPlan = note
            }
        }
        .confirmationDialog(uiText("Dissocier la série Apple Calendar ?", "Unlink the Apple Calendar series?"), isPresented: $confirmDissociateSeries) {
            Button(uiText("Dissocier les liens", "Unlink Links"), role: .destructive) {
                dissociateAppleCalendarSeries()
            }
            Button(uiText("Annuler", "Cancel"), role: .cancel) {}
        } message: {
            Text(uiText("Les événements Apple Calendar, les séances UniSaver et leurs contenus sont conservés. Seuls les liens et règles automatiques de cette matière sont retirés.", "Apple Calendar events, UniSaver sessions, and their content are kept. Only this class’s links and automatic rules are removed."))
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
        .sheet(item: $selectedResearchPaper) { note in
            ResearchPaperWorkspaceView(projectNote: note)
        }
        .navigationDestination(item: $selectedAssignmentPlan) { note in
            AssignmentWorkspaceView(note: note)
        }
    }

    private var resumeWorkSection: some View {
        overviewSection(uiText("Reprendre mon travail", "Resume Work"), empty: uiText("Aucun contenu consultable pour l’instant.", "No usable content yet.")) {
            VStack(alignment: .leading, spacing: 10) {
                if let recentChapter {
                    NavigationLink {
                        ChapterDetailView(chapter: recentChapter, quickAddTarget: $quickAddTarget)
                    } label: {
                        compactLinkRow(title: recentChapter.title, subtitle: "\(uiText("Chapitre", "Chapter")) \(recentChapter.number) · \(recentChapter.status.title)", systemImage: "list.number")
                    }
                    .buttonStyle(.plain)
                }
                ForEach(researchPapers.prefix(2)) { paper in
                    Button {
                        selectedResearchPaper = paper
                    } label: {
                        ResearchPaperCompactRow(note: paper)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(assignmentPlans.prefix(2)) { assignment in
                    Button {
                        selectedAssignmentPlan = assignment
                    } label: {
                        AssignmentPlanCompactRow(note: assignment)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(courseNotes.prefix(1)) { note in
                    NavigationLink {
                        NoteEditorView(note: note)
                    } label: {
                        compactLinkRow(title: note.title, subtitle: UniDateFormatters.dayMonth.string(from: note.updatedAt), systemImage: "note.text")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var upcomingWorkSection: some View {
        overviewSection(uiText("À venir", "Upcoming"), empty: uiText("Aucune séance ou échéance proche.", "No upcoming sessions or deadlines."), seeAllTitle: upcomingPreviewSessions.isEmpty && courseTasks.isEmpty ? nil : uiText("Voir tout", "See all"), seeAllAction: { selectedTab = .sessions }) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(upcomingPreviewSessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session, quickAddTarget: $quickAddTarget)
                    } label: {
                        CourseSessionSummaryRow(session: session, prominent: session.id == nextSession?.id)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(courseTasks.prefix(3)) { task in
                    compactLinkRow(title: task.title, subtitle: "\(uiText("Échéance", "Due")) \(TaskStructureService.deadlineLabel(for: task))", systemImage: "checklist")
                }
                if !courseAppleSeriesRules.isEmpty || !courseCalendarLinks.isEmpty {
                    Divider()
                    HStack {
                        Text("\(courseCalendarLinks.count) \(uiText("lien(s) Apple Calendar", "Apple Calendar link(s)"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(uiText("Modifier la règle", "Edit rule"), systemImage: "calendar.badge.clock") {
                            NotificationCenter.default.post(name: .selectAppSection, object: AppSection.planner)
                        }
                        Button(uiText("Dissocier", "Unlink"), systemImage: "link.badge.minus", role: .destructive) {
                            confirmDissociateSeries = true
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var recentResourcesSection: some View {
        overviewSection(uiText("Ressources récentes", "Recent Resources"), empty: uiText("Aucune ressource liée à cette matière.", "No resources linked to this class."), seeAllTitle: courseResources.isEmpty ? nil : uiText("Voir tout", "See all"), seeAllAction: { selectedTab = .materials }) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(courseResources) { resource in
                    NavigationLink {
                        ResourceDetailView(resource: resource)
                    } label: {
                        compactLinkRow(title: resource.title, subtitle: resource.effectiveResourceKindTitle, systemImage: resource.effectiveResourceSystemImage)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var compactChaptersSection: some View {
        overviewSection(uiText("Chapitres", "Chapters"), empty: uiText("Aucun chapitre. Crée un chapitre pour organiser les séances et contenus.", "No chapters yet. Create one to organize sessions and content."), seeAllTitle: visibleChapters.isEmpty ? nil : uiText("Voir tout", "See all"), seeAllAction: { selectedTab = .chapters }) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(visibleChapters) { chapter in
                    NavigationLink {
                        ChapterDetailView(chapter: chapter, quickAddTarget: $quickAddTarget)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(chapter.number)")
                                .font(.headline.monospacedDigit())
                                .frame(width: 34, height: 34)
                                .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chapter.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Text("\(chapter.sessions.count) \(uiText("séance(s)", "session(s)")) · \(chapter.status.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    if chapter.id != visibleChapters.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func compactLinkRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 26)
                .foregroundStyle(StudyDeskTheme.accentPrimary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func infoCard(_ title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .deskCard()
    }

    private func overviewSection<Content: View>(_ title: String, empty: String, seeAllTitle: String? = nil, seeAllAction: (() -> Void)? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline.weight(.semibold))
                Spacer()
                if let seeAllTitle, let seeAllAction {
                    Button(seeAllTitle, action: seeAllAction)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(CourseColor.indigo.color)
                }
            }
            if sectionIsEmpty(title) {
                Text(empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                content()
            }
        }
        .padding(14)
        .deskCard()
    }

    private func sectionIsEmpty(_ title: String) -> Bool {
        switch title {
        case uiText("Reprendre mon travail", "Resume Work"): recentChapter == nil && researchPapers.isEmpty && assignmentPlans.isEmpty && courseNotes.isEmpty
        case uiText("À venir", "Upcoming"): upcomingPreviewSessions.isEmpty && courseTasks.isEmpty
        case uiText("Ressources récentes", "Recent Resources"): courseResources.isEmpty
        case uiText("Chapitres", "Chapters"): visibleChapters.isEmpty
        default: true
        }
    }

    private var courseCalendarLinks: [ExternalCalendarEventLink] {
        calendarLinks.filter { $0.course?.id == course.id || $0.session?.course?.id == course.id }
    }

    private var courseAppleSeriesRules: [AppleCalendarSeriesRule] {
        AppleCalendarSeriesRuleStore.decode(appleCalendarSeriesRulesData).filter { $0.courseID == course.id.uuidString }
    }

    private func appleLink(for session: ClassSession) -> ExternalCalendarEventLink? {
        calendarLinks.first { $0.session?.id == session.id }
    }

    private func dissociateAppleCalendarSeries() {
        for link in courseCalendarLinks {
            modelContext.delete(link)
        }
        let remainingRules = AppleCalendarSeriesRuleStore.decode(appleCalendarSeriesRulesData).filter { $0.courseID != course.id.uuidString }
        appleCalendarSeriesRulesData = AppleCalendarSeriesRuleStore.encode(remainingRules)
        try? modelContext.save()
    }
}

private struct CourseSessionSummaryRow: View {
    let session: ClassSession
    var prominent = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(CourseColor.color(for: session.course?.colorIdentifier ?? "blue"))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(prominent ? .headline : .body.weight(.medium))
                    .lineLimit(1)
                Text("\(UniDateFormatters.dayMonth.string(from: session.startTime)) · \(UniDateFormatters.interval(session.startTime, session.endTime))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let room = session.room, !room.isEmpty {
                    Text(room)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct CourseGettingStartedView: View {
    let course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    let importSyllabusAction: () -> Void
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private func uiText(_ french: String, _ english: String) -> String {
        appLanguage == .english ? english : french
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(uiText("Construisons cette matière", "Let’s Build This Class"))
                .font(.headline.weight(.semibold))
            Text(uiText("Commence par une structure claire ou importe le planning fourni par ton professeur.", "Start with a clear structure or import the plan your instructor provided."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                gettingStartedButton(
                    title: uiText("Créer un chapitre", "Create Chapter"),
                    subtitle: uiText("Organiser les séances et documents.", "Organize sessions and documents."),
                    systemImage: "list.number",
                    action: { quickAddTarget = .chapter(course) }
                )
                gettingStartedButton(
                    title: uiText("Importer un syllabus", "Import Syllabus"),
                    subtitle: uiText("Préparer chapitres et échéances.", "Prepare chapters and deadlines."),
                    systemImage: "doc.text.magnifyingglass",
                    action: importSyllabusAction
                )
            }
        }
        .padding(16)
        .deskCard()
    }

    private func gettingStartedButton(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CourseColor.indigo.color)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(StudyDeskTheme.borderSubtle)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SoftPrimaryCourseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [CourseColor.sky.color, CourseColor.indigo.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .shadow(color: CourseColor.indigo.color.opacity(configuration.isPressed ? 0.05 : 0.18), radius: configuration.isPressed ? 2 : 8, y: configuration.isPressed ? 1 : 4)
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}

private struct CourseSyllabusImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var course: Course
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \ClassSession.startTime) private var sessions: [ClassSession]
    @Query(sort: \ExternalCalendarEventLink.updatedAt, order: .reverse) private var calendarLinks: [ExternalCalendarEventLink]

    @State private var selectedURL: URL?
    @State private var sourceResource: AcademicResource?
    @State private var extractedText = ""
    @State private var chapters: [SyllabusChapterProposal] = []
    @State private var sessionsToImport: [SyllabusSessionProposal] = []
    @State private var tasks: [SyllabusTaskProposal] = []
    @State private var exams: [SyllabusExamProposal] = []
    @State private var messages: [String] = []
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var selectedFloatingTimeZoneID = TimeZone.current.identifier

    private let fileStore = AcademicFileStore()

    private var canConfirm: Bool {
        sourceResource != nil &&
        (
            chapters.contains { $0.action != .ignore } ||
            sessionsToImport.contains { $0.action != .ignore } ||
            tasks.contains { $0.action != .ignore } ||
            exams.contains { $0.action != .ignore && $0.date != nil }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sourcePanel
                Divider()
                List {
                    if !messages.isEmpty {
                        Section("Messages / Messages") {
                            ForEach(messages, id: \.self) { message in
                                Label(message, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Section("Texte reconnu ou saisi / Recognized or edited text") {
                        TextEditor(text: $extractedText)
                            .font(.body.monospaced())
                            .frame(minHeight: 120)
                        Button("Analyser le texte / Analyze text", systemImage: "wand.and.stars") {
                            analyzeCurrentText()
                        }
                        .disabled(extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Section("Chapitres / Chapters") {
                        if chapters.isEmpty {
                            Text("Aucun chapitre proposé. Ajoute ou corrige le texte reconnu, puis relance l’analyse.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach($chapters) { $proposal in
                            SyllabusChapterProposalRow(proposal: $proposal)
                        }
                    }
                    Section("Séances / Sessions") {
                        if sessionsToImport.isEmpty {
                            Text("Aucune séance proposée.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach($sessionsToImport) { $proposal in
                            SyllabusSessionProposalRow(
                                proposal: $proposal,
                                chapterChoices: chapters,
                                existingSessions: existingCourseSessions
                            )
                        }
                    }
                    Section("Échéances / Deadlines") {
                        if tasks.isEmpty && exams.isEmpty {
                            Text("Aucun devoir ou examen proposé.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach($tasks) { $proposal in
                            SyllabusTaskProposalRow(proposal: $proposal, chapterChoices: chapters)
                        }
                        ForEach($exams) { $proposal in
                            SyllabusExamProposalRow(proposal: $proposal, chapterChoices: chapters)
                        }
                    }
                    Section("Récapitulatif / Summary") {
                        Label("\(chapters.filter { $0.action == .create }.count) chapitre(s) à créer", systemImage: "list.number")
                        Label("\(sessionsToImport.filter { $0.action == .create }.count) séance(s) à créer", systemImage: "calendar")
                        Label("\(sessionsToImport.filter { $0.action == .associate }.count) séance(s) à associer", systemImage: "link")
                        Label("\(tasks.filter { $0.action == .create }.count) tâche(s) à créer", systemImage: "checklist")
                        Label("\(exams.filter { $0.action == .create && $0.date != nil }.count) examen(s) daté(s) à créer", systemImage: "graduationcap")
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.bar)
                }
            }
            .navigationTitle("Importer un syllabus / planning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "Import..." : "Confirmer") {
                        confirmImport()
                    }
                    .disabled(!canConfirm || isImporting)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 680)
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Choisir PDF, DOCX, image ou ICS", systemImage: "doc.badge.plus") {
                    chooseFile()
                }
                if let selectedURL {
                    Text(selectedURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sourceResource {
                    NavigationLink {
                        ResourceDetailView(resource: sourceResource)
                    } label: {
                        Label("Ouvrir la source", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            Text("Le document original est conservé dans UniSaver. Rien n’est créé dans le cours avant confirmation. Les champs incertains restent visibles et modifiables.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if sessionsToImport.contains(where: \.isFloatingTime) {
                Picker("Fuseau source des dates sans TZID", selection: $selectedFloatingTimeZoneID) {
                    ForEach(CalendarICSParser.suggestedTimeZoneIdentifiers, id: \.self) { identifier in
                        Text(identifier).tag(identifier)
                    }
                }
                .onChange(of: selectedFloatingTimeZoneID) { _, _ in
                    if let selectedURL, selectedURL.pathExtension.localizedLowercase == "ics" {
                        load(url: selectedURL)
                    }
                }
            }
        }
        .padding()
    }

    private var existingCourseSessions: [ClassSession] {
        sessions.filter { $0.course?.id == course.id }.sorted { $0.startTime < $1.startTime }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["pdf", "docx", "png", "jpg", "jpeg", "heic", "ics"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = false
        panel.message = "Choisis un syllabus, planning ou calendrier"
        guard panel.runModal() == .OK, let url = panel.url else {
            errorMessage = "Sélection annulée. / Selection cancelled."
            return
        }
        load(url: url)
    }

    private func load(url: URL) {
        selectedURL = url
        errorMessage = nil
        messages = []
        chapters = []
        sessionsToImport = []
        tasks = []
        exams = []
        do {
            sourceResource = try importOrReuseSourceResource(url)
            let extracted = try SyllabusExtractor.extract(
                from: url,
                defaultFloatingTimeZone: TimeZone(identifier: selectedFloatingTimeZoneID) ?? .current,
                existingSessions: existingCourseSessions
            )
            extractedText = extracted.text
            messages = extracted.messages
            chapters = extracted.chapters
            sessionsToImport = extracted.sessions
            tasks = extracted.tasks
            exams = extracted.exams
            applyAppleCalendarHints()
        } catch {
            errorMessage = "Import impossible : \(error.localizedDescription)"
        }
    }

    private func importOrReuseSourceResource(_ url: URL) throws -> AcademicResource {
        let draft = ResourceImportDraft(
            fileURL: url,
            title: url.deletingPathExtension().lastPathComponent,
            resourceDescription: "Source syllabus/planning pour \(course.name)",
            course: course,
            chapter: nil,
            session: nil,
            tags: ["syllabus", "planning"]
        )
        if let duplicate = ResourceImportService.duplicateResource(hash: try fileStore.fingerprint(for: url), draft: draft, existingResources: resources) {
            return duplicate
        }
        return try ResourceImportService.submit(
            draft: draft,
            existingResources: resources,
            modelContext: modelContext,
            fileStore: fileStore,
            allowDuplicate: true
        )
    }

    private func analyzeCurrentText() {
        let extracted = SyllabusExtractor.extract(
            text: extractedText,
            sourceName: sourceResource?.title ?? selectedURL?.lastPathComponent ?? "Texte manuel",
            existingSessions: existingCourseSessions
        )
        messages = extracted.messages
        chapters = extracted.chapters
        sessionsToImport = extracted.sessions
        tasks = extracted.tasks
        exams = extracted.exams
        applyAppleCalendarHints()
    }

    private func applyAppleCalendarHints() {
        let links = calendarLinks.filter { $0.course?.id == course.id }
        guard !links.isEmpty else { return }
        for index in sessionsToImport.indices {
            guard let startDate = sessionsToImport[index].startDate else { continue }
            guard let link = links.first(where: { link in
                abs(link.occurrenceStartDate.timeIntervalSince(startDate)) < 1800 ||
                (Calendar.current.isDate(link.occurrenceStartDate, inSameDayAs: startDate) &&
                 link.titleSnapshot.localizedCaseInsensitiveContains(sessionsToImport[index].title.prefix(24)))
            }) else { continue }
            if let linkedSession = link.session {
                sessionsToImport[index].existingSessionID = linkedSession.id
                sessionsToImport[index].action = .associate
                sessionsToImport[index].uncertainty = [sessionsToImport[index].uncertainty, "Correspondance Apple Calendar confirmée : \(link.calendarTitleSnapshot)."].compactMap { $0 }.joined(separator: " ")
            } else {
                sessionsToImport[index].uncertainty = [sessionsToImport[index].uncertainty, "Événement Apple Calendar déjà associé à cette matière, mais sans séance UniSaver liée : vérifie avant de créer une nouvelle séance."].compactMap { $0 }.joined(separator: " ")
            }
        }
    }

    private func confirmImport() {
        guard let sourceResource else {
            errorMessage = "Aucune source importée. / No imported source."
            return
        }
        isImporting = true
        var createdChaptersByProposalID: [UUID: Chapter] = [:]
        do {
            for proposal in chapters where proposal.action == .create {
                let chapter = Chapter(
                    number: proposal.number,
                    title: proposal.title,
                    chapterDescription: provenance("Source: \(sourceResource.title)", proposal.provenance, proposal.uncertainty),
                    order: course.chapters.count + createdChaptersByProposalID.count,
                    course: course
                )
                modelContext.insert(chapter)
                createdChaptersByProposalID[proposal.id] = chapter
            }

            for proposal in sessionsToImport {
                let chapter = chapter(for: proposal.chapterProposalID, created: createdChaptersByProposalID)
                switch proposal.action {
                case .create:
                    guard let start = proposal.startDate, let end = proposal.endDate else { continue }
                    let session = ClassSession(
                        number: (course.sessions.map(\.number).max() ?? 0) + 1,
                        title: proposal.title,
                        sessionDescription: provenance("Source: \(sourceResource.title)", proposal.provenance, proposal.uncertainty),
                        date: Calendar.current.startOfDay(for: start),
                        startTime: start,
                        endTime: max(end, start.addingTimeInterval(900)),
                        room: proposal.location.nilIfBlank,
                        course: course,
                        chapter: chapter
                    )
                    modelContext.insert(session)
                case .associate:
                    if let existing = existingCourseSessions.first(where: { $0.id == proposal.existingSessionID }) {
                        existing.chapter = chapter ?? existing.chapter
                        existing.sessionDescription = appendProvenance(existing.sessionDescription, sourceResource: sourceResource, provenance: proposal.provenance, uncertainty: proposal.uncertainty)
                        existing.updatedAt = .now
                    }
                case .ignore:
                    break
                }
            }

            for proposal in tasks where proposal.action == .create {
                guard let dueDate = proposal.dueDate else { continue }
                let task = AcademicTask(
                    title: proposal.title,
                    taskDescription: provenance("Source: \(sourceResource.title)", proposal.provenance, proposal.uncertainty),
                    dueDate: dueDate,
                    course: course,
                    chapter: chapter(for: proposal.chapterProposalID, created: createdChaptersByProposalID)
                )
                modelContext.insert(task)
            }

            for proposal in exams where proposal.action == .create {
                guard let date = proposal.date else { continue }
                let exam = Exam(
                    title: proposal.title,
                    date: Calendar.current.startOfDay(for: date),
                    startTime: proposal.startTime,
                    endTime: proposal.endTime,
                    room: proposal.location.nilIfBlank,
                    notes: provenance("Source: \(sourceResource.title)", proposal.provenance, proposal.uncertainty),
                    course: course,
                    chapters: chapter(for: proposal.chapterProposalID, created: createdChaptersByProposalID).map { [$0] } ?? []
                )
                modelContext.insert(exam)
            }

            course.updatedAt = .now
            try modelContext.save()
            isImporting = false
            dismiss()
        } catch {
            isImporting = false
            errorMessage = "Enregistrement impossible : \(error.localizedDescription)"
        }
    }

    private func chapter(for proposalID: UUID?, created: [UUID: Chapter]) -> Chapter? {
        guard let proposalID else { return nil }
        if let created = created[proposalID] { return created }
        return course.chapters.first { $0.id == proposalID }
    }

    private func provenance(_ source: String, _ detail: String, _ uncertainty: String?) -> String {
        [source, detail, uncertainty.map { "À vérifier / Check: \($0)" }].compactMap { $0 }.joined(separator: "\n")
    }

    private func appendProvenance(_ current: String, sourceResource: AcademicResource, provenance: String, uncertainty: String?) -> String {
        let addition = self.provenance("Source: \(sourceResource.title)", provenance, uncertainty)
        guard !current.contains(addition) else { return current }
        return [current, addition].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

private enum SyllabusProposalAction: String, CaseIterable, Identifiable {
    case create
    case associate
    case ignore

    var id: String { rawValue }
    var title: String {
        switch self {
        case .create: "Créer"
        case .associate: "Associer"
        case .ignore: "Ignorer"
        }
    }
}

private struct SyllabusChapterProposal: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var number: Int
    var provenance: String
    var uncertainty: String?
    var action: SyllabusProposalAction = .create
}

private struct SyllabusSessionProposal: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var startDate: Date?
    var endDate: Date?
    var location: String
    var provenance: String
    var uncertainty: String?
    var isFloatingTime = false
    var chapterProposalID: UUID?
    var existingSessionID: UUID?
    var action: SyllabusProposalAction = .create
}

private struct SyllabusTaskProposal: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var dueDate: Date?
    var provenance: String
    var uncertainty: String?
    var chapterProposalID: UUID?
    var action: SyllabusProposalAction = .create
}

private struct SyllabusExamProposal: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var date: Date?
    var startTime: Date?
    var endTime: Date?
    var location: String
    var provenance: String
    var uncertainty: String?
    var chapterProposalID: UUID?
    var action: SyllabusProposalAction = .create
}

private struct SyllabusExtractionResult {
    var text: String
    var messages: [String]
    var chapters: [SyllabusChapterProposal]
    var sessions: [SyllabusSessionProposal]
    var tasks: [SyllabusTaskProposal]
    var exams: [SyllabusExamProposal]
}

private enum SyllabusExtractor {
    static func extract(from url: URL, defaultFloatingTimeZone: TimeZone, existingSessions: [ClassSession]) throws -> SyllabusExtractionResult {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let ext = url.pathExtension.localizedLowercase
        switch ext {
        case "ics":
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = CalendarICSParser.parse(text, defaultFloatingTimeZone: defaultFloatingTimeZone)
            return extract(calendarEvents: parsed.events, errors: parsed.errors, sourceName: url.lastPathComponent, existingSessions: existingSessions)
        case "pdf":
            return extractPDF(url: url, existingSessions: existingSessions)
        case "docx":
            return SyllabusExtractionResult(
                text: "",
                messages: ["DOCX importé comme source. L’extraction fiable du texte DOCX n’est pas disponible ici ; colle les passages du planning dans la zone de texte puis relance l’analyse."],
                chapters: [],
                sessions: [],
                tasks: [],
                exams: []
            )
        case "png", "jpg", "jpeg", "heic":
            return SyllabusExtractionResult(
                text: "",
                messages: ["Image importée comme source. La reconnaissance fiable n’est pas activée dans ce parcours ; saisis ou colle le texte reconnu manuellement avant confirmation."],
                chapters: [],
                sessions: [],
                tasks: [],
                exams: []
            )
        default:
            return SyllabusExtractionResult(
                text: "",
                messages: ["Format non reconnu pour l’extraction automatique. Le fichier reste conservé comme source."],
                chapters: [],
                sessions: [],
                tasks: [],
                exams: []
            )
        }
    }

    static func extract(text: String, sourceName: String, existingSessions: [ClassSession]) -> SyllabusExtractionResult {
        parseLines(text.components(separatedBy: .newlines), sourceName: sourceName, existingSessions: existingSessions)
    }

    private static func extractPDF(url: URL, existingSessions: [ClassSession]) -> SyllabusExtractionResult {
        guard let document = PDFDocument(url: url) else {
            return SyllabusExtractionResult(text: "", messages: ["PDF illisible par PDFKit."], chapters: [], sessions: [], tasks: [], exams: [])
        }
        var lines: [String] = []
        var fullText: [String] = []
        for index in 0..<document.pageCount {
            let pageText = document.page(at: index)?.string ?? ""
            fullText.append(pageText)
            for rawLine in pageText.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                lines.append("[p.\(index + 1)] \(line)")
            }
        }
        var result = parseLines(lines, sourceName: url.lastPathComponent, existingSessions: existingSessions)
        result.text = fullText.joined(separator: "\n\n")
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.messages.append("Le PDF ne fournit pas de texte extractible. Utilise une version OCR ou saisis les informations manuellement.")
        }
        return result
    }

    private static func extract(calendarEvents: [CalendarImportEvent], errors: [CalendarImportError], sourceName: String, existingSessions: [ClassSession]) -> SyllabusExtractionResult {
        let sessions = calendarEvents.map { event in
            let match = matchingSession(for: event.title, startDate: event.startDate, existingSessions: existingSessions)
            return SyllabusSessionProposal(
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location ?? "",
                provenance: "\(sourceName) · \(event.sourceTimeDescription)",
                uncertainty: event.recurrenceNote,
                isFloatingTime: event.isFloatingTime,
                existingSessionID: match?.id,
                action: match == nil ? .create : .associate
            )
        }
        return SyllabusExtractionResult(
            text: calendarEvents.map { "\($0.title) \($0.sourceTimeDescription) \($0.location ?? "")" }.joined(separator: "\n"),
            messages: errors.map { "Ligne \($0.line): \($0.message)" },
            chapters: [],
            sessions: sessions,
            tasks: [],
            exams: []
        )
    }

    private static func parseLines(_ lines: [String], sourceName: String, existingSessions: [ClassSession]) -> SyllabusExtractionResult {
        var messages: [String] = []
        var chapters: [SyllabusChapterProposal] = []
        var sessions: [SyllabusSessionProposal] = []
        var tasks: [SyllabusTaskProposal] = []
        var exams: [SyllabusExamProposal] = []
        var currentChapterID: UUID?

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count >= 4 else { continue }
            let clean = line.replacingOccurrences(of: #"^\[p\.\d+\]\s*"#, with: "", options: .regularExpression)
            let provenance = "\(sourceName) · ligne \(index + 1)\(pageHint(from: line).map { " · \($0)" } ?? "")"
            let lower = clean.lowercased()
            let parsedDate = parseDate(in: clean)
            if lower.contains("chapter") || lower.contains("chapitre") || lower.contains("module") || lower.contains("topic") || lower.contains("week ") || lower.contains("semaine") {
                let proposal = SyllabusChapterProposal(
                    title: strippedPrefix(clean),
                    number: chapters.count + 1,
                    provenance: provenance,
                    uncertainty: clean.count < 8 ? "Titre court ou incomplet." : nil
                )
                chapters.append(proposal)
                currentChapterID = proposal.id
                continue
            }
            if lower.contains("exam") || lower.contains("examen") || lower.contains("midterm") || lower.contains("final") || lower.contains("contrôle") {
                exams.append(SyllabusExamProposal(
                    title: strippedPrefix(clean),
                    date: parsedDate?.date,
                    startTime: parsedDate?.date,
                    endTime: parsedDate?.date.addingTimeInterval(7200),
                    location: location(in: clean) ?? "",
                    provenance: provenance,
                    uncertainty: parsedDate == nil ? "Date absente : aucune date d’examen n’a été inventée." : parsedDate?.uncertainty,
                    chapterProposalID: currentChapterID,
                    action: parsedDate == nil ? .ignore : .create
                ))
                continue
            }
            if lower.contains("assignment") || lower.contains("homework") || lower.contains("devoir") || lower.contains("due") || lower.contains("lecture") || lower.contains("reading") {
                tasks.append(SyllabusTaskProposal(
                    title: strippedPrefix(clean),
                    dueDate: parsedDate?.date,
                    provenance: provenance,
                    uncertainty: parsedDate == nil ? "Échéance sans date détectée." : parsedDate?.uncertainty,
                    chapterProposalID: currentChapterID,
                    action: parsedDate == nil ? .ignore : .create
                ))
                continue
            }
            if let parsedDate, lower.contains("session") || lower.contains("séance") || lower.contains("class") || lower.contains("lecture") || lower.contains("course") {
                let match = matchingSession(for: clean, startDate: parsedDate.date, existingSessions: existingSessions)
                sessions.append(SyllabusSessionProposal(
                    title: strippedPrefix(clean),
                    startDate: parsedDate.date,
                    endDate: parsedDate.date.addingTimeInterval(5400),
                    location: location(in: clean) ?? "",
                    provenance: provenance,
                    uncertainty: parsedDate.uncertainty,
                    chapterProposalID: currentChapterID,
                    existingSessionID: match?.id,
                    action: match == nil ? .create : .associate
                ))
                continue
            }
            if hasAmbiguousDate(in: clean) {
                messages.append("Date ambiguë ignorée ligne \(index + 1): \(clean)")
            }
        }

        return SyllabusExtractionResult(
            text: lines.joined(separator: "\n"),
            messages: messages,
            chapters: chapters,
            sessions: sessions,
            tasks: tasks,
            exams: exams
        )
    }

    private struct ParsedDate {
        var date: Date
        var uncertainty: String?
    }

    private static func parseDate(in text: String) -> ParsedDate? {
        let patterns = [
            #"\b\d{4}-\d{2}-\d{2}(?:\s+\d{1,2}:\d{2})?\b"#,
            #"\b\d{1,2}/\d{1,2}/\d{4}(?:\s+\d{1,2}:\d{2})?\b"#,
            #"\b\d{1,2}-\d{1,2}-\d{4}(?:\s+\d{1,2}:\d{2})?\b"#
        ]
        for pattern in patterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let raw = String(text[range])
            for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd", "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "dd-MM-yyyy HH:mm", "dd-MM-yyyy"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .current
                formatter.dateFormat = format
                if let date = formatter.date(from: raw) {
                    return ParsedDate(date: date, uncertainty: nil)
                }
            }
        }
        return nil
    }

    private static func hasAmbiguousDate(in text: String) -> Bool {
        text.range(of: #"\b\d{1,2}/\d{1,2}\b"#, options: .regularExpression) != nil ||
        text.range(of: #"\b\d{1,2}-\d{1,2}\b"#, options: .regularExpression) != nil
    }

    private static func matchingSession(for title: String, startDate: Date, existingSessions: [ClassSession]) -> ClassSession? {
        existingSessions.first { session in
            abs(session.startTime.timeIntervalSince(startDate)) < 1800 ||
            (Calendar.current.isDate(session.startTime, inSameDayAs: startDate) && normalized(session.title) == normalized(title))
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pageHint(from line: String) -> String? {
        guard let range = line.range(of: #"^\[p\.\d+\]"#, options: .regularExpression) else { return nil }
        return String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private static func strippedPrefix(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^\[p\.\d+\]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(chapter|chapitre|module|topic|week|semaine|session|séance|assignment|homework|devoir|exam|examen|midterm|final)\s*[:#-]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func location(in text: String) -> String? {
        let markers = ["room", "salle", "location", "lieu"]
        for marker in markers {
            if let range = text.range(of: "\(marker)\\s*:?\\s*([^,;]+)", options: [.regularExpression, .caseInsensitive]) {
                return String(text[range]).components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}

private struct SyllabusChapterProposalRow: View {
    @Binding var proposal: SyllabusChapterProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: $proposal.action) {
                ForEach([SyllabusProposalAction.create, .ignore]) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.segmented)
            TextField("Titre", text: $proposal.title)
            Stepper("Numéro \(proposal.number)", value: $proposal.number, in: 1...99)
            SyllabusProvenanceView(provenance: proposal.provenance, uncertainty: proposal.uncertainty)
        }
    }
}

private struct SyllabusSessionProposalRow: View {
    @Binding var proposal: SyllabusSessionProposal
    let chapterChoices: [SyllabusChapterProposal]
    let existingSessions: [ClassSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: $proposal.action) {
                ForEach(SyllabusProposalAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.segmented)
            TextField("Titre", text: $proposal.title)
            if let startDate = proposal.startDate, let endDate = proposal.endDate {
                Text("\(startDate.formatted(date: .abbreviated, time: .shortened)) – \(endDate.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
            TextField("Lieu", text: $proposal.location)
            Picker("Chapitre", selection: $proposal.chapterProposalID) {
                Text("Sans chapitre").tag(UUID?.none)
                ForEach(chapterChoices) { chapter in
                    Text(chapter.title).tag(Optional(chapter.id))
                }
            }
            if proposal.action == .associate {
                Picker("Séance existante", selection: $proposal.existingSessionID) {
                    Text("Choisir").tag(UUID?.none)
                    ForEach(existingSessions) { session in
                        Text("\(session.title) · \(UniDateFormatters.dayMonth.string(from: session.startTime)) \(UniDateFormatters.time.string(from: session.startTime))").tag(Optional(session.id))
                    }
                }
            }
            SyllabusProvenanceView(provenance: proposal.provenance, uncertainty: proposal.uncertainty)
        }
    }
}

private struct SyllabusTaskProposalRow: View {
    @Binding var proposal: SyllabusTaskProposal
    let chapterChoices: [SyllabusChapterProposal]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: $proposal.action) {
                ForEach([SyllabusProposalAction.create, .ignore]) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.segmented)
            TextField("Titre", text: $proposal.title)
            if let dueDate = proposal.dueDate {
                DatePicker("Échéance", selection: Binding(get: { dueDate }, set: { proposal.dueDate = $0 }))
            } else {
                Text("Date absente : ignorée tant qu’une date n’est pas fournie.")
                    .foregroundStyle(.orange)
            }
            Picker("Chapitre", selection: $proposal.chapterProposalID) {
                Text("Sans chapitre").tag(UUID?.none)
                ForEach(chapterChoices) { chapter in
                    Text(chapter.title).tag(Optional(chapter.id))
                }
            }
            SyllabusProvenanceView(provenance: proposal.provenance, uncertainty: proposal.uncertainty)
        }
    }
}

private struct SyllabusExamProposalRow: View {
    @Binding var proposal: SyllabusExamProposal
    let chapterChoices: [SyllabusChapterProposal]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: $proposal.action) {
                ForEach([SyllabusProposalAction.create, .ignore]) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.segmented)
            TextField("Titre", text: $proposal.title)
            if let date = proposal.date {
                DatePicker("Date", selection: Binding(get: { date }, set: { proposal.date = $0 }))
            } else {
                Text("Examen sans date : UniSaver ne crée rien tant qu’une date réelle n’est pas indiquée.")
                    .foregroundStyle(.orange)
            }
            TextField("Lieu", text: $proposal.location)
            Picker("Chapitre", selection: $proposal.chapterProposalID) {
                Text("Sans chapitre").tag(UUID?.none)
                ForEach(chapterChoices) { chapter in
                    Text(chapter.title).tag(Optional(chapter.id))
                }
            }
            SyllabusProvenanceView(provenance: proposal.provenance, uncertainty: proposal.uncertainty)
        }
    }
}

private struct SyllabusProvenanceView: View {
    let provenance: String
    let uncertainty: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(provenance)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let uncertainty {
                Label(uncertainty, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct CourseMaterialsView: View {
    @Environment(\.modelContext) private var modelContext
    let course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @State private var importingContent = false

    private var courseResources: [AcademicResource] {
        resources.filter { $0.course?.id == course.id }
    }

    private var courseNotes: [StudyNote] {
        notes.filter { $0.course?.id == course.id && !QuestionBankSessionService.isProgressNote($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Section {
                    ResourceCollectionView(resources: courseResources, emptyTitle: "Aucun document pour \(course.name)") {
                        quickAddTarget = .resource(course, nil, nil)
                    }
                    .frame(minHeight: 220)
                } header: {
                    HStack {
                        Text("Documents")
                            .font(.headline)
                        Spacer()
                        Button("Importer du contenu", systemImage: "square.and.arrow.down") {
                            importingContent = true
                        }
                    }
                }

                Section {
                    NoteListView(notes: courseNotes, emptyTitle: "Aucune note pour \(course.name)") {
                        let note = StudyNote(title: "\(course.name) note", course: course)
                        modelContext.insert(note)
                        try? modelContext.save()
                        return note
                    }
                    .frame(minHeight: 220)
                } header: {
                    HStack {
                        Text("Notes")
                            .font(.headline)
                        Spacer()
                        Button("Nouvelle note", systemImage: "note.text") {
                            quickAddTarget = .note(course, nil, nil, nil)
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $importingContent) {
            CourseContentImportSheet(initialCourse: course)
        }
    }
}

struct CourseRecordingsView: View {
    let course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]

    private var courseRecordings: [CourseRecording] {
        recordings.filter { $0.course?.id == course.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Enregistrements")
                    .font(.headline)
                Spacer()
                Button("Enregistrer", systemImage: "waveform.badge.mic") {
                    quickAddTarget = .recording(course, nil, nil)
                }
            }
            if courseRecordings.isEmpty {
                EmptyStateView(
                    title: "Aucun enregistrement",
                    message: "Importe un audio ou enregistre une séance pour retrouver la transcription ici.",
                    systemImage: "waveform",
                    actionTitle: "Ajouter un enregistrement",
                    action: { quickAddTarget = .recording(course, nil, nil) }
                )
            } else {
                RecordingListView(recordings: courseRecordings)
            }
        }
        .padding()
    }
}

enum AssignmentPlanStage: String, Codable, CaseIterable, Identifiable {
    case extracted
    case reviewed
    case planned
    case confirmed
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extracted: "Extraction"
        case .reviewed: "Requirements reviewed"
        case .planned: "Plan drafted"
        case .confirmed: "Plan confirmed"
        case .completed: "Completed"
        }
    }
}

struct AssignmentRequirement: Codable, Identifiable {
    var id = UUID()
    var title: String
    var detail: String
    var kind: String
    var sourceReference: String
    var supportingText: String
    var uncertainty: String?
    var isReviewed = false
}

struct AssignmentMilestoneDraft: Codable, Identifiable {
    var id = UUID()
    var title: String
    var detail: String
    var dueDate: Date?
    var estimatedMinutes: Int
    var priority: AcademicTaskPriority
    var dependencyIDs: [UUID] = []
    var sourceRequirementIDs: [UUID] = []
    var isApproved = true
    var isLocked = false
    var createdTaskID: UUID?
}

struct AssignmentWorkSessionDraft: Codable, Identifiable {
    var id = UUID()
    var title: String
    var startDate: Date
    var endDate: Date
    var milestoneID: UUID?
    var overlapWarning: String?
    var isApproved = false
    var isLocked = false
    var createdStudyBlockID: UUID?
}

struct AssignmentPlanProject: Codable {
    var schemaVersion = 1
    var title: String
    var courseName: String
    var chapterTitle: String?
    var stage: AssignmentPlanStage = .extracted
    var pastedInstructions = ""
    var extractedText = ""
    var sourceResourceID: UUID?
    var sourceName = "Manual instructions"
    var deadline: Date?
    var deadlineUncertainty: String?
    var deliverables: [AssignmentRequirement] = []
    var constraints: [AssignmentRequirement] = []
    var gradingCriteria: [AssignmentRequirement] = []
    var explicitIntermediateDeadlines: [AssignmentRequirement] = []
    var unresolvedQuestions: [String] = []
    var milestones: [AssignmentMilestoneDraft] = []
    var sessions: [AssignmentWorkSessionDraft] = []
    var dailyWorkloadMinutes = 120
    var workingStartHour = 9
    var workingEndHour = 18
    var breakMinutes = 15
    var shortfallWarning: String?
    var lastSavedAt: Date = .now

    var allRequirements: [AssignmentRequirement] {
        deliverables + constraints + gradingCriteria + explicitIntermediateDeadlines
    }

    var nextAction: String {
        if allRequirements.contains(where: { !$0.isReviewed && ($0.uncertainty != nil || $0.kind == "deadline") }) {
            return "Review uncertain requirements"
        }
        if milestones.isEmpty {
            return "Approve milestones"
        }
        if sessions.isEmpty {
            return "Review proposed work sessions"
        }
        if stage != .confirmed {
            return "Confirm plan"
        }
        if let next = milestones.first(where: { $0.createdTaskID == nil || $0.isApproved }) {
            return next.title
        }
        return "Work through the confirmed plan"
    }

    var progress: Double {
        guard !milestones.isEmpty else { return allRequirements.isEmpty ? 0 : 0.2 }
        let confirmed = milestones.filter { $0.createdTaskID != nil }.count
        return min(1, max(0.15, Double(confirmed) / Double(milestones.count)))
    }
}

enum AssignmentPlanStore {
    static let marker = "UNISAVER_ASSIGNMENT_PLAN_V1:"

    static func isAssignmentPlan(_ note: StudyNote) -> Bool {
        note.body.hasPrefix(marker)
    }

    static func decode(_ note: StudyNote) -> AssignmentPlanProject {
        let raw = note.body.hasPrefix(marker) ? String(note.body.dropFirst(marker.count)) : ""
        if let data = raw.data(using: .utf8),
           let project = try? JSONDecoder().decode(AssignmentPlanProject.self, from: data) {
            return project
        }
        return AssignmentPlanProject(title: note.title, courseName: note.course?.name ?? "Course", chapterTitle: note.chapter?.title)
    }

    static func save(_ project: AssignmentPlanProject, into note: StudyNote) {
        var copy = project
        copy.lastSavedAt = .now
        let data = (try? JSONEncoder().encode(copy)) ?? Data()
        note.title = copy.title
        note.body = marker + (String(data: data, encoding: .utf8) ?? "{}")
        note.updatedAt = .now
    }
}

enum AcademicChangeSourceKind: String, Codable, CaseIterable, Identifiable {
    case moodle
    case appleCalendar
    case revisedDocument

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        let english = language == .english
        return switch self {
        case .moodle: english ? "Moodle" : "Moodle"
        case .appleCalendar: english ? "Apple Calendar" : "Apple Calendar"
        case .revisedDocument: english ? "Revised document" : "Document révisé"
        }
    }
}

enum AcademicChangeField: String, Codable, CaseIterable, Identifiable {
    case title
    case deadline
    case instructions
    case eventTime
    case deleted
    case resource

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        let english = language == .english
        return switch self {
        case .title: english ? "Title" : "Titre"
        case .deadline: english ? "Deadline" : "Échéance"
        case .instructions: english ? "Instructions" : "Consigne"
        case .eventTime: english ? "Event time" : "Horaire"
        case .deleted: english ? "Deleted or unavailable" : "Supprimé ou indisponible"
        case .resource: english ? "Resource" : "Ressource"
        }
    }
}

enum AcademicChangeStatus: String, Codable {
    case new
    case accepted
    case ignored
}

enum AcademicChangeUrgency: String, Codable {
    case urgent
    case normal
    case informational

    func title(language: AppLanguage) -> String {
        let english = language == .english
        return switch self {
        case .urgent: english ? "Urgent" : "Urgent"
        case .normal: english ? "Review" : "À vérifier"
        case .informational: english ? "Info" : "Info"
        }
    }

    var color: Color {
        switch self {
        case .urgent: .red
        case .normal: .orange
        case .informational: .secondary
        }
    }
}

struct AcademicSourceSnapshot: Codable, Identifiable, Hashable {
    var id: String
    var sourceKind: AcademicChangeSourceKind
    var stableSourceID: String
    var title: String
    var deadline: Date?
    var instructionsHash: String?
    var instructionsPreview: String
    var courseID: UUID?
    var localItemID: UUID?
    var sourceName: String
    var capturedAt: Date
    var timeZoneID: String
    var isLiveSubscription: Bool
}

struct AcademicChangeItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var sourceKind: AcademicChangeSourceKind
    var stableSourceID: String
    var field: AcademicChangeField
    var oldValue: String
    var newValue: String
    var oldDateValue: Date?
    var newDateValue: Date?
    var sourceName: String
    var detectedAt: Date
    var affectedCourseID: UUID?
    var affectedAssignmentNoteID: UUID?
    var affectedTaskID: UUID?
    var affectedSessionID: UUID?
    var proposedAction: String
    var urgency: AcademicChangeUrgency
    var status: AcademicChangeStatus = .new
    var fingerprint: String
}

struct AcademicChangeMonitorState: Codable {
    var schemaVersion = 1
    var snapshots: [AcademicSourceSnapshot] = []
    var inbox: [AcademicChangeItem] = []
    var lastSuccessfulSyncBySource: [String: Date] = [:]
    var notifyDeadlineChanges = true
    var notifyInformationalChanges = false
    var lastOpenedAt: Date = .now
}

enum AcademicChangeMonitorStore {
    static let marker = "UNISAVER_CHANGE_MONITOR_V1:"

    static func monitorNote(in notes: [StudyNote], course: Course, context: ModelContext) -> StudyNote {
        if let note = notes.first(where: { $0.course?.id == course.id && $0.body.hasPrefix(marker) }) {
            return note
        }
        let note = StudyNote(
            title: "Academic Change Monitor",
            body: marker + "{}",
            course: course
        )
        context.insert(note)
        return note
    }

    static func decode(_ note: StudyNote) -> AcademicChangeMonitorState {
        let raw = note.body.hasPrefix(marker) ? String(note.body.dropFirst(marker.count)) : ""
        if let data = raw.data(using: .utf8),
           let state = try? JSONDecoder().decode(AcademicChangeMonitorState.self, from: data) {
            return state
        }
        return AcademicChangeMonitorState()
    }

    static func save(_ state: AcademicChangeMonitorState, into note: StudyNote) {
        var copy = state
        copy.lastOpenedAt = .now
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(copy)) ?? Data()
        note.body = marker + (String(data: data, encoding: .utf8) ?? "{}")
        note.updatedAt = .now
    }

    static func add(_ change: AcademicChangeItem, to state: inout AcademicChangeMonitorState) {
        guard !state.inbox.contains(where: { $0.fingerprint == change.fingerprint && $0.status == .new }) else {
            return
        }
        state.inbox.append(change)
    }
}

struct AcademicChangeMonitorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \AcademicTask.updatedAt, order: .reverse) private var tasks: [AcademicTask]
    @Query(sort: \ExternalCalendarEventLink.updatedAt, order: .reverse) private var calendarLinks: [ExternalCalendarEventLink]
    let course: Course

    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue
    @State private var state = AcademicChangeMonitorState()
    @State private var selectedAssignmentNoteID: UUID?
    @State private var isImporterPresented = false
    @State private var syncMessage: String?
    @State private var errorMessage: String?

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private func uiText(_ french: String, _ english: String) -> String {
        appLanguage == .english ? english : french
    }

    private var monitorNote: StudyNote {
        AcademicChangeMonitorStore.monitorNote(in: notes, course: course, context: modelContext)
    }

    private var assignmentNotes: [StudyNote] {
        notes
            .filter { $0.course?.id == course.id && AssignmentPlanStore.isAssignmentPlan($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var relevantChanges: [AcademicChangeItem] {
        state.inbox
            .filter { $0.affectedCourseID == nil || $0.affectedCourseID == course.id }
            .sorted { first, second in
                if first.status == second.status {
                    return first.detectedAt > second.detectedAt
                }
                return first.status == .new
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourceStatusSection
                    controlsSection
                    inboxSection
                    notificationSection
                }
                .padding(24)
                .frame(maxWidth: 920, alignment: .topLeading)
            }
            footer
        }
        .frame(minWidth: 760, minHeight: 640)
        .background(Color.studyDeskBackground)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleRevisedDocumentImport(result)
        }
        .onAppear {
            state = AcademicChangeMonitorStore.decode(monitorNote)
            if selectedAssignmentNoteID == nil {
                selectedAssignmentNoteID = assignmentNotes.first?.id
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "tray.full")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(uiText("Boîte des changements", "Changes Inbox"))
                    .font(.title3.weight(.semibold))
                Text(uiText("UniSaver compare les sources prises en charge et propose les mises à jour sans modifier tes plans avant confirmation.", "UniSaver compares supported sources and proposes updates without changing your plans until you confirm."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(uiText("Fermer", "Close")) { dismiss() }
        }
        .padding(20)
        .background(StudyDeskTheme.surfacePrimary)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var sourceStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(uiText("Sources surveillées", "Monitored sources"))
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                AcademicChangeSourceCard(
                    title: "Moodle",
                    subtitle: moodleStatus,
                    isLive: MoodleSyncMetadataStore().load().institutionURL != nil,
                    language: appLanguage
                )
                AcademicChangeSourceCard(
                    title: "Apple Calendar",
                    subtitle: calendarStatus,
                    isLive: readableEventAccess,
                    language: appLanguage
                )
                AcademicChangeSourceCard(
                    title: uiText("Documents importés", "Imported documents"),
                    subtitle: uiText("Les fichiers statiques ne changent pas seuls. Réimporte une version corrigée pour comparer.", "Static files do not update themselves. Upload a revised copy to compare."),
                    isLive: false,
                    language: appLanguage
                )
            }
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(uiText("Comparer", "Compare"))
                .font(.headline)
            HStack(alignment: .top, spacing: 12) {
                Button {
                    runSupportedSourceScan()
                } label: {
                    Label(uiText("Scanner les sources prises en charge", "Scan supported sources"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 8) {
                    Picker(uiText("Assignment", "Assignment"), selection: $selectedAssignmentNoteID) {
                        ForEach(assignmentNotes) { note in
                            Text(note.title).tag(Optional(note.id))
                        }
                    }
                    .frame(maxWidth: 360)
                    .disabled(assignmentNotes.isEmpty)
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label(uiText("Comparer un document révisé", "Compare revised document"), systemImage: "doc.badge.plus")
                    }
                    .disabled(selectedAssignmentNoteID == nil)
                    Text(uiText("Aucune écriture n’est faite dans le plan avant acceptation d’un changement.", "No plan is changed until a change is accepted."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let syncMessage {
                Text(syncMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(uiText("Changements détectés", "Detected changes"))
                    .font(.headline)
                Spacer()
                Text("\(relevantChanges.filter { $0.status == .new }.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if relevantChanges.isEmpty {
                ContentUnavailableView {
                    Label(uiText("Aucun changement à revoir", "No changes to review"), systemImage: "checkmark.seal")
                } description: {
                    Text(uiText("Lance un scan ou compare une version corrigée d’un assignment.", "Run a scan or compare a corrected assignment file."))
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: 10) {
                    ForEach(relevantChanges) { change in
                        AcademicChangeRow(
                            change: change,
                            language: appLanguage,
                            onAccept: { accept(change) },
                            onIgnore: { updateStatus(change, status: .ignored) }
                        )
                    }
                }
            }
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(uiText("Notifications", "Notifications"))
                .font(.headline)
            Toggle(uiText("Me signaler les changements urgents d’échéance", "Notify me about urgent deadline changes"), isOn: Binding(
                get: { state.notifyDeadlineChanges },
                set: { state.notifyDeadlineChanges = $0; persistState() }
            ))
            Toggle(uiText("Inclure les changements informatifs", "Include informational changes"), isOn: Binding(
                get: { state.notifyInformationalChanges },
                set: { state.notifyInformationalChanges = $0; persistState() }
            ))
            Text(uiText("Cette version consolide les alertes dans UniSaver. Les notifications système dépendent des autorisations macOS et des limites de rafraîchissement en arrière-plan.", "This version consolidates alerts inside UniSaver. System notifications depend on macOS permissions and background refresh limits."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.studyDeskBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Text(uiText("Dernier scan : ", "Last scan: ") + lastSyncLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(uiText("Terminé", "Done")) { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(StudyDeskTheme.surfacePrimary)
        .overlay(alignment: .top) { Divider() }
    }

    private var moodleStatus: String {
        let metadata = MoodleSyncMetadataStore().load()
        guard metadata.institutionURL != nil else {
            return uiText("Non connecté. UniSaver ne peut pas interroger Moodle sans token autorisé.", "Not connected. UniSaver cannot query Moodle without an authorized token.")
        }
        let functions = Set(metadata.accessibleFunctions)
        let eventSupport = functions.contains("core_calendar_get_action_events_by_courses")
        let date = metadata.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? uiText("jamais", "never")
        return eventSupport
            ? uiText("Événements d’action disponibles. Dernière synchronisation : \(date).", "Action events available. Last sync: \(date).")
            : uiText("Cours disponibles, événements d’action indisponibles pour ce compte.", "Courses available; action events unavailable for this account.")
    }

    private var calendarStatus: String {
        if readableEventAccess {
            return uiText("\(calendarLinksForCourse.count) lien(s) Apple Calendar peuvent être comparés via EventKit.", "\(calendarLinksForCourse.count) Apple Calendar link(s) can be compared through EventKit.")
        }
        return uiText("Accès Calendar non autorisé ou indisponible. Les liens existants sont conservés.", "Calendar access is not authorized or unavailable. Existing links are preserved.")
    }

    private var calendarLinksForCourse: [ExternalCalendarEventLink] {
        calendarLinks.filter { $0.course?.id == course.id || $0.session?.course?.id == course.id }
    }

    private var lastSyncLabel: String {
        let dates = state.lastSuccessfulSyncBySource.values
        guard let latest = dates.max() else { return uiText("aucun", "none") }
        return latest.formatted(date: .abbreviated, time: .shortened)
    }

    private var readableEventAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    private func runSupportedSourceScan() {
        syncMessage = nil
        errorMessage = nil
        var copy = state
        scanMoodleImportedTasks(into: &copy)
        scanAppleCalendarLinks(into: &copy)
        copy.lastSuccessfulSyncBySource["local-scan"] = .now
        state = copy
        persistState()
        syncMessage = uiText("Scan terminé. Les changements nouveaux sont listés ci-dessous ; les sources indisponibles n’ont pas remplacé les données existantes.", "Scan complete. New changes are listed below; unavailable sources did not replace existing data.")
    }

    private func scanMoodleImportedTasks(into state: inout AcademicChangeMonitorState) {
        let metadata = MoodleSyncMetadataStore().load()
        let taskRecords = metadata.records.filter { $0.kind == .task }
        guard !taskRecords.isEmpty else {
            return
        }
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        for record in taskRecords {
            guard let task = taskByID[record.localID], task.course?.id == course.id else { continue }
            let snapshotID = "moodle-task-\(record.remoteID)"
            let newSnapshot = AcademicSourceSnapshot(
                id: snapshotID,
                sourceKind: .moodle,
                stableSourceID: record.remoteID,
                title: task.title,
                deadline: task.dueDate,
                instructionsHash: normalizedHash(task.taskDescription),
                instructionsPreview: preview(task.taskDescription),
                courseID: course.id,
                localItemID: task.id,
                sourceName: record.sourceURL.host ?? "Moodle",
                capturedAt: .now,
                timeZoneID: TimeZone.current.identifier,
                isLiveSubscription: metadata.institutionURL != nil
            )
            compare(newSnapshot, previous: state.snapshots.first { $0.id == snapshotID }, affectedTaskID: task.id, state: &state)
            upsert(newSnapshot, in: &state)
        }
        state.lastSuccessfulSyncBySource[AcademicChangeSourceKind.moodle.rawValue] = .now
    }

    private func scanAppleCalendarLinks(into state: inout AcademicChangeMonitorState) {
        guard readableEventAccess else {
            state.lastSuccessfulSyncBySource[AcademicChangeSourceKind.appleCalendar.rawValue] = .now
            return
        }
        let store = EKEventStore()
        for link in calendarLinksForCourse {
            let sourceID = link.externalStableIdentifier ?? link.externalEventIdentifier
            let snapshotID = "apple-event-\(sourceID)-\(Int(link.occurrenceStartDate.timeIntervalSince1970))"
            guard let event = store.event(withIdentifier: link.externalEventIdentifier) else {
                let fingerprint = "\(snapshotID)-deleted"
                AcademicChangeMonitorStore.add(
                    AcademicChangeItem(
                        sourceKind: .appleCalendar,
                        stableSourceID: sourceID,
                        field: .deleted,
                        oldValue: link.titleSnapshot,
                        newValue: uiText("Événement introuvable dans Calendar", "Event no longer available in Calendar"),
                        sourceName: link.calendarTitleSnapshot,
                        detectedAt: .now,
                        affectedCourseID: course.id,
                        affectedSessionID: link.session?.id,
                        proposedAction: uiText("Vérifier avant de masquer ou dissocier. UniSaver ne supprimera rien sans confirmation.", "Review before hiding or unlinking. UniSaver will not delete anything without confirmation."),
                        urgency: .normal,
                        fingerprint: fingerprint
                    ),
                    to: &state
                )
                continue
            }
            let newSnapshot = AcademicSourceSnapshot(
                id: snapshotID,
                sourceKind: .appleCalendar,
                stableSourceID: sourceID,
                title: event.title ?? link.titleSnapshot,
                deadline: event.startDate,
                instructionsHash: normalizedHash(event.notes ?? ""),
                instructionsPreview: preview(event.notes ?? ""),
                courseID: course.id,
                localItemID: link.session?.id,
                sourceName: event.calendar.title,
                capturedAt: .now,
                timeZoneID: event.timeZone?.identifier ?? TimeZone.current.identifier,
                isLiveSubscription: true
            )
            compare(newSnapshot, previous: state.snapshots.first { $0.id == snapshotID }, affectedSessionID: link.session?.id, state: &state)
            upsert(newSnapshot, in: &state)
        }
        state.lastSuccessfulSyncBySource[AcademicChangeSourceKind.appleCalendar.rawValue] = .now
    }

    private func handleRevisedDocumentImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard let noteID = selectedAssignmentNoteID,
                  let note = assignmentNotes.first(where: { $0.id == noteID }) else {
                errorMessage = uiText("Choisis d’abord un assignment à comparer.", "Choose an assignment to compare first.")
                return
            }
            let revisedText = try textFromImportedDocument(url)
            let extracted = AssignmentExtractor.extract(
                text: revisedText,
                sourceName: url.lastPathComponent,
                fallbackTitle: url.deletingPathExtension().lastPathComponent
            )
            var copy = state
            let current = AssignmentPlanStore.decode(note)
            compareRevisedAssignment(current: current, extracted: extracted, note: note, sourceName: url.lastPathComponent, state: &copy)
            copy.lastSuccessfulSyncBySource[AcademicChangeSourceKind.revisedDocument.rawValue] = .now
            state = copy
            persistState()
            syncMessage = uiText("Document comparé. Les écarts détectés attendent ta confirmation.", "Document compared. Detected differences are waiting for your confirmation.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func textFromImportedDocument(_ url: URL) throws -> String {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .pdf) == true {
            let result = AssignmentExtractor.extractPDFText(from: url)
            if result.text.isEmpty {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: result.messages.first ?? uiText("PDF sans texte exploitable.", "PDF has no extractable text.")])
            }
            return result.text
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func compareRevisedAssignment(current: AssignmentPlanProject, extracted: AssignmentExtractionResult, note: StudyNote, sourceName: String, state: inout AcademicChangeMonitorState) {
        let stableID = "assignment-document-\(note.id.uuidString)"
        if normalized(current.title) != normalized(extracted.title) {
            addChange(sourceKind: .revisedDocument, stableID: stableID, field: .title, oldValue: current.title, newValue: extracted.title, sourceName: sourceName, noteID: note.id, urgency: .normal, state: &state)
        }
        if let newDeadline = extracted.deadline, current.deadline != newDeadline {
            addChange(
                sourceKind: .revisedDocument,
                stableID: stableID,
                field: .deadline,
                oldValue: current.deadline?.formatted(date: .abbreviated, time: .shortened) ?? uiText("Aucune", "None"),
                newValue: newDeadline.formatted(date: .abbreviated, time: .shortened),
                newDateValue: newDeadline,
                sourceName: sourceName,
                noteID: note.id,
                urgency: .urgent,
                state: &state
            )
        }
        let currentRequirements = current.allRequirements.map(\.supportingText).joined(separator: "\n")
        let revisedRequirements = extracted.requirements.map(\.supportingText).joined(separator: "\n")
        if normalizedHash(currentRequirements) != normalizedHash(revisedRequirements), !revisedRequirements.isEmpty {
            addChange(
                sourceKind: .revisedDocument,
                stableID: stableID,
                field: .instructions,
                oldValue: preview(currentRequirements),
                newValue: preview(revisedRequirements),
                sourceName: sourceName,
                noteID: note.id,
                urgency: .normal,
                state: &state
            )
        }
    }

    private func compare(_ newSnapshot: AcademicSourceSnapshot, previous: AcademicSourceSnapshot?, affectedTaskID: UUID? = nil, affectedSessionID: UUID? = nil, state: inout AcademicChangeMonitorState) {
        guard let previous else { return }
        if normalized(previous.title) != normalized(newSnapshot.title) {
            addChange(sourceKind: newSnapshot.sourceKind, stableID: newSnapshot.stableSourceID, field: .title, oldValue: previous.title, newValue: newSnapshot.title, sourceName: newSnapshot.sourceName, taskID: affectedTaskID, sessionID: affectedSessionID, urgency: .normal, state: &state)
        }
        if previous.deadline != newSnapshot.deadline {
            addChange(
                sourceKind: newSnapshot.sourceKind,
                stableID: newSnapshot.stableSourceID,
                field: newSnapshot.sourceKind == .appleCalendar ? .eventTime : .deadline,
                oldValue: previous.deadline?.formatted(date: .abbreviated, time: .shortened) ?? uiText("Aucune", "None"),
                newValue: newSnapshot.deadline?.formatted(date: .abbreviated, time: .shortened) ?? uiText("Aucune", "None"),
                oldDateValue: previous.deadline,
                newDateValue: newSnapshot.deadline,
                sourceName: newSnapshot.sourceName,
                taskID: affectedTaskID,
                sessionID: affectedSessionID,
                urgency: .urgent,
                state: &state
            )
        }
        if previous.instructionsHash != newSnapshot.instructionsHash {
            addChange(sourceKind: newSnapshot.sourceKind, stableID: newSnapshot.stableSourceID, field: .instructions, oldValue: previous.instructionsPreview, newValue: newSnapshot.instructionsPreview, sourceName: newSnapshot.sourceName, taskID: affectedTaskID, sessionID: affectedSessionID, urgency: .normal, state: &state)
        }
    }

    private func addChange(
        sourceKind: AcademicChangeSourceKind,
        stableID: String,
        field: AcademicChangeField,
        oldValue: String,
        newValue: String,
        oldDateValue: Date? = nil,
        newDateValue: Date? = nil,
        sourceName: String,
        noteID: UUID? = nil,
        taskID: UUID? = nil,
        sessionID: UUID? = nil,
        urgency: AcademicChangeUrgency,
        state: inout AcademicChangeMonitorState
    ) {
        let fingerprint = "\(sourceKind.rawValue)|\(stableID)|\(field.rawValue)|\(normalizedHash(oldValue))|\(normalizedHash(newValue))"
        let proposed = proposedAction(for: field, sourceKind: sourceKind)
        AcademicChangeMonitorStore.add(
            AcademicChangeItem(
                sourceKind: sourceKind,
                stableSourceID: stableID,
                field: field,
                oldValue: oldValue,
                newValue: newValue,
                oldDateValue: oldDateValue,
                newDateValue: newDateValue,
                sourceName: sourceName,
                detectedAt: .now,
                affectedCourseID: course.id,
                affectedAssignmentNoteID: noteID,
                affectedTaskID: taskID,
                affectedSessionID: sessionID,
                proposedAction: proposed,
                urgency: urgency,
                fingerprint: fingerprint
            ),
            to: &state
        )
    }

    private func proposedAction(for field: AcademicChangeField, sourceKind: AcademicChangeSourceKind) -> String {
        switch field {
        case .deadline:
            return uiText("Mettre à jour l’échéance après vérification, sans déplacer les séances de travail confirmées.", "Update the deadline after review, without moving confirmed work sessions.")
        case .eventTime:
            return uiText("Mettre à jour la séance liée après confirmation. L’événement Apple reste en lecture seule.", "Update the linked session after confirmation. The Apple event remains read-only.")
        case .instructions:
            return uiText("Ajouter cette différence aux points à vérifier au lieu de remplacer automatiquement la consigne éditée.", "Add this difference to the review list instead of automatically replacing edited instructions.")
        case .title:
            return uiText("Mettre à jour le titre local après confirmation.", "Update the local title after confirmation.")
        case .deleted:
            return uiText("Vérifier la source avant de masquer ou dissocier l’élément local.", "Review the source before hiding or unlinking the local item.")
        case .resource:
            return sourceKind == .moodle
                ? uiText("Examiner la nouvelle ressource et l’importer si elle est utile.", "Review the new resource and import it if useful.")
                : uiText("Examiner la ressource avant modification.", "Review the resource before changing anything.")
        }
    }

    private func accept(_ change: AcademicChangeItem) {
        switch change.field {
        case .deadline:
            if let noteID = change.affectedAssignmentNoteID,
               let note = assignmentNotes.first(where: { $0.id == noteID }),
               let newDate = change.newDateValue {
                var project = AssignmentPlanStore.decode(note)
                project.deadline = newDate
                project.unresolvedQuestions.append(uiText("Échéance mise à jour depuis \(change.sourceName). Vérifie le planning avant de déplacer des séances confirmées.", "Deadline updated from \(change.sourceName). Review the plan before moving confirmed sessions."))
                AssignmentPlanStore.save(project, into: note)
            } else if let taskID = change.affectedTaskID,
                      let task = tasks.first(where: { $0.id == taskID }),
                      let newDate = change.newDateValue {
                task.dueDate = newDate
                task.updatedAt = .now
            }
        case .eventTime:
            if let sessionID = change.affectedSessionID,
               let session = course.sessions.first(where: { $0.id == sessionID }),
               let newDate = change.newDateValue {
                let duration = max(900, session.endTime.timeIntervalSince(session.startTime))
                session.startTime = newDate
                session.endTime = newDate.addingTimeInterval(duration)
                session.date = Calendar.current.startOfDay(for: newDate)
                session.updatedAt = .now
            }
        case .title:
            if let noteID = change.affectedAssignmentNoteID,
               let note = assignmentNotes.first(where: { $0.id == noteID }) {
                var project = AssignmentPlanStore.decode(note)
                project.title = change.newValue
                AssignmentPlanStore.save(project, into: note)
            } else if let taskID = change.affectedTaskID,
                      let task = tasks.first(where: { $0.id == taskID }) {
                task.title = change.newValue
                task.updatedAt = .now
            } else if let sessionID = change.affectedSessionID,
                      let session = course.sessions.first(where: { $0.id == sessionID }) {
                session.title = change.newValue
                session.updatedAt = .now
            }
        case .instructions:
            if let noteID = change.affectedAssignmentNoteID,
               let note = assignmentNotes.first(where: { $0.id == noteID }) {
                var project = AssignmentPlanStore.decode(note)
                project.unresolvedQuestions.append(uiText("Consigne révisée à vérifier depuis \(change.sourceName): \(change.newValue)", "Revised instructions to review from \(change.sourceName): \(change.newValue)"))
                AssignmentPlanStore.save(project, into: note)
            } else if let taskID = change.affectedTaskID,
                      let task = tasks.first(where: { $0.id == taskID }) {
                task.taskDescription += "\n\n" + uiText("Changement détecté à vérifier : \(change.newValue)", "Detected change to review: \(change.newValue)")
                task.updatedAt = .now
            }
        case .deleted, .resource:
            break
        }
        updateStatus(change, status: .accepted)
    }

    private func updateStatus(_ change: AcademicChangeItem, status: AcademicChangeStatus) {
        guard let index = state.inbox.firstIndex(where: { $0.id == change.id }) else { return }
        state.inbox[index].status = status
        persistState()
        try? modelContext.save()
    }

    private func persistState() {
        AcademicChangeMonitorStore.save(state, into: monitorNote)
        try? modelContext.save()
    }

    private func upsert(_ snapshot: AcademicSourceSnapshot, in state: inout AcademicChangeMonitorState) {
        if let index = state.snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            state.snapshots[index] = snapshot
        } else {
            state.snapshots.append(snapshot)
        }
    }

    private func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized(text).utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func preview(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(220))
    }
}

private struct AcademicChangeSourceCard: View {
    let title: String
    let subtitle: String
    let isLive: Bool
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(isLive ? liveText : staticText, systemImage: isLive ? "dot.radiowaves.left.and.right" : "doc")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isLive ? .green : .secondary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var liveText: String { language == .english ? "Live" : "Actif" }
    private var staticText: String { language == .english ? "Static" : "Statique" }
}

private struct AcademicChangeRow: View {
    let change: AcademicChangeItem
    let language: AppLanguage
    let onAccept: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(change.field.title(language: language))
                            .font(.subheadline.weight(.semibold))
                        Text(change.urgency.title(language: language))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(change.urgency.color)
                    }
                    Text("\(change.sourceKind.title(language: language)) · \(change.sourceName) · \(change.detectedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if change.status != .new {
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                valueColumn(title: language == .english ? "Before" : "Avant", value: change.oldValue)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 22)
                valueColumn(title: language == .english ? "After" : "Après", value: change.newValue)
            }
            Text(change.proposedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            if change.status == .new {
                HStack {
                    Button(language == .english ? "Ignore" : "Ignorer", role: .cancel, action: onIgnore)
                    Spacer()
                    Button(language == .english ? "Apply after review" : "Appliquer après vérification", action: onAccept)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusText: String {
        switch change.status {
        case .new:
            language == .english ? "New" : "Nouveau"
        case .accepted:
            language == .english ? "Accepted" : "Accepté"
        case .ignored:
            language == .english ? "Ignored" : "Ignoré"
        }
    }

    private func valueColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct AssignmentPlanCompactRow: View {
    let note: StudyNote

    private var project: AssignmentPlanProject {
        AssignmentPlanStore.decode(note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(project.title, systemImage: "doc.badge.clock")
                .font(.headline)
            Text("\(project.stage.title) · \(project.nextAction)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(project.deadline.map { "Due \(UniDateFormatters.dayMonth.string(from: $0))" } ?? "No deadline confirmed")
                Spacer()
                Text("\(project.milestones.count) milestones")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            ProgressView(value: project.progress)
        }
        .padding(12)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(StudyDeskTheme.borderSubtle) }
    }
}

struct AssignmentExtractionResult {
    var title: String
    var deadline: Date?
    var deadlineUncertainty: String?
    var requirements: [AssignmentRequirement]
    var messages: [String]
}

enum AssignmentExtractor {
    static func extractPDFText(from url: URL) -> (text: String, messages: [String]) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let document = PDFDocument(url: url) else {
            return ("", ["PDF unreadable by PDFKit."])
        }
        var chunks: [String] = []
        for index in 0..<document.pageCount {
            let pageText = document.page(at: index)?.string ?? ""
            for line in pageText.components(separatedBy: .newlines) {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    chunks.append("[p.\(index + 1)] \(clean)")
                }
            }
        }
        let text = chunks.joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("", ["This PDF does not expose selectable text. Use an OCR copy or paste the instructions manually."])
        }
        return (text, [])
    }

    static func extract(text: String, sourceName: String, fallbackTitle: String) -> AssignmentExtractionResult {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var messages: [String] = []
        var requirements: [AssignmentRequirement] = []
        var deadline: Date?
        var deadlineUncertainty: String?
        let title = lines.first(where: { !$0.hasPrefix("[p.") && $0.count > 5 }) ?? fallbackTitle

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let source = "\(sourceName) · line \(index + 1)\(pageHint(from: line).map { " · \($0)" } ?? "")"
            let clean = line.replacingOccurrences(of: #"^\[p\.\d+\]\s*"#, with: "", options: .regularExpression)
            let parsedDate = parseAssignmentDate(in: clean)
            if lower.contains("due") || lower.contains("deadline") || lower.contains("échéance") || lower.contains("remise") || lower.contains("submit") || lower.contains("à rendre") {
                if let parsedDate {
                    if deadline != nil {
                        messages.append("Conflicting or repeated deadline near: \(clean)")
                    }
                    deadline = parsedDate.date
                    deadlineUncertainty = parsedDate.uncertainty
                    requirements.append(AssignmentRequirement(title: "Deadline", detail: clean, kind: "deadline", sourceReference: source, supportingText: clean, uncertainty: parsedDate.uncertainty))
                } else if lower.contains("due") || lower.contains("deadline") || lower.contains("échéance") || lower.contains("à rendre") {
                    requirements.append(AssignmentRequirement(title: "Possible deadline", detail: clean, kind: "deadline", sourceReference: source, supportingText: clean, uncertainty: "Date mentioned but not parsed. Review required."))
                }
            }
            if lower.contains("deliverable") || lower.contains("submit") || lower.contains("write") || lower.contains("paper") || lower.contains("presentation") || lower.contains("rendu") || lower.contains("livrable") {
                requirements.append(AssignmentRequirement(title: "Deliverable", detail: clean, kind: "deliverable", sourceReference: source, supportingText: clean))
                continue
            }
            if lower.contains("criteria") || lower.contains("rubric") || lower.contains("grade") || lower.contains("grading") || lower.contains("barème") || lower.contains("critère") {
                requirements.append(AssignmentRequirement(title: "Grading criterion", detail: clean, kind: "grading", sourceReference: source, supportingText: clean, uncertainty: clean.count < 20 ? "Short criterion; verify meaning." : nil))
                continue
            }
            if lower.contains("must") || lower.contains("constraint") || lower.contains("required") || lower.contains("minimum") || lower.contains("maximum") || lower.contains("obligatoire") || lower.contains("minimum") || lower.contains("maximum") {
                requirements.append(AssignmentRequirement(title: "Constraint", detail: clean, kind: "constraint", sourceReference: source, supportingText: clean))
                continue
            }
            if let parsedDate, !requirements.contains(where: { $0.sourceReference == source && $0.kind == "deadline" }) {
                requirements.append(AssignmentRequirement(title: "Date to classify (evaluation / preparation / submission)", detail: clean, kind: "intermediate", sourceReference: source, supportingText: clean, uncertainty: "Confirm what this date refers to. " + (parsedDate.uncertainty ?? "")))
            }
        }

        if deadline == nil {
            messages.append("No submission deadline was confidently extracted. Verify it; manual work can proceed without a date.")
        }
        if requirements.filter({ $0.kind == "deliverable" }).isEmpty {
            messages.append("No deliverables found. Clarify what must be produced; suggested steps remain generic.")
        }
        if requirements.filter({ $0.kind == "grading" }).isEmpty {
            messages.append("No grading criteria found. UniSaver will not invent a rubric.")
        }

        return AssignmentExtractionResult(title: strippedPrefix(title), deadline: deadline, deadlineUncertainty: deadlineUncertainty, requirements: requirements, messages: messages)
    }

    private static func pageHint(from line: String) -> String? {
        guard let range = line.range(of: #"^\[p\.\d+\]"#, options: .regularExpression) else { return nil }
        return String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private static func parseAssignmentDate(in text: String) -> (date: Date, uncertainty: String?)? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector?.firstMatch(in: text, options: [], range: range), let date = match.date else {
            return nil
        }
        let matched = (text as NSString).substring(with: match.range)
        let uncertainty = matched.range(of: #"\d{1,2}:\d{2}|am|pm"#, options: [.regularExpression, .caseInsensitive]) == nil ? "Time missing; default planner sessions use working hours." : nil
        let missingYear = matched.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) == nil
        let warning = [uncertainty, missingYear ? "Year inferred by date detector; confirm the intended year." : nil].compactMap { $0 }.joined(separator: " ")
        return (date, warning.isEmpty ? nil : warning)
    }

    private static func strippedPrefix(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\[p\.\d+\]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[-•*\d\.\)\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AssignmentPlannerEngine {
    static func buildMilestones(for project: AssignmentPlanProject, now: Date = .now) -> [AssignmentMilestoneDraft] {
        // Generic preparation actions, never claimed as teacher requirements.
        let deliverables = project.deliverables.map(\.detail).joined(separator: "; ")
        let base: [(String, String, Int, AcademicTaskPriority)] = [
            ("Review brief and open questions", "Finish when missing requirements are identified and consequential ambiguities clarified.", 30, .high),
            ("Produce the requested work", deliverables.isEmpty ? "Generic preparation: clarify the deliverable before working. Finish when a draft answering the reviewed brief exists." : "Finish when a draft addresses these reviewed deliverables: " + deliverables, 90, .high),
            ("Check against reviewed requirements", "Finish when the draft has been checked against the attached criteria and unresolved issues are recorded.", 30, .high),
            ("Submit the final work", "Separate submission action. Finish when files are sent through the required channel and the student records the outcome. UniSaver does not confirm submission through an API.", 15, .urgent)
        ]
        var milestones: [AssignmentMilestoneDraft] = []
        for item in base {
            var milestone = AssignmentMilestoneDraft(title: item.0, detail: item.1, dueDate: nil,
                estimatedMinutes: item.2, priority: item.3, sourceRequirementIDs: project.allRequirements.map(\.id))
            if let previous = milestones.last { milestone.dependencyIDs = [previous.id] }
            milestones.append(milestone)
        }
        // The only supplied date remains the assignment submission deadline.
        milestones[milestones.count - 1].dueDate = project.deadline
        return milestones
    }

    static func buildSessions(milestones: [AssignmentMilestoneDraft], project: AssignmentPlanProject, classSessions: [ClassSession], studyBlocks: [StudyBlock], now: Date = .now) -> (sessions: [AssignmentWorkSessionDraft], shortfall: String?) {
        guard let deadline = project.deadline else {
            return ([], "Add a confirmed deadline before scheduling work sessions.")
        }
        let totalMinutes = milestones.filter(\.isApproved).reduce(0) { $0 + $1.estimatedMinutes }
        let days = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: deadline)).day ?? 1)
        let capacity = days * project.dailyWorkloadMinutes
        var shortfall: String?
        if totalMinutes > capacity {
            shortfall = "Estimated work is \(totalMinutes) min, but configured capacity before the deadline is \(capacity) min. Extend the deadline, reduce scope, or increase availability."
        }
        var cursor = nextWorkingStart(after: now, project: project)
        var sessions: [AssignmentWorkSessionDraft] = []
        for milestone in milestones where milestone.isApproved {
            var remaining = milestone.estimatedMinutes
            while remaining > 0 && cursor < deadline {
                let duration = min(remaining, 90)
                let end = Calendar.current.date(byAdding: .minute, value: duration, to: cursor) ?? cursor.addingTimeInterval(TimeInterval(duration * 60))
                let warning = overlapWarning(start: cursor, end: end, classSessions: classSessions, studyBlocks: studyBlocks)
                sessions.append(AssignmentWorkSessionDraft(title: milestone.title, startDate: cursor, endDate: end, milestoneID: milestone.id, overlapWarning: warning))
                remaining -= duration
                cursor = nextWorkingStart(after: end.addingTimeInterval(TimeInterval(project.breakMinutes * 60)), project: project)
            }
            if remaining > 0 {
                shortfall = [shortfall, "Could not schedule \(remaining) min for \(milestone.title) before the deadline."].compactMap { $0 }.joined(separator: "\n")
            }
        }
        return (sessions, shortfall)
    }

    private static func nextWorkingStart(after date: Date, project: AssignmentPlanProject) -> Date {
        var candidate = date
        let calendar = Calendar.current
        while true {
            let hour = calendar.component(.hour, from: candidate)
            if hour < project.workingStartHour {
                return calendar.date(bySettingHour: project.workingStartHour, minute: 0, second: 0, of: candidate) ?? candidate
            }
            if hour >= project.workingEndHour {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
                candidate = calendar.date(bySettingHour: project.workingStartHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
                continue
            }
            return candidate
        }
    }

    private static func overlapWarning(start: Date, end: Date, classSessions: [ClassSession], studyBlocks: [StudyBlock]) -> String? {
        if classSessions.contains(where: { $0.startTime < end && $0.endTime > start }) {
            return "Overlaps an existing class session."
        }
        if studyBlocks.contains(where: { $0.startDate < end && $0.endDate > start }) {
            return "Overlaps an existing study block."
        }
        return nil
    }
}

struct AssignmentPlannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: Course
    let chapters: [Chapter]
    let onCreate: (StudyNote) -> Void
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \ClassSession.startTime) private var classSessions: [ClassSession]
    @Query(sort: \StudyBlock.startDate) private var studyBlocks: [StudyBlock]

    @State private var selectedChapterID: UUID?
    @State private var selectedFileURL: URL?
    @State private var sourceResource: AcademicResource?
    @State private var instructions = ""
    @State private var project = AssignmentPlanProject(title: "", courseName: "")
    @State private var messages: [String] = []
    @State private var step = 0
    @State private var errorMessage: String?
    @State private var fileImporterPresented = false
    @State private var saving = false
    @State private var pendingPlanNote: StudyNote?
    @State private var showsOriginal = false

    private let fileStore = AcademicFileStore()

    private var selectedChapter: Chapter? {
        chapters.first { $0.id == selectedChapterID }
    }

    private var canConfirmPlan: Bool {
        !project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            project.allRequirements.allSatisfy(\.isReviewed) &&
            project.milestones.contains(where: \.isApproved)
    }

    var body: some View {
        CreationWindow(
            icon: "doc.badge.clock",
            title: "Add assignment",
            subtitle: "Extract the real brief, review requirements, then confirm tasks and work sessions.",
            accent: CourseColor.sky.color,
            closeAction: { dismiss() }
        ) {
            Picker("Step", selection: $step) {
                Text("Import").tag(0)
                Text("Requirements").tag(1)
                Text("Plan").tag(2)
            }
            .pickerStyle(.segmented)
            .disabled(saving)

            if step == 0 {
                importStep
            } else if step == 1 {
                requirementsStep
            } else {
                planningStep
            }

            if !messages.isEmpty {
                CreationCard("Extraction notes") {
                    ForEach(messages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            if let errorMessage {
                CreationErrorText(message: errorMessage)
            }
        } footer: {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                CreationPrimaryButton(
                    title: step == 2 ? "Confirm plan" : "Continue",
                    systemImage: step == 2 ? "checkmark.circle.fill" : "arrow.right.circle.fill",
                    accent: CourseColor.sky.color,
                    isDisabled: saving || (step == 2 && !canConfirmPlan),
                    action: primaryAction
                )
            }
        }
        .fileImporter(isPresented: $fileImporterPresented, allowedContentTypes: [.pdf, .plainText], allowsMultipleSelection: false) { result in
            handleFile(result)
        }
        .sheet(isPresented: $showsOriginal) {
            if let sourceResource {
                VStack {
                    Button("Close reader") { showsOriginal = false }.padding()
                    ResourceDetailView(resource: sourceResource)
                }.frame(minWidth: 600, minHeight: 600)
            }
        }
        .frame(minWidth: 820, idealWidth: 940, minHeight: 700, idealHeight: 780)
        .onAppear {
            if project.courseName.isEmpty {
                project.courseName = course.name
                project.chapterTitle = selectedChapter?.title
            }
        }
    }

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            CreationCard("Source") {
                Picker("Chapter", selection: $selectedChapterID) {
                    Text("Whole subject").tag(UUID?.none)
                    ForEach(chapters) { chapter in
                        Text(chapter.title).tag(Optional(chapter.id))
                    }
                }
                Button("Upload PDF or text file", systemImage: "doc.badge.plus") {
                    fileImporterPresented = true
                }
                if sourceResource != nil {
                    Button("Open original document") { showsOriginal = true }
                }
                if let selectedFileURL {
                    Text("Selected: \(selectedFileURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: $instructions)
                    .font(.body)
                    .frame(minHeight: 220)
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(StudyDeskTheme.borderSubtle) }
                Text("Paste instructions here if the PDF is scanned or unreadable. UniSaver only extracts selectable PDF text in this workflow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var requirementsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            CreationCard("Assignment") {
                TextField("Title", text: $project.title)
                    .textFieldStyle(.roundedBorder)
                Toggle("Submission deadline supplied", isOn: Binding(
                    get: { project.deadline != nil },
                    set: { project.deadline = $0 ? .now : nil }
                ))
                if project.deadline != nil {
                    DatePicker("Submission deadline (review before confirming)", selection: Binding(get: { project.deadline ?? .now }, set: { project.deadline = $0 }))
                } else {
                    Text("No deadline supplied. Manual work is available; automatic scheduling needs a confirmed deadline.").foregroundStyle(.secondary)
                }
                if let deadlineUncertainty = project.deadlineUncertainty {
                    Label(deadlineUncertainty, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Stepper("Daily workload \(project.dailyWorkloadMinutes) min", value: $project.dailyWorkloadMinutes, in: 30...360, step: 15)
                HStack {
                    Stepper("Start \(project.workingStartHour):00", value: $project.workingStartHour, in: 6...20)
                    Stepper("End \(project.workingEndHour):00", value: $project.workingEndHour, in: 8...23)
                }
            }
            requirementEditor("Deliverables", requirements: $project.deliverables)
            requirementEditor("Constraints", requirements: $project.constraints)
            requirementEditor("Grading criteria", requirements: $project.gradingCriteria)
            requirementEditor("Intermediate deadlines", requirements: $project.explicitIntermediateDeadlines)
            CreationCard("Unresolved questions") {
                ForEach(project.unresolvedQuestions, id: \.self) { question in
                    Label(question, systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                }
                Button("Add question") {
                    project.unresolvedQuestions.append("Clarify: ")
                }
            }
        }
    }

    private var planningStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            CreationCard("Milestones") {
                ForEach($project.milestones) { $milestone in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Create", isOn: $milestone.isApproved)
                        TextField("Title", text: $milestone.title)
                            .textFieldStyle(.roundedBorder)
                        TextField("Detail", text: $milestone.detail, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Set a personal step deadline", isOn: Binding(get: { milestone.dueDate != nil }, set: { milestone.dueDate = $0 ? project.deadline ?? .now : nil }))
                        if milestone.dueDate != nil {
                            DatePicker("Step deadline", selection: Binding(get: { milestone.dueDate ?? .now }, set: { milestone.dueDate = $0 }))
                        }
                        Text("Generic action. Finish condition is editable. Estimates are optional; use 0 for none. Depends on the preceding step.").font(.caption).foregroundStyle(.secondary)
                        Stepper("Estimate \(milestone.estimatedMinutes) min", value: $milestone.estimatedMinutes, in: 0...600, step: 15)
                        Picker("Priority", selection: $milestone.priority) {
                            ForEach(AcademicTaskPriority.allCases) { priority in
                                Text(priority.title).tag(priority)
                            }
                        }
                    }
                    .padding(10)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            CreationCard("Draft work sessions") {
                if let shortfallWarning = project.shortfallWarning {
                    Label(shortfallWarning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Regenerate sessions") { regenerateSessions() }
                    Text("Sessions remain drafts until confirmation. Overlaps are shown and can be disabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach($project.sessions) { $session in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Create", isOn: $session.isApproved)
                        TextField("Title", text: $session.title)
                            .textFieldStyle(.roundedBorder)
                        DatePicker("Start", selection: $session.startDate)
                        DatePicker("End", selection: $session.endDate)
                        if let warning = session.overlapWarning {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(10)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func requirementEditor(_ title: String, requirements: Binding<[AssignmentRequirement]>) -> some View {
        CreationCard(title) {
            ForEach(requirements) { requirement in
                if let index = requirements.wrappedValue.firstIndex(where: { $0.id == requirement.id }) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Title", text: requirements[index].title)
                            .textFieldStyle(.roundedBorder)
                        TextField("Detail", text: requirements[index].detail, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Text(requirements[index].wrappedValue.sourceReference)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("Reviewed requirement", isOn: requirements[index].isReviewed)
                        Text(requirements[index].wrappedValue.supportingText).font(.caption).textSelection(.enabled)
                        if let uncertainty = requirements[index].wrappedValue.uncertainty {
                            Toggle("Reviewed: \(uncertainty)", isOn: requirements[index].isReviewed)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(10)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Button("Add \(title.lowercased())") {
                requirements.wrappedValue.append(AssignmentRequirement(title: title, detail: "", kind: title.lowercased(), sourceReference: "Student entry", supportingText: ""))
            }
        }
    }

    private func primaryAction() {
        if step == 0 {
            if project.extractedText != instructions {
                if !project.title.isEmpty {
                    errorMessage = "The source changed. Keep your reviewed plan, or cancel and start a new import to re-extract; manual corrections will not be overwritten."
                    return
                }
                analyzeInstructions()
            }
            step = 1
        } else if step == 1 {
            generateMilestonesAndSessions()
            step = 2
        } else {
            confirmPlan()
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            selectedFileURL = url
            let draft = ResourceImportDraft(fileURL: url, title: url.deletingPathExtension().lastPathComponent, resourceDescription: "Assignment brief source", course: course, chapter: selectedChapter, session: nil, tags: ["assignment"])
            do {
                sourceResource = try ResourceImportService.submit(draft: draft, existingResources: resources, modelContext: modelContext, fileStore: fileStore)
            } catch ResourceImportSubmitError.duplicate(let duplicateID) {
                sourceResource = resources.first { $0.id == duplicateID }
                messages.append("Duplicate file detected; linked to the existing Library resource.")
            }
            if url.pathExtension.localizedLowercase == "pdf" {
                let extracted = AssignmentExtractor.extractPDFText(from: url)
                instructions = extracted.text
                messages.append(contentsOf: extracted.messages)
            } else {
                instructions = try String(contentsOf: sourceResource.map { try fileStore.url(for: $0.storedRelativePath) } ?? url, encoding: .utf8)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func analyzeInstructions() {
        let sourceName = sourceResource?.originalFileName ?? selectedFileURL?.lastPathComponent ?? "Pasted instructions"
        let extracted = AssignmentExtractor.extract(text: instructions, sourceName: sourceName, fallbackTitle: selectedFileURL?.deletingPathExtension().lastPathComponent ?? "New assignment")
        project.title = extracted.title
        project.courseName = course.name
        project.chapterTitle = selectedChapter?.title
        project.pastedInstructions = instructions
        project.extractedText = instructions
        project.sourceResourceID = sourceResource?.id
        project.sourceName = sourceName
        project.deadline = extracted.deadline
        project.deadlineUncertainty = extracted.deadlineUncertainty
        project.deliverables = extracted.requirements.filter { $0.kind == "deliverable" }
        project.constraints = extracted.requirements.filter { $0.kind == "constraint" }
        project.gradingCriteria = extracted.requirements.filter { $0.kind == "grading" }
        project.explicitIntermediateDeadlines = extracted.requirements.filter { $0.kind == "intermediate" || $0.kind == "deadline" }
        project.unresolvedQuestions = extracted.messages
        messages.append(contentsOf: extracted.messages)
    }

    private func generateMilestonesAndSessions() {
        if project.milestones.isEmpty {
            project.milestones = AssignmentPlannerEngine.buildMilestones(for: project)
        }
        regenerateSessions()
        project.stage = .planned
    }

    private func regenerateSessions() {
        let result = AssignmentPlannerEngine.buildSessions(
            milestones: project.milestones,
            project: project,
            classSessions: classSessions.filter { $0.course?.id == course.id || Calendar.current.dateComponents([.day], from: .now, to: $0.startTime).day ?? 999 < 60 },
            studyBlocks: studyBlocks
        )
        project.sessions = result.sessions
        project.shortfallWarning = result.shortfall
    }

    private func confirmPlan() {
        guard canConfirmPlan else {
            errorMessage = "Review uncertain fields and approve at least one step before creating the plan."
            return
        }
        saving = true
        let note = pendingPlanNote ?? StudyNote(title: project.title, course: course, chapter: selectedChapter, resource: sourceResource)
        if pendingPlanNote == nil {
            modelContext.insert(note)
            pendingPlanNote = note
        }
        for index in project.milestones.indices where project.milestones[index].isApproved {
            if let existingID = project.milestones[index].createdTaskID, taskExists(existingID) { continue }
            let task = AcademicTask(
                title: "\(project.title) · \(project.milestones[index].title)",
                taskDescription: "\(project.milestones[index].detail)\nAssignmentPlanID: \(note.id.uuidString)",
                dueDate: project.milestones[index].dueDate ?? project.deadline ?? .distantFuture,
                priority: project.milestones[index].priority,
                estimatedDuration: TimeInterval(project.milestones[index].estimatedMinutes * 60),
                course: course,
                chapter: selectedChapter
            )
            modelContext.insert(task)
            project.milestones[index].createdTaskID = task.id
        }
        for index in project.sessions.indices where project.sessions[index].isApproved {
            if let existingID = project.sessions[index].createdStudyBlockID, studyBlockExists(existingID) { continue }
            let linkedTask = project.sessions[index].milestoneID.flatMap { milestoneID in
                project.milestones.first { $0.id == milestoneID }?.createdTaskID
            }.flatMap { taskID in
                try? modelContext.fetch(FetchDescriptor<AcademicTask>()).first { $0.id == taskID }
            }
            let block = StudyBlock(title: "Assignment · \(project.sessions[index].title)", startDate: project.sessions[index].startDate, endDate: project.sessions[index].endDate, status: .planned, course: course, task: linkedTask)
            modelContext.insert(block)
            project.sessions[index].createdStudyBlockID = block.id
        }
        project.stage = .confirmed
        AssignmentPlanStore.save(project, into: note)
        modelContext.insert(note)
        do {
            try modelContext.save()
            onCreate(note)
            dismiss()
        } catch {
            saving = false
            errorMessage = error.localizedDescription
        }
    }

    private func taskExists(_ id: UUID) -> Bool {
        (try? modelContext.fetch(FetchDescriptor<AcademicTask>()).contains { $0.id == id }) ?? false
    }

    private func studyBlockExists(_ id: UUID) -> Bool {
        (try? modelContext.fetch(FetchDescriptor<StudyBlock>()).contains { $0.id == id }) ?? false
    }
}

struct AssignmentWorkspaceView: View {
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: StudyNote
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \StudyBlock.startDate) private var studyBlocks: [StudyBlock]
    @Query(sort: \ClassSession.startTime) private var classSessions: [ClassSession]
    @State private var project: AssignmentPlanProject
    @State private var message: String?
    @State private var showingReplan = false
    @State private var selectedGroupProject: StudyNote?
    @State private var proposedSessions: [AssignmentWorkSessionDraft] = []
    @State private var proposedShortfall: String?
    @State private var workTask: AcademicTask?

    init(note: StudyNote) {
        self.note = note
        _project = State(initialValue: AssignmentPlanStore.decode(note))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message {
                        Label(message, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                    requirementsCard
                    milestonesCard
                    sessionsCard
                    unresolvedCard
                }
                .padding(24)
                .frame(maxWidth: 1040, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .confirmationDialog("Apply revised work sessions?", isPresented: $showingReplan) {
            Button("Apply revised draft") {
                applyReplan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(replanPreviewText)
        }
        .onDisappear(perform: save)
        .sheet(item: $selectedGroupProject) { note in
            GroupProjectWorkspaceView(note: note)
        }
        .onChange(of: workTask?.id) { _, _ in
            if let task = workTask { navigation.focusTask = task; workTask = nil }
        }
        .frame(minWidth: 380, idealWidth: 1000, minHeight: 600)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.title)
                        .font(.title2.weight(.semibold))
                    Text("\(project.courseName)\(project.chapterTitle.map { " · \($0)" } ?? "")")
                        .foregroundStyle(.secondary)
                    Text(project.milestones.first(where: { $0.isApproved && linkedTask(for: $0)?.status != .completed })?.title ?? "Review completed work")
                        .font(.headline)
                }
                Spacer()
                Button("Create group project", systemImage: "person.3.sequence") {
                    selectedGroupProject = GroupProjectStore.createLocalProject(from: note, assignment: project, context: modelContext)
                    try? modelContext.save()
                }
                .buttonStyle(.bordered)
                Button("Replan remaining work", systemImage: "calendar.badge.clock") {
                    makeReplanPreview()
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Label(project.deadline.map { "Due \(UniDateFormatters.dayMonth.string(from: $0))" } ?? "No deadline", systemImage: "calendar")
                Label("\(remainingMinutes) min remaining", systemImage: "timer")
                Label(project.stage.title, systemImage: "location")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: completedProgress)
                .tint(CourseColor.sky.color)
        }
        .padding(20)
        .background(StudyDeskTheme.surfacePrimary)
    }

    private var requirementsCard: some View {
        CreationCard("Requirements and sources") {
            ForEach(project.allRequirements) { requirement in
                VStack(alignment: .leading, spacing: 4) {
                    Text(requirement.title)
                        .font(.subheadline.weight(.semibold))
                    Text(requirement.detail)
                    Text("\(requirement.sourceReference): \(requirement.supportingText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let uncertainty = requirement.uncertainty {
                        Label(uncertainty, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Divider()
            }
        }
    }

    private var milestonesCard: some View {
        CreationCard("Milestones and progress") {
            ForEach(project.milestones.indices, id: \.self) { index in
                HStack(alignment: .top) {
                    Toggle("", isOn: Binding(
                        get: { linkedTask(for: project.milestones[index])?.status == .completed },
                        set: { completed in
                            if let task = linkedTask(for: project.milestones[index]) {
                                task.status = completed ? .completed : .todo
                                task.updatedAt = .now
                                try? modelContext.save()
                            }
                        }
                    ))
                    .labelsHidden()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.milestones[index].title)
                            .font(.subheadline.weight(.semibold))
                        Text(project.milestones[index].detail)
                            .foregroundStyle(.secondary)
                        Text(project.milestones[index].dueDate.map { UniDateFormatters.dayMonth.string(from: $0) } ?? "No due date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let task = linkedTask(for: project.milestones[index]) {
                        Button(task.status == .inProgress ? "Resume task" : "Start task") { workTask = task }
                    }
                    Stepper("\(project.milestones[index].estimatedMinutes) min", value: $project.milestones[index].estimatedMinutes, in: 15...600, step: 15)
                }
                .padding(8)
                .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var sessionsCard: some View {
        CreationCard("Planned work sessions") {
            ForEach(project.sessions) { session in
                HStack {
                    Image(systemName: session.createdStudyBlockID == nil ? "calendar.badge.exclamationmark" : "calendar")
                        .foregroundStyle(session.overlapWarning == nil ? CourseColor.sky.color : Color.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(UniDateFormatters.dayMonth.string(from: session.startDate)) · \(UniDateFormatters.interval(session.startDate, session.endDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let warning = session.overlapWarning {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                }
                Divider()
            }
        }
    }

    private var unresolvedCard: some View {
        CreationCard("Unresolved questions") {
            if project.unresolvedQuestions.isEmpty {
                Text("No unresolved questions.")
                    .foregroundStyle(.secondary)
            }
            ForEach(project.unresolvedQuestions, id: \.self) { question in
                Label(question, systemImage: "questionmark.circle")
                    .foregroundStyle(.orange)
            }
            if let shortfall = project.shortfallWarning {
                Label(shortfall, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var completedProgress: Double {
        let approved = project.milestones.filter(\.isApproved)
        guard !approved.isEmpty else { return 0 }
        return Double(approved.filter { linkedTask(for: $0)?.status == .completed }.count) / Double(approved.count)
    }

    private var remainingMinutes: Int {
        project.milestones.reduce(0) { total, milestone in
            if let task = linkedTask(for: milestone), task.status == .completed {
                return total
            }
            return total + milestone.estimatedMinutes
        }
    }

    private var replanPreviewText: String {
        "Before: \(project.sessions.count) sessions. After: \(proposedSessions.count) sessions.\n\(proposedShortfall ?? "No shortfall detected.")\nCompleted tasks and locked sessions are preserved."
    }

    private func linkedTask(for milestone: AssignmentMilestoneDraft) -> AcademicTask? {
        guard let id = milestone.createdTaskID else { return nil }
        return tasks.first { $0.id == id }
    }

    private func makeReplanPreview() {
        let remainingMilestones = project.milestones.filter { milestone in
            guard milestone.isApproved else { return false }
            if let task = linkedTask(for: milestone), task.status == .completed {
                return false
            }
            return !milestone.isLocked
        }
        let result = AssignmentPlannerEngine.buildSessions(milestones: remainingMilestones, project: project, classSessions: classSessions, studyBlocks: studyBlocks)
        proposedSessions = result.sessions
        proposedShortfall = result.shortfall
        showingReplan = true
    }

    private func applyReplan() {
        let lockedOrCreated = project.sessions.filter { $0.isLocked || $0.createdStudyBlockID != nil }
        project.sessions = lockedOrCreated + proposedSessions
        project.shortfallWarning = proposedShortfall
        save()
        message = "Revised schedule preview applied. Confirm new sessions from the assignment import flow if you want Planner blocks created."
    }

    private func save() {
        AssignmentPlanStore.save(project, into: note)
        try? modelContext.save()
    }
}

enum GroupProjectMemberRole: String, Codable, CaseIterable, Identifiable {
    case coordinator
    case contributor
    case reviewer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coordinator: "Coordinator"
        case .contributor: "Contributor"
        case .reviewer: "Reviewer"
        }
    }
}

enum GroupProjectTaskStatus: String, Codable, CaseIterable, Identifiable {
    case unassigned
    case todo
    case inProgress
    case blocked
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unassigned: "Unassigned"
        case .todo: "To do"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .done: "Done"
        }
    }
}

struct GroupProjectMember: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var contact: String = ""
    var role: GroupProjectMemberRole = .contributor
    var isLocalStudent = false
    var addedAt: Date = .now
}

struct GroupProjectResponsibility: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var detail: String
    var deliverableReference: String?
    var milestoneID: UUID?
    var sourceTaskID: UUID?
    var ownerMemberID: UUID?
    var dueDate: Date?
    var estimatedMinutes: Int
    var status: GroupProjectTaskStatus = .unassigned
    var blocker: String = ""
    var dependencyIDs: [UUID] = []
    var lastUpdatedAt: Date = .now
}

struct GroupProjectHistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var text: String
}

struct LocalGroupProject: Codable {
    var schemaVersion = 1
    var title: String
    var assignmentNoteID: UUID
    var courseName: String
    var chapterTitle: String?
    var isLocalOnly = true
    var deliverables: [AssignmentRequirement] = []
    var milestones: [AssignmentMilestoneDraft] = []
    var members: [GroupProjectMember] = []
    var responsibilities: [GroupProjectResponsibility] = []
    var history: [GroupProjectHistoryEntry] = []
    var createdAt = Date()
    var updatedAt = Date()

    var nextAction: String {
        if members.count <= 1 { return "Add project members" }
        if responsibilities.contains(where: { $0.ownerMemberID == nil }) { return "Assign unassigned work" }
        if let blocked = responsibilities.first(where: { $0.status == .blocked }) { return "Resolve blocker: \(blocked.title)" }
        if let next = responsibilities.filter({ $0.status != .done }).sorted(by: { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }).first { return next.title }
        return "Review and submit"
    }

    var progress: Double {
        guard !responsibilities.isEmpty else { return 0 }
        let done = responsibilities.filter { $0.status == .done }.count
        return Double(done) / Double(responsibilities.count)
    }
}

enum GroupProjectStore {
    static let marker = "UNISAVER_LOCAL_GROUP_PROJECT_V1:"

    static func isGroupProject(_ note: StudyNote) -> Bool {
        note.body.hasPrefix(marker)
    }

    static func decode(_ note: StudyNote) -> LocalGroupProject {
        let raw = note.body.hasPrefix(marker) ? String(note.body.dropFirst(marker.count)) : ""
        if let data = raw.data(using: .utf8),
           let project = try? JSONDecoder().decode(LocalGroupProject.self, from: data) {
            return project
        }
        return LocalGroupProject(title: note.title, assignmentNoteID: note.id, courseName: note.course?.name ?? "Course")
    }

    static func save(_ project: LocalGroupProject, into note: StudyNote) {
        var copy = project
        copy.updatedAt = .now
        let data = (try? JSONEncoder().encode(copy)) ?? Data()
        note.title = copy.title
        note.body = marker + (String(data: data, encoding: .utf8) ?? "{}")
        note.updatedAt = .now
    }

    static func createLocalProject(from note: StudyNote, assignment: AssignmentPlanProject, context: ModelContext) -> StudyNote {
        let existing = (try? context.fetch(FetchDescriptor<StudyNote>()).first {
            guard $0.course?.id == note.course?.id, isGroupProject($0) else { return false }
            return decode($0).assignmentNoteID == note.id
        })
        if let existing {
            return existing
        }
        var project = LocalGroupProject(
            title: "Group · \(assignment.title)",
            assignmentNoteID: note.id,
            courseName: assignment.courseName,
            chapterTitle: assignment.chapterTitle,
            deliverables: assignment.deliverables,
            milestones: assignment.milestones,
            members: [GroupProjectMember(name: "Me", role: .coordinator, isLocalStudent: true)],
            responsibilities: assignment.milestones.map { milestone in
                GroupProjectResponsibility(
                    title: milestone.title,
                    detail: milestone.detail,
                    deliverableReference: milestone.sourceRequirementIDs.isEmpty ? nil : "Requirement-linked milestone",
                    milestoneID: milestone.id,
                    sourceTaskID: milestone.createdTaskID,
                    dueDate: milestone.dueDate,
                    estimatedMinutes: milestone.estimatedMinutes,
                    status: .unassigned,
                    dependencyIDs: milestone.dependencyIDs
                )
            },
            history: [GroupProjectHistoryEntry(text: "Local group project created from assignment “\(assignment.title)”. No invitations were sent.")]
        )
        if project.responsibilities.isEmpty {
            project.responsibilities = assignment.allRequirements.map { requirement in
                GroupProjectResponsibility(
                    title: requirement.title,
                    detail: requirement.detail,
                    deliverableReference: requirement.sourceReference,
                    dueDate: assignment.deadline,
                    estimatedMinutes: 60
                )
            }
        }
        let groupNote = StudyNote(title: project.title, course: note.course, chapter: note.chapter, resource: note.resource)
        GroupProjectStore.save(project, into: groupNote)
        context.insert(groupNote)
        return groupNote
    }
}

struct GroupProjectCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    let course: Course
    let onCreate: (StudyNote) -> Void
    @State private var selectedAssignmentID: UUID?
    @State private var errorMessage: String?

    private var assignmentNotes: [StudyNote] {
        notes.filter { $0.course?.id == course.id && AssignmentPlanStore.isAssignmentPlan($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create local group project")
                    .font(.title3.weight(.semibold))
                Text("Reuse an assignment’s deliverables, milestones and tasks. This is local planning only; UniSaver has no shared backend or access-control service in this build.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(StudyDeskTheme.surfacePrimary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if assignmentNotes.isEmpty {
                        ContentUnavailableView("No assignment plans", systemImage: "doc.badge.clock", description: Text("Create an assignment plan first, then turn it into a local group project."))
                    } else {
                        Picker("Assignment", selection: $selectedAssignmentID) {
                            ForEach(assignmentNotes) { note in
                                Text(note.title).tag(Optional(note.id))
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create project") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(assignmentNotes.isEmpty)
            }
            .padding(16)
            .background(StudyDeskTheme.surfacePrimary)
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            selectedAssignmentID = selectedAssignmentID ?? assignmentNotes.first?.id
        }
    }

    private func create() {
        guard let selectedAssignmentID,
              let note = assignmentNotes.first(where: { $0.id == selectedAssignmentID }) else {
            errorMessage = "Choose an assignment."
            return
        }
        let project = GroupProjectStore.createLocalProject(from: note, assignment: AssignmentPlanStore.decode(note), context: modelContext)
        try? modelContext.save()
        onCreate(project)
        dismiss()
    }
}

struct GroupProjectWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: StudyNote
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @State private var project: LocalGroupProject
    @State private var newMemberName = ""
    @State private var newMemberContact = ""
    @State private var suggestionPreview: [UUID: UUID] = [:]
    @State private var showingSuggestion = false
    @State private var showingScheduleSheet = false
    @State private var selectedResponsibilityID: UUID?

    init(note: StudyNote) {
        self.note = note
        _project = State(initialValue: GroupProjectStore.decode(note))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    localModeBanner
                    summaryGrid
                    deliverablesCard
                    membersCard
                    responsibilitiesCard
                    blockersCard
                    historyCard
                }
                .padding(24)
                .frame(maxWidth: 1080, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .confirmationDialog("Apply suggested division of work?", isPresented: $showingSuggestion) {
            Button("Apply assignments") { applySuggestion() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will assign currently unassigned responsibilities across members. You can reassign anything afterwards.")
        }
        .sheet(isPresented: $showingScheduleSheet) {
            scheduleSheet
        }
        .onDisappear(perform: save)
        .frame(minWidth: 900, minHeight: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.title)
                        .font(.title2.weight(.semibold))
                    Text("\(project.courseName)\(project.chapterTitle.map { " · \($0)" } ?? "")")
                        .foregroundStyle(.secondary)
                    Text(project.nextAction)
                        .font(.headline)
                }
                Spacer()
                Button("Suggest division", systemImage: "person.2.badge.gearshape") { buildSuggestionPreview() }
                    .buttonStyle(.bordered)
                    .disabled(project.members.isEmpty || project.responsibilities.isEmpty)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
            ProgressView(value: project.progress)
                .tint(CourseColor.blueViolet.color)
        }
        .padding(20)
        .background(StudyDeskTheme.surfacePrimary)
    }

    private var localModeBanner: some View {
        Label("Local group-planning mode: members, assignments and history are stored only in this UniSaver workspace. Real collaboration needs a backend with authentication, invitations, server-side permissions, conflict handling and explicit sharing rules.", systemImage: "lock.doc")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 12))
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            metric("Members", "\(project.members.count)")
            metric("Unassigned", "\(project.responsibilities.filter { $0.ownerMemberID == nil }.count)")
            metric("Blocked", "\(project.responsibilities.filter { $0.status == .blocked }.count)")
            metric("Due soon", "\(project.responsibilities.filter { dueSoon($0.dueDate) && $0.status != .done }.count)")
        }
    }

    private var deliverablesCard: some View {
        CreationCard("Deliverables") {
            if project.deliverables.isEmpty {
                Text("No explicit deliverables were extracted from the assignment.")
                    .foregroundStyle(.secondary)
            }
            ForEach(project.deliverables) { deliverable in
                VStack(alignment: .leading, spacing: 4) {
                    Text(deliverable.title)
                        .font(.subheadline.weight(.semibold))
                    Text(deliverable.detail)
                    Text(deliverable.sourceReference)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
        }
    }

    private var membersCard: some View {
        CreationCard("Project members") {
            ForEach($project.members) { $member in
                HStack {
                    TextField("Name", text: $member.name)
                    TextField("Contact optional", text: $member.contact)
                    Picker("Role", selection: $member.role) {
                        ForEach(GroupProjectMemberRole.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .frame(width: 150)
                }
            }
            Divider()
            HStack {
                TextField("Member name", text: $newMemberName)
                TextField("Email or note optional", text: $newMemberContact)
                Button("Add") { addMember() }
                    .disabled(newMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Adding a member here does not send an invitation or external message.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var responsibilitiesCard: some View {
        CreationCard("Responsibilities") {
            if project.responsibilities.isEmpty {
                Text("No responsibilities yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach($project.responsibilities) { $responsibility in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Task title", text: $responsibility.title)
                                .font(.subheadline.weight(.semibold))
                            Text(responsibility.detail)
                                .foregroundStyle(.secondary)
                            Text(responsibility.dueDate.map { "Due \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No due date")
                                .font(.caption)
                                .foregroundStyle(dueSoon(responsibility.dueDate) ? .orange : .secondary)
                        }
                        Spacer()
                        Button("Plan privately") {
                            selectedResponsibilityID = responsibility.id
                            showingScheduleSheet = true
                        }
                    }
                    HStack {
                        Picker("Owner", selection: $responsibility.ownerMemberID) {
                            Text("Unassigned").tag(UUID?.none)
                            ForEach(project.members) { member in
                                Text(member.name).tag(Optional(member.id))
                            }
                        }
                        .onChange(of: responsibility.ownerMemberID) { _, newOwner in
                            recordHistory("Reassigned “\(responsibility.title)” to \(memberName(newOwner)).")
                        }
                        Picker("Status", selection: $responsibility.status) {
                            ForEach(GroupProjectTaskStatus.allCases) { status in
                                Text(status.title).tag(status)
                            }
                        }
                        Stepper("\(responsibility.estimatedMinutes) min", value: $responsibility.estimatedMinutes, in: 15...900, step: 15)
                    }
                    if responsibility.status == .blocked {
                        TextField("Blocker", text: $responsibility.blocker)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(12)
                .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var blockersCard: some View {
        CreationCard("Blocked and approaching") {
            let blocked = project.responsibilities.filter { $0.status == .blocked || dueSoon($0.dueDate) && $0.status != .done }
            if blocked.isEmpty {
                Text("No blockers or urgent deadlines.")
                    .foregroundStyle(.secondary)
            }
            ForEach(blocked) { item in
                Label("\(item.title) · \(item.status.title)\(item.blocker.isEmpty ? "" : " · \(item.blocker)")", systemImage: item.status == .blocked ? "exclamationmark.triangle" : "calendar.badge.clock")
                    .foregroundStyle(item.status == .blocked ? .orange : .secondary)
            }
        }
    }

    private var historyCard: some View {
        CreationCard("Recent changes") {
            ForEach(project.history.sorted { $0.date > $1.date }.prefix(8)) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.text)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
        }
    }

    private var scheduleSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Private work session")
                .font(.title3.weight(.semibold))
            Text("This creates a local Planner block for you only. It does not expose your calendar to group members.")
                .foregroundStyle(.secondary)
            Button("Create 60-minute session tomorrow") {
                scheduleSelectedResponsibility()
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") { showingScheduleSheet = false }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func addMember() {
        let name = newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        project.members.append(GroupProjectMember(name: name, contact: newMemberContact.trimmingCharacters(in: .whitespacesAndNewlines)))
        recordHistory("Added member \(name). No invitation was sent.")
        newMemberName = ""
        newMemberContact = ""
        save()
    }

    private func buildSuggestionPreview() {
        let members = project.members
        guard !members.isEmpty else { return }
        var preview: [UUID: UUID] = [:]
        let unassigned = project.responsibilities.filter { $0.ownerMemberID == nil }
        for (index, item) in unassigned.enumerated() {
            preview[item.id] = members[index % members.count].id
        }
        suggestionPreview = preview
        showingSuggestion = true
    }

    private func applySuggestion() {
        for index in project.responsibilities.indices {
            if let owner = suggestionPreview[project.responsibilities[index].id] {
                project.responsibilities[index].ownerMemberID = owner
                project.responsibilities[index].status = .todo
                project.responsibilities[index].lastUpdatedAt = .now
            }
        }
        recordHistory("Applied suggested division of currently unassigned work.")
        suggestionPreview = [:]
        save()
    }

    private func scheduleSelectedResponsibility() {
        guard let selectedResponsibilityID,
              let responsibility = project.responsibilities.first(where: { $0.id == selectedResponsibilityID }) else {
            showingScheduleSheet = false
            return
        }
        let start = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
        let rounded = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: start) ?? start
        let task = responsibility.sourceTaskID.flatMap { id in tasks.first { $0.id == id } }
        let block = StudyBlock(
            title: "Group project · \(responsibility.title)",
            startDate: rounded,
            endDate: rounded.addingTimeInterval(3600),
            status: .planned,
            course: note.course,
            task: task
        )
        modelContext.insert(block)
        recordHistory("Created a private local work session for “\(responsibility.title)”.")
        save()
        showingScheduleSheet = false
    }

    private func memberName(_ id: UUID?) -> String {
        guard let id, let member = project.members.first(where: { $0.id == id }) else { return "Unassigned" }
        return member.name
    }

    private func dueSoon(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date <= Date().addingTimeInterval(7 * 86_400)
    }

    private func recordHistory(_ text: String) {
        project.history.append(GroupProjectHistoryEntry(text: text))
    }

    private func save() {
        GroupProjectStore.save(project, into: note)
        try? modelContext.save()
    }
}

enum ResearchPaperStage: String, Codable, CaseIterable, Identifiable {
    case frame
    case sources
    case arguments
    case drafting
    case revision
    case submitted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frame: "Cadrage"
        case .sources: "Sources"
        case .arguments: "Arguments"
        case .drafting: "Rédaction"
        case .revision: "Révision"
        case .submitted: "Remis"
        }
    }
}

enum ResearchPaperItemStatus: String, Codable, CaseIterable, Identifiable {
    case idea
    case toVerify
    case confirmed
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idea: "Idée"
        case .toVerify: "À vérifier"
        case .confirmed: "Confirmé"
        case .rejected: "Écarté"
        }
    }
}

enum ResearchSourceStatus: String, Codable, CaseIterable, Identifiable {
    case collected
    case toRead
    case reading
    case used
    case cited
    case discarded
    case needsVerification

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collected: "Collectée"
        case .toRead: "À lire"
        case .reading: "En lecture"
        case .used: "Exploitée"
        case .cited: "Citée"
        case .discarded: "Écartée"
        case .needsVerification: "Référence à vérifier"
        }
    }
}

struct ResearchPaperProject: Codable {
    var schemaVersion = 1
    var title: String
    var courseName: String
    var chapterTitle: String?
    var stage: ResearchPaperStage = .frame
    var prompt: String = ""
    var dueDate: Date?
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var expectedLength: String = ""
    var citationStyle: String = "APA"
    var language: String = Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
    var criteria: String = ""
    var requiredSections: String = ""
    var constraints: String = ""
    var topic: ResearchPaperTrackedText = .init(label: "Sujet envisagé")
    var researchQuestion: ResearchPaperTrackedText = .init(label: "Question de recherche")
    var thesis: ResearchPaperTrackedText = .init(label: "Thèse provisoire")
    var scope: ResearchPaperTrackedText = .init(label: "Périmètre")
    var topics: [ResearchTopicCandidate] = []
    var sources: [ResearchSourceDraft] = []
    var arguments: [ResearchArgumentDraft] = []
    var outline: [ResearchOutlineSection] = []
    var figures: [ResearchFigureDraft] = []
    var drafts: [ResearchDraftSection] = []
    var reviewComments: [ResearchReviewComment] = []
    var bibliographyManualEdits: String = ""
    var exportedDraft: String = ""
    var lastSavedAt: Date = .now

    var nextAction: String {
        if researchQuestion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Définir la question de recherche" }
        if sources.filter({ $0.status != .discarded }).count < 3 { return "Ajouter et vérifier les premières sources" }
        if arguments.isEmpty { return "Formuler un premier argument appuyé par une source" }
        if outline.isEmpty { return "Construire le plan" }
        if drafts.allSatisfy({ $0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return "Rédiger la première section" }
        return "Réviser le fond et les références"
    }

    var progress: Double {
        let checks = [
            !researchQuestion.text.isEmpty,
            !thesis.text.isEmpty,
            sources.contains { $0.status == .used || $0.status == .cited },
            arguments.contains { !$0.claim.isEmpty && $0.supportingSourceID != nil },
            !outline.isEmpty,
            drafts.contains { !$0.body.isEmpty },
            sources.allSatisfy { !$0.isCited || $0.missingBibliographyFields.isEmpty }
        ]
        return Double(checks.filter { $0 }.count) / Double(checks.count)
    }
}

struct ResearchPaperTrackedText: Codable, Identifiable {
    var id = UUID()
    var label: String
    var text: String = ""
    var status: ResearchPaperItemStatus = .idea
}

struct ResearchTopicCandidate: Codable, Identifiable {
    var id = UUID()
    var title: String = ""
    var personalInterest: String = ""
    var feasibility: String = ""
    var sourceAvailability: String = ""
    var mainObjection: String = ""
    var decision: ResearchPaperItemStatus = .idea
}

struct ResearchSourceDraft: Codable, Identifiable {
    var id = UUID()
    var title: String = ""
    var author: String = ""
    var year: String = ""
    var container: String = ""
    var pages: String = ""
    var doi: String = ""
    var url: String = ""
    var isbn: String = ""
    var sourceType: String = "Article"
    var status: ResearchSourceStatus = .collected
    var relevance: String = ""
    var reliability: String = ""
    var personalSummary: String = ""
    var keyConcepts: String = ""
    var limitations: String = ""
    var quotations: String = ""
    var paraphrases: String = ""
    var supportsArguments: String = ""
    var accessDate: Date?
    var linkedResourceID: UUID?
    var tags: String = ""

    var isCited: Bool { status == .cited }

    var missingBibliographyFields: [String] {
        var missing: [String] = []
        if author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("auteur") }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("titre") }
        if year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("année") }
        if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && doi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("URL/DOI") }
        return missing
    }
}

struct ResearchArgumentDraft: Codable, Identifiable {
    var id = UUID()
    var claim: String = ""
    var supportingSourceID: UUID?
    var supportPassage: String = ""
    var counterSourceID: UUID?
    var counterPassage: String = ""
    var analysis: String = ""
    var confidence: String = "À vérifier"
    var missingInformation: String = ""
    var outlineSectionID: UUID?
}

struct ResearchOutlineSection: Codable, Identifiable {
    var id = UUID()
    var title: String = ""
    var objective: String = ""
    var keyClaim: String = ""
    var notes: String = ""
    var supportingSourceIDs: [UUID] = []
    var targetWords: Int = 300
    var isSkipped = false
}

struct ResearchFigureDraft: Codable, Identifiable {
    var id = UUID()
    var title: String = ""
    var source: String = ""
    var license: String = ""
    var caption: String = ""
    var plannedLocation: String = ""
}

struct ResearchDraftSection: Codable, Identifiable {
    var id = UUID()
    var sectionID: UUID?
    var title: String = ""
    var body: String = ""
    var linkedSourceIDs: [UUID] = []
    var updatedAt: Date = .now
}

struct ResearchReviewComment: Codable, Identifiable {
    var id = UUID()
    var pass: String = "Fond"
    var excerpt: String = ""
    var comment: String = ""
    var sourceEvidence: String = ""
    var status: String = "À traiter"
}

enum ResearchPaperStore {
    static let marker = "UNISAVER_RESEARCH_PAPER_V1:"

    static func isResearchPaper(_ note: StudyNote) -> Bool {
        note.body.hasPrefix(marker)
    }

    static func decode(_ note: StudyNote) -> ResearchPaperProject {
        let raw = note.body.hasPrefix(marker) ? String(note.body.dropFirst(marker.count)) : ""
        if let data = raw.data(using: .utf8),
           let project = try? JSONDecoder().decode(ResearchPaperProject.self, from: data) {
            return project
        }
        return ResearchPaperProject(title: note.title, courseName: note.course?.name ?? "Course", chapterTitle: note.chapter?.title)
    }

    static func save(_ project: ResearchPaperProject, into note: StudyNote) {
        var copy = project
        copy.lastSavedAt = .now
        let data = (try? JSONEncoder().encode(copy)) ?? Data()
        note.title = copy.title
        note.body = marker + (String(data: data, encoding: .utf8) ?? "{}")
        note.updatedAt = .now
    }
}

func researchWordCount(_ text: String) -> Int {
    text.split { $0.isWhitespace || $0.isNewline }.count
}

struct ResearchPaperCompactRow: View {
    let note: StudyNote

    private var project: ResearchPaperProject {
        ResearchPaperStore.decode(note)
    }

    var body: some View {
        compactResearchRow(
            title: project.title,
            subtitle: "\(project.stage.title) · \(project.nextAction)",
            progress: project.progress
        )
    }

    private func compactResearchRow(title: String, subtitle: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: progress)
        }
        .padding(12)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(StudyDeskTheme.borderSubtle) }
    }
}

struct ResearchPaperCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let fixedCourse: Course?
    let availableCourses: [Course]
    let onCreate: (StudyNote) -> Void
    @State private var title = ""
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var prompt = ""
    @State private var hasDueDate = true
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 21, to: .now) ?? .now
    @State private var expectedLength = ""
    @State private var citationStyle = "APA"
    @State private var language = Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
    @State private var criteria = ""
    @State private var researchQuestion = ""
    @State private var thesis = ""
    @State private var error: String?

    init(course: Course, chapters: [Chapter], onCreate: @escaping (StudyNote) -> Void) {
        self.fixedCourse = course
        self.availableCourses = [course]
        self.onCreate = onCreate
        _selectedCourseID = State(initialValue: course.id)
    }

    init(courses: [Course], onCreate: @escaping (StudyNote) -> Void) {
        self.fixedCourse = nil
        self.availableCourses = courses.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.onCreate = onCreate
        _selectedCourseID = State(initialValue: courses.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.first?.id)
    }

    private var selectedCourse: Course? {
        if let fixedCourse { return fixedCourse }
        return availableCourses.first { $0.id == selectedCourseID }
    }

    private var chapters: [Chapter] {
        selectedCourse?.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order } ?? []
    }

    private var selectedChapter: Chapter? {
        chapters.first { $0.id == selectedChapterID }
    }

    var body: some View {
        CreationWindow(
            icon: "doc.text.magnifyingglass",
            title: "Research Paper",
            subtitle: "Cadre le travail avant de collecter les sources et de rédiger.",
            accent: CourseColor.indigo.color,
            closeAction: { dismiss() }
        ) {
            CreationCard("Projet") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Titre provisoire", text: $title)
                        .textFieldStyle(.roundedBorder)
                    if fixedCourse == nil {
                        Picker("Matière", selection: $selectedCourseID) {
                            Text("À choisir").tag(UUID?.none)
                            ForEach(availableCourses) { course in
                                Text(course.name).tag(Optional(course.id))
                            }
                        }
                    } else if let selectedCourse {
                        LabeledContent("Matière", value: selectedCourse.name)
                    }
                    Picker("Chapitre", selection: $selectedChapterID) {
                        Text("Toute la matière").tag(UUID?.none)
                        ForEach(chapters) { chapter in
                            Text(chapter.title).tag(Optional(chapter.id))
                        }
                    }
                    TextField("Consigne originale", text: $prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Échéance", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date et heure de remise", selection: $dueDate)
                    }
                    TextField("Longueur demandée", text: $expectedLength)
                        .textFieldStyle(.roundedBorder)
                    TextField("Style bibliographique", text: $citationStyle)
                        .textFieldStyle(.roundedBorder)
                    TextField("Langue du travail", text: $language)
                        .textFieldStyle(.roundedBorder)
                    TextField("Critères / contraintes", text: $criteria, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
            }
            CreationCard("Cadrage initial") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Question de recherche provisoire", text: $researchQuestion, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    TextField("Thèse provisoire", text: $thesis, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Text("L’IA pourra poser des questions de cadrage plus tard, mais rien n’est présenté comme validé par le professeur.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                CreationPrimaryButton(title: "Créer", systemImage: "checkmark.circle.fill", accent: CourseColor.indigo.color, isDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: create)
            }
        }
        .frame(minWidth: 660, idealWidth: 780, minHeight: 620, idealHeight: 720)
    }

    private func create() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            error = "Titre requis."
            return
        }
        guard let selectedCourse else {
            error = "Choisis une matière pour créer le projet."
            return
        }
        var project = ResearchPaperProject(title: cleanTitle, courseName: selectedCourse.name, chapterTitle: selectedChapter?.title)
        project.prompt = prompt
        project.dueDate = hasDueDate ? dueDate : nil
        project.expectedLength = expectedLength
        project.citationStyle = citationStyle
        project.language = language
        project.criteria = criteria
        project.researchQuestion.text = researchQuestion
        project.thesis.text = thesis
        project.outline = [
            ResearchOutlineSection(title: "Introduction", objective: "Présenter la question, le contexte et la thèse.", targetWords: 300),
            ResearchOutlineSection(title: "Développement", objective: "Déployer les arguments soutenus par les sources.", targetWords: 900),
            ResearchOutlineSection(title: "Conclusion", objective: "Répondre à la question et préciser les limites.", targetWords: 250)
        ]
        project.drafts = project.outline.map { ResearchDraftSection(sectionID: $0.id, title: $0.title) }
        let note = StudyNote(title: cleanTitle, course: selectedCourse, chapter: selectedChapter)
        ResearchPaperStore.save(project, into: note)
        modelContext.insert(note)
        do {
            try modelContext.save()
            onCreate(note)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum ResearchPaperWorkspaceTab: String, CaseIterable, Identifiable {
    case project = "Projet"
    case sources = "Sources"
    case arguments = "Arguments et plan"
    case drafting = "Rédaction"
    case revision = "Révision"

    var id: String { rawValue }
}

struct ResearchPaperWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var projectNote: StudyNote
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @State private var project: ResearchPaperProject
    @State private var tab: ResearchPaperWorkspaceTab = .project
    @State private var selectedDraftID: UUID?
    @State private var blockedPasteMessage: String?
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var showingMilestonePreview = false
    @State private var pendingAIPass: String?
    @State private var feedbackInProgress = false

    init(projectNote: StudyNote) {
        self.projectNote = projectNote
        _project = State(initialValue: ResearchPaperStore.decode(projectNote))
    }

    private var courseResources: [AcademicResource] {
        resources.filter { resource in
            resource.course?.id == projectNote.course?.id
                && (projectNote.chapter == nil || resource.chapter?.id == projectNote.chapter?.id || resource.session?.chapter?.id == projectNote.chapter?.id)
        }
    }

    private var currentDraftIndex: Int? {
        if let selectedDraftID, let index = project.drafts.firstIndex(where: { $0.id == selectedDraftID }) {
            return index
        }
        return project.drafts.indices.first
    }

    var body: some View {
        VStack(spacing: 0) {
            researchHeader
            Picker("Section", selection: $tab) {
                ForEach(ResearchPaperWorkspaceTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(12)
                            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(12)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    switch tab {
                    case .project:
                        projectSection
                    case .sources:
                        sourcesSection
                    case .arguments:
                        argumentsSection
                    case .drafting:
                        draftingSection
                    case .revision:
                        revisionSection
                    }
                }
                .padding(24)
                .frame(maxWidth: 1120, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .onDisappear(perform: save)
        .confirmationDialog("Créer les jalons dans Planner ?", isPresented: $showingMilestonePreview) {
            Button("Créer les tâches manquantes") {
                createMilestones()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("UniSaver propose des tâches liées à cette matière. Les tâches terminées ou déjà créées ne sont pas dupliquées.")
        }
        .confirmationDialog("Envoyer ce contenu au fournisseur IA ?", isPresented: Binding(get: { pendingAIPass != nil }, set: { if !$0 { pendingAIPass = nil } })) {
            Button("Envoyer les sections et sources sélectionnées") {
                if let pendingAIPass {
                    requestAIReview(pass: pendingAIPass)
                }
                pendingAIPass = nil
            }
            Button("Annuler", role: .cancel) {
                pendingAIPass = nil
            }
        } message: {
            Text(aiConsentPreview)
        }
        .frame(minWidth: 980, minHeight: 760)
    }

    private var researchHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.title)
                        .font(.largeTitle.bold())
                    Text(project.nextAction)
                        .font(.title3.weight(.semibold))
                    Text(nextDeadlineText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Continuer", systemImage: "arrow.right.circle.fill") {
                    tab = nextTab
                }
                .buttonStyle(.borderedProminent)
            }
            ProgressView(value: project.progress)
                .tint(CourseColor.indigo.color)
            HStack(spacing: 10) {
                Label(project.stage.title, systemImage: "location")
                Label("\(project.sources.filter { $0.status == .cited }.count) citées", systemImage: "text.quote")
                Label("\(project.arguments.count) arguments", systemImage: "rectangle.and.pencil.and.ellipsis")
                Label("\(totalWordCount) mots", systemImage: "textformat")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(
            LinearGradient(colors: [CourseColor.indigo.color.opacity(0.12), StudyDeskTheme.surfacePrimary], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CreationCard("Cadrage") {
                trackedTextEditor($project.topic)
                trackedTextEditor($project.researchQuestion)
                trackedTextEditor($project.thesis)
                trackedTextEditor($project.scope)
            }
            CreationCard("Atelier de sujets") {
                if project.topics.isEmpty {
                    Text("Ajoute deux ou trois sujets candidats. L’IA peut questionner la largeur du sujet, mais ne valide rien à la place du professeur.")
                        .foregroundStyle(.secondary)
                }
                ForEach($project.topics) { $topic in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Sujet candidat", text: $topic.title)
                            .textFieldStyle(.roundedBorder)
                        TextField("Intérêt personnel", text: $topic.personalInterest, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        TextField("Faisabilité et sources disponibles", text: $topic.feasibility, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        TextField("Objection principale", text: $topic.mainObjection, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Picker("Décision", selection: $topic.decision) {
                            ForEach(ResearchPaperItemStatus.allCases) { status in Text(status.title).tag(status) }
                        }
                    }
                    .padding(12)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                }
                Button("Ajouter un sujet", systemImage: "plus") {
                    project.topics.append(ResearchTopicCandidate())
                    save()
                }
            }
            CreationCard("Échéance et jalons") {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("Date de remise", selection: Binding(get: { project.dueDate ?? .now }, set: { project.dueDate = $0 }))
                    TextField("Style bibliographique", text: $project.citationStyle)
                        .textFieldStyle(.roundedBorder)
                    TextField("Sections obligatoires / contraintes", text: $project.requiredSections, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button("Prévoir les jalons", systemImage: "calendar.badge.plus") {
                        showingMilestonePreview = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CreationCard("Ajouter une source") {
                Text("DOI, URL, ISBN, fichier ou saisie manuelle sont conservés comme métadonnées à vérifier. Cette version ne récupère pas automatiquement les métadonnées et n’invente rien.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Nouvelle source manuelle", systemImage: "plus") {
                        project.sources.append(ResearchSourceDraft())
                        save()
                    }
                    Menu("Depuis une ressource", systemImage: "doc.badge.plus") {
                        if courseResources.isEmpty {
                            Text("Aucune ressource liée")
                        }
                        ForEach(courseResources) { resource in
                            Button(resource.title) {
                                addSource(from: resource)
                            }
                        }
                    }
                }
            }
            ForEach($project.sources) { $source in
                ResearchSourceEditor(source: $source, project: project)
            }
            CreationCard("Bibliographie provisoire") {
                Text(bibliographyText)
                    .textSelection(.enabled)
                Text("Les champs manquants restent visibles. Vérifie manuellement le style \(project.citationStyle).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Copier la bibliographie", systemImage: "doc.on.doc") {
                    copyToPasteboard(bibliographyText)
                    message = "Bibliographie copiée."
                }
            }
        }
    }

    private var argumentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CreationCard("Matrice d’arguments") {
                if project.arguments.isEmpty {
                    Text("Commence par une affirmation formulée par toi, puis choisis les sources qui la soutiennent ou la nuancent.")
                        .foregroundStyle(.secondary)
                }
                ForEach($project.arguments) { $argument in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Affirmation", text: $argument.claim, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Picker("Source qui soutient", selection: $argument.supportingSourceID) {
                            Text("À choisir").tag(UUID?.none)
                            ForEach(project.sources) { source in Text(source.title.isEmpty ? "Source sans titre" : source.title).tag(Optional(source.id)) }
                        }
                        TextField("Passage / page", text: $argument.supportPassage, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Picker("Section du plan", selection: $argument.outlineSectionID) {
                            Text("Non placée").tag(UUID?.none)
                            ForEach(project.outline) { section in
                                Text(section.title).tag(Optional(section.id))
                            }
                        }
                        Picker("Source qui nuance ou contredit", selection: $argument.counterSourceID) {
                            Text("Aucune").tag(UUID?.none)
                            ForEach(project.sources) { source in Text(source.title.isEmpty ? "Source sans titre" : source.title).tag(Optional(source.id)) }
                        }
                        TextField("Analyse personnelle", text: $argument.analysis, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        TextField("Information encore à chercher", text: $argument.missingInformation, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(12)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                }
                Button("Ajouter un argument", systemImage: "plus") {
                    project.arguments.append(ResearchArgumentDraft())
                    save()
                }
            }
            CreationCard("Plan") {
                ForEach($project.outline) { $section in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Section", text: $section.title)
                            .textFieldStyle(.roundedBorder)
                        TextField("Objectif", text: $section.objective, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        TextField("Claim principal", text: $section.keyClaim, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        TextField("Notes de plan", text: $section.notes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Menu("Sources liées à cette section") {
                            if project.sources.isEmpty {
                                Text("Aucune source")
                            }
                            ForEach(project.sources) { source in
                                let isLinked = section.supportingSourceIDs.contains(source.id)
                                Button(isLinked ? "Retirer \(source.title.isEmpty ? "source sans titre" : source.title)" : "Lier \(source.title.isEmpty ? "source sans titre" : source.title)") {
                                    if isLinked {
                                        section.supportingSourceIDs.removeAll { $0 == source.id }
                                    } else {
                                        section.supportingSourceIDs.append(source.id)
                                    }
                                    save()
                                }
                            }
                        }
                        Stepper("Cible \(section.targetWords) mots", value: $section.targetWords, in: 50...3000, step: 50)
                        Toggle("Section ignorée", isOn: $section.isSkipped)
                        Text(sectionEvidenceWarning(section))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(12)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                }
                Button("Ajouter une section", systemImage: "plus") {
                    let section = ResearchOutlineSection(title: "Nouvelle section", objective: "", targetWords: 300)
                    project.outline.append(section)
                    project.drafts.append(ResearchDraftSection(sectionID: section.id, title: section.title))
                    save()
                }
            }
            figuresSection
        }
    }

    private var figuresSection: some View {
        CreationCard("Schémas et figures") {
            ForEach($project.figures) { $figure in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Titre", text: $figure.title)
                        .textFieldStyle(.roundedBorder)
                    TextField("Source / provenance", text: $figure.source)
                        .textFieldStyle(.roundedBorder)
                    TextField("Licence ou autorisation connue", text: $figure.license)
                        .textFieldStyle(.roundedBorder)
                    TextField("Légende", text: $figure.caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    TextField("Emplacement prévu", text: $figure.plannedLocation)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(12)
                .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
            }
            Button("Ajouter une figure", systemImage: "photo.badge.plus") {
                project.figures.append(ResearchFigureDraft())
                save()
            }
        }
    }

    private var draftingSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sections")
                    .font(.headline)
                ForEach(project.drafts) { draft in
                    Button {
                        selectedDraftID = draft.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.title)
                            Text("\(researchWordCount(draft.body)) mots")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(selectedDraftID == draft.id ? CourseColor.indigo.color.opacity(0.14) : StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                Text("Sources citées et références incomplètes")
                    .font(.headline)
                Text(referenceWarnings)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !project.sources.isEmpty {
                    Menu("Insérer une citation", systemImage: "quote.opening") {
                        ForEach(project.sources) { source in
                            Button(source.title.isEmpty ? "Source sans titre" : source.title) {
                                insertCitation(source)
                            }
                        }
                    }
                    .disabled(currentDraftIndex == nil)
                }
                Button("Exporter le brouillon", systemImage: "square.and.arrow.up") {
                    exportDraft()
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 260)

            if let index = currentDraftIndex {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(project.drafts[index].title)
                            .font(.title2.bold())
                        Spacer()
                        Text("\(researchWordCount(project.drafts[index].body)) mots")
                            .font(.headline)
                    }
                    NoPasteEssayEditor(
                        text: Binding(
                            get: { project.drafts[index].body },
                            set: { value in
                                project.drafts[index].body = value
                                project.drafts[index].updatedAt = .now
                                save()
                            }
                        ),
                        blockedMessage: $blockedPasteMessage
                    )
                    .frame(minHeight: 430)
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(StudyDeskTheme.borderSubtle) }
                    if let blockedPasteMessage {
                        Text(blockedPasteMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("L’IA ne remplace jamais cette rédaction. Lie chaque affirmation importante à une source vérifiable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var revisionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CreationCard("Passes de révision") {
                HStack {
                    Button(feedbackInProgress ? "Analyse..." : "Réviser le fond avec l’IA", systemImage: "brain.head.profile") {
                        pendingAIPass = "Fond"
                    }
                    .disabled(feedbackInProgress)
                    Button(feedbackInProgress ? "Analyse..." : "Réviser la forme avec l’IA", systemImage: "text.magnifyingglass") {
                        pendingAIPass = "Forme"
                    }
                    .disabled(feedbackInProgress)
                }
                .buttonStyle(.borderedProminent)
                Text("Avant l’envoi, UniSaver montre les sections et les sources utilisées. Les retours restent séparés du brouillon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Sans fournisseur IA, les contrôles déterministes restent disponibles : plan, arguments sans source, références incomplètes, sections vides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            CreationCard("Export") {
                Button("Exporter le brouillon et la bibliographie", systemImage: "square.and.arrow.up") {
                    exportDraft()
                }
                .buttonStyle(.borderedProminent)
                Text(exportWarnings)
                    .font(.caption)
                    .foregroundStyle(exportWarnings.isEmpty ? Color.secondary : Color.orange)
            }
            CreationCard("Contrôles sans IA") {
                Text(deterministicReview)
                    .textSelection(.enabled)
            }
            CreationCard("Commentaires") {
                if project.reviewComments.isEmpty {
                    Text("Aucun retour enregistré.")
                        .foregroundStyle(.secondary)
                }
                ForEach($project.reviewComments) { $comment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(comment.pass)
                            .font(.headline)
                        TextField("Extrait réel du brouillon", text: $comment.excerpt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        TextField("Commentaire", text: $comment.comment, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        TextField("Élément de source disponible", text: $comment.sourceEvidence, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Picker("État", selection: $comment.status) {
                            Text("À traiter").tag("À traiter")
                            Text("Traitée").tag("Traitée")
                            Text("Rejetée").tag("Rejetée")
                        }
                    }
                    .padding(12)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func trackedTextEditor(_ item: Binding<ResearchPaperTrackedText>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.wrappedValue.label)
                .font(.headline)
            TextField(item.wrappedValue.label, text: item.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Picker("Statut", selection: item.status) {
                ForEach(ResearchPaperItemStatus.allCases) { status in Text(status.title).tag(status) }
            }
        }
    }

    private var nextTab: ResearchPaperWorkspaceTab {
        switch project.stage {
        case .frame: .project
        case .sources: .sources
        case .arguments: .arguments
        case .drafting: .drafting
        case .revision, .submitted: .revision
        }
    }

    private var nextDeadlineText: String {
        guard let dueDate = project.dueDate else { return "Aucune échéance enregistrée" }
        return "Échéance \(UniDateFormatters.dayMonth.string(from: dueDate)) · \(project.timeZoneIdentifier)"
    }

    private var totalWordCount: Int {
        project.drafts.reduce(0) { $0 + researchWordCount($1.body) }
    }

    private var bibliographyText: String {
        let lines = project.sources.map { source in
            let warning = source.missingBibliographyFields.isEmpty ? "" : " [à vérifier: \(source.missingBibliographyFields.joined(separator: ", "))]"
            return "\(source.author.isEmpty ? "Auteur manquant" : source.author) (\(source.year.isEmpty ? "année manquante" : source.year)). \(source.title.isEmpty ? "Titre manquant" : source.title). \(source.container)\(source.doi.isEmpty ? "" : " DOI: \(source.doi)")\(source.url.isEmpty ? "" : " \(source.url)")\(warning)"
        }
        return lines.isEmpty ? "Aucune source." : lines.joined(separator: "\n\n")
    }

    private var exportWarnings: String {
        var warnings: [String] = []
        let incomplete = project.sources.filter { $0.isCited && !$0.missingBibliographyFields.isEmpty }
        if !incomplete.isEmpty {
            warnings.append("\(incomplete.count) référence(s) citées ont des métadonnées manquantes.")
        }
        let unsupported = project.arguments.filter { $0.supportingSourceID == nil || $0.supportPassage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !unsupported.isEmpty {
            warnings.append("\(unsupported.count) claim(s) n’ont pas de source et page/passage précis.")
        }
        let unattachedFigures = project.figures.filter { $0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.plannedLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !unattachedFigures.isEmpty {
            warnings.append("\(unattachedFigures.count) figure(s) ont une provenance ou un emplacement incomplet.")
        }
        return warnings.joined(separator: "\n")
    }

    private var aiConsentPreview: String {
        let sections = project.drafts.filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.title)
        let sourceTitles = project.sources.filter { source in
            ![source.personalSummary, source.quotations, source.paraphrases, source.limitations].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }.map { $0.title.isEmpty ? "Source sans titre" : $0.title }
        return """
        Sections envoyées: \(sections.isEmpty ? "aucune section rédigée" : sections.joined(separator: ", "))
        Sources envoyées: \(sourceTitles.isEmpty ? "aucun extrait exploitable" : sourceTitles.joined(separator: ", "))
        Les clés API ne sont jamais incluses dans l’historique local. Le brouillon ne sera pas modifié automatiquement.
        """
    }

    private var referenceWarnings: String {
        let unused = project.sources.filter { source in
            !project.arguments.contains { $0.supportingSourceID == source.id || $0.counterSourceID == source.id }
        }
        let missing = project.sources.filter { !$0.missingBibliographyFields.isEmpty }
        return "Sources jamais utilisées: \(unused.count)\nRéférences à vérifier: \(missing.count)"
    }

    private var deterministicReview: String {
        let emptySections = project.drafts.filter { $0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.title)
        let unsupportedArguments = project.arguments.filter { $0.supportingSourceID == nil || $0.supportPassage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return """
        Sections vides: \(emptySections.isEmpty ? "aucune" : emptySections.joined(separator: ", "))
        Arguments sans preuve précise: \(unsupportedArguments)
        \(referenceWarnings)
        Qualité non déduite automatiquement: ces contrôles indiquent ce qui manque, pas la valeur du devoir.
        """
    }

    private func sectionEvidenceWarning(_ section: ResearchOutlineSection) -> String {
        let count = project.arguments.filter { $0.outlineSectionID == section.id }.count
        let sourceCount = section.supportingSourceIDs.count
        if count == 0 && sourceCount == 0 {
            return "Aucun argument ou source explicitement lié à cette section."
        }
        return "\(count) argument(s) · \(sourceCount) source(s) liée(s)."
    }

    private func addSource(from resource: AcademicResource) {
        if project.sources.contains(where: { $0.linkedResourceID == resource.id || normalizedTitle($0.title) == normalizedTitle(resource.title) }) {
            errorMessage = "Doublon probable détecté : cette ressource est déjà suivie comme source."
            return
        }
        var source = ResearchSourceDraft()
        source.title = resource.title
        source.sourceType = resource.effectiveResourceKindTitle
        source.linkedResourceID = resource.id
        source.status = .toRead
        source.url = resource.storedRelativePath
        source.relevance = "À évaluer"
        project.sources.append(source)
        save()
        message = "Source ajoutée depuis \(resource.title)."
    }

    private func insertCitation(_ source: ResearchSourceDraft) {
        guard let index = currentDraftIndex else { return }
        let author = source.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = source.year.trimmingCharacters(in: .whitespacesAndNewlines)
        let citation = " (\(author.isEmpty ? source.title : author)\(year.isEmpty ? "" : ", \(year)"), p. )"
        project.drafts[index].body += citation
        project.drafts[index].updatedAt = .now
        if let sourceIndex = project.sources.firstIndex(where: { $0.id == source.id }), project.sources[sourceIndex].status != .cited {
            project.sources[sourceIndex].status = .cited
        }
        save()
    }

    private func exportDraft() {
        let body = project.drafts
            .filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "# \($0.title)\n\n\($0.body)" }
            .joined(separator: "\n\n")
        let figures = project.figures.map { figure in
            "Figure: \(figure.title)\nCaption: \(figure.caption)\nSource: \(figure.source)\nPermission: \(figure.license)\nPlacement: \(figure.plannedLocation)"
        }.joined(separator: "\n\n")
        let export = """
        \(project.title)
        Course: \(project.courseName)
        Research question: \(project.researchQuestion.text)
        Thesis: \(project.thesis.text)

        \(body.isEmpty ? "[Aucun brouillon rédigé]" : body)

        \(figures.isEmpty ? "" : "Figures\n\n\(figures)\n\n")
        Bibliography (\(project.citationStyle))

        \(bibliographyText)

        Warnings
        \(exportWarnings.isEmpty ? "Aucun avertissement bloquant détecté." : exportWarnings)
        """
        project.exportedDraft = export
        copyToPasteboard(export)
        save()
        message = "Export copié dans le presse-papiers. Vérifie les avertissements avant remise."
    }

    private func normalizedTitle(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func copyToPasteboard(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }

    private func createMilestones() {
        guard let dueDate = project.dueDate, let course = projectNote.course else { return }
        let titles = [
            "Research Paper · valider la question de recherche",
            "Research Paper · réunir un premier corpus",
            "Research Paper · terminer les lectures prioritaires",
            "Research Paper · construire le plan",
            "Research Paper · finir le premier brouillon",
            "Research Paper · réviser l’argumentation",
            "Research Paper · vérifier citations et figures",
            "Research Paper · relire et remettre"
        ]
        for (index, title) in titles.enumerated() {
            let alreadyExists = tasks.contains { task in
                task.course?.id == course.id &&
                    task.chapter?.id == projectNote.chapter?.id &&
                    task.title == title &&
                    task.taskDescription.contains(projectNote.id.uuidString)
            }
            guard !alreadyExists else { continue }
            let daysBefore = max(1, (titles.count - index) * 2)
            let date = Calendar.current.date(byAdding: .day, value: -daysBefore, to: dueDate) ?? dueDate
            let task = AcademicTask(
                title: title,
                taskDescription: "Ouvre le Research Paper: \(project.title)\nResearchPaperID: \(projectNote.id.uuidString)",
                dueDate: date,
                priority: index >= titles.count - 2 ? .high : .medium,
                estimatedDuration: 3600,
                course: course,
                chapter: projectNote.chapter
            )
            modelContext.insert(task)
        }
        try? modelContext.save()
        message = "Jalons créés dans Planner."
    }

    private func requestAIReview(pass: String) {
        guard !feedbackInProgress else { return }
        feedbackInProgress = true
        let draftText = project.drafts.map { "\($0.title):\n\($0.body)" }.joined(separator: "\n\n")
        let sources = project.sources.compactMap { source -> AIRevisionSource? in
            let text = [source.personalSummary, source.quotations, source.paraphrases, source.limitations].filter { !$0.isEmpty }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return AIRevisionSource(id: source.id.uuidString, title: source.title, kind: .resource, detail: source.pages, text: text, sourceReference: source.title)
        }
        Task {
            do {
                let client = AIRevisionAssistantClient()
                guard case .ready = client.status() else { throw AIRevisionError.notConfigured }
                let answer = try await client.explain(
                    question: """
                    Passe de révision: \(pass).
                    Question: \(project.researchQuestion.text)
                    Thèse: \(project.thesis.text)
                    Brouillon:
                    \(draftText)

                    Donne des commentaires sans réécrire le devoir. Cite de courts passages réels du brouillon, distingue erreur vérifiée, objection possible et suggestion.
                    """,
                    courseName: project.courseName,
                    chapterTitle: project.chapterTitle ?? "Research Paper",
                    sources: sources
                )
                await MainActor.run {
                    project.reviewComments.append(ResearchReviewComment(pass: pass, excerpt: "Voir retour IA", comment: answer, sourceEvidence: sources.map(\.sourceReference).joined(separator: ", ")))
                    save()
                    feedbackInProgress = false
                }
            } catch {
                await MainActor.run {
                    project.reviewComments.append(ResearchReviewComment(pass: pass, excerpt: "", comment: "Retour IA indisponible: \(error.localizedDescription)", sourceEvidence: ""))
                    save()
                    feedbackInProgress = false
                }
            }
        }
    }

    private func save() {
        ResearchPaperStore.save(project, into: projectNote)
        try? modelContext.save()
    }
}

private struct ResearchSourceEditor: View {
    @Binding var source: ResearchSourceDraft
    let project: ResearchPaperProject

    var body: some View {
        CreationCard(source.title.isEmpty ? "Source sans titre" : source.title) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("État", selection: $source.status) {
                        ForEach(ResearchSourceStatus.allCases) { status in Text(status.title).tag(status) }
                    }
                    Text(source.missingBibliographyFields.isEmpty ? "Métadonnées minimales présentes" : "Manque: \(source.missingBibliographyFields.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(source.missingBibliographyFields.isEmpty ? Color.secondary : Color.orange)
                }
                TextField("Auteur", text: $source.author)
                    .textFieldStyle(.roundedBorder)
                TextField("Année", text: $source.year)
                    .textFieldStyle(.roundedBorder)
                TextField("Titre", text: $source.title)
                    .textFieldStyle(.roundedBorder)
                TextField("Revue / éditeur / site", text: $source.container)
                    .textFieldStyle(.roundedBorder)
                TextField("Type de source", text: $source.sourceType)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Pages", text: $source.pages)
                    TextField("DOI", text: $source.doi)
                    TextField("ISBN", text: $source.isbn)
                }
                .textFieldStyle(.roundedBorder)
                TextField("URL", text: $source.url)
                    .textFieldStyle(.roundedBorder)
                TextField("Pertinence pour le sujet", text: $source.relevance, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextField("Notes de crédibilité", text: $source.reliability, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextField("Résumé personnel", text: $source.personalSummary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextField("Citations courtes avec page exacte", text: $source.quotations, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextField("Paraphrases personnelles", text: $source.paraphrases, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextField("Tags", text: $source.tags)
                    .textFieldStyle(.roundedBorder)
                TextField("Limites / fiabilité", text: $source.limitations, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                duplicateWarning
            }
        }
    }

    @ViewBuilder
    private var duplicateWarning: some View {
        let normalized = source.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let duplicateCount = project.sources.filter { !$0.title.isEmpty && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }.count
        if duplicateCount > 1 {
            Label("Doublon probable: même titre dans ce projet.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

struct FutureCourseAreaView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        EmptyStateView(title: title, message: message, systemImage: systemImage)
            .padding()
            .background(StudyDeskTheme.backgroundPrimary)
    }
}
