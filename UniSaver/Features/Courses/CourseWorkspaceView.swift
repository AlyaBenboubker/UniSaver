import AppKit
import PDFKit
import SwiftData
import SwiftUI

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
        let english = language == .english
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
    @State private var selectedResearchPaper: StudyNote?
    @State private var addingExternalActivity = false
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private func uiText(_ french: String, _ english: String) -> String {
        appLanguage == .english ? english : french
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
        .sheet(item: $selectedResearchPaper) { note in
            ResearchPaperWorkspaceView(projectNote: note)
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
            Divider()
            Button(uiText("Nouvelle note", "New Note"), systemImage: "note.text") { quickAddTarget = .note(course, nil, nil, nil) }
            Button(uiText("Nouvel enregistrement", "New Recording"), systemImage: "waveform") { quickAddTarget = .recording(course, nil, nil) }
            Button(uiText("Nouveau quiz", "New Quiz"), systemImage: "questionmark.app") { quickAddTarget = .quiz(course, nil, nil) }
            Button(uiText("Importer des flashcards", "Import Flashcards"), systemImage: "text.badge.plus") { quickAddTarget = .bulkFlashcards(course, nil) }
            Button(uiText("Question ouverte", "Open Question"), systemImage: "text.book.closed") { creatingEssayAssignment = true }
            Button("Research Paper", systemImage: "doc.text.magnifyingglass") { creatingResearchPaper = true }
            Button(uiText("Ajouter une activité externe", "Add External Activity"), systemImage: "link.badge.plus") { addingExternalActivity = true }
            Divider()
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
    @State private var addingExternalActivity = false
    @State private var confirmDissociateSeries = false
    @State private var selectedExternalActivity: ExternalLearningActivity?
    @State private var selectedMathExercise: MathExercise?
    @State private var selectedEssayAssignment: EssayAssignment?
    @State private var selectedResearchPaper: StudyNote?
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
        notes.filter { $0.course?.id == course.id && !ResearchPaperStore.isResearchPaper($0) }.prefix(4).map(\.self)
    }

    private var researchPapers: [StudyNote] {
        notes.filter { $0.course?.id == course.id && ResearchPaperStore.isResearchPaper($0) }
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
                    compactLinkRow(title: task.title, subtitle: "\(uiText("Échéance", "Due")) \(UniDateFormatters.dayMonth.string(from: task.dueDate))", systemImage: "checklist")
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
        case uiText("Reprendre mon travail", "Resume Work"): recentChapter == nil && researchPapers.isEmpty && courseNotes.isEmpty
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
        panel.allowedFileTypes = ["pdf", "docx", "png", "jpg", "jpeg", "heic", "ics"]
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
        notes.filter { $0.course?.id == course.id }
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

private enum ResearchPaperStage: String, Codable, CaseIterable, Identifiable {
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

private enum ResearchPaperItemStatus: String, Codable, CaseIterable, Identifiable {
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

private enum ResearchSourceStatus: String, Codable, CaseIterable, Identifiable {
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

private struct ResearchPaperProject: Codable {
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

private struct ResearchPaperTrackedText: Codable, Identifiable {
    var id = UUID()
    var label: String
    var text: String = ""
    var status: ResearchPaperItemStatus = .idea
}

private struct ResearchTopicCandidate: Codable, Identifiable {
    var id = UUID()
    var title: String = ""
    var personalInterest: String = ""
    var feasibility: String = ""
    var sourceAvailability: String = ""
    var mainObjection: String = ""
    var decision: ResearchPaperItemStatus = .idea
}

private struct ResearchSourceDraft: Codable, Identifiable {
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

private struct ResearchArgumentDraft: Codable, Identifiable {
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

private struct ResearchOutlineSection: Codable, Identifiable {
    var id = UUID()
    var title: String = ""
    var objective: String = ""
    var targetWords: Int = 300
}

private struct ResearchFigureDraft: Codable, Identifiable {
    var id = UUID()
    var title: String = ""
    var source: String = ""
    var license: String = ""
    var caption: String = ""
    var plannedLocation: String = ""
}

private struct ResearchDraftSection: Codable, Identifiable {
    var id = UUID()
    var sectionID: UUID?
    var title: String = ""
    var body: String = ""
    var linkedSourceIDs: [UUID] = []
    var updatedAt: Date = .now
}

private struct ResearchReviewComment: Codable, Identifiable {
    var id = UUID()
    var pass: String = "Fond"
    var excerpt: String = ""
    var comment: String = ""
    var sourceEvidence: String = ""
    var status: String = "À traiter"
}

private enum ResearchPaperStore {
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

private func researchWordCount(_ text: String) -> Int {
    text.split { $0.isWhitespace || $0.isNewline }.count
}

private struct ResearchPaperCompactRow: View {
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

private struct ResearchPaperCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: Course
    let chapters: [Chapter]
    let onCreate: (StudyNote) -> Void
    @State private var title = ""
    @State private var selectedChapterID: UUID?
    @State private var prompt = ""
    @State private var hasDueDate = true
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 21, to: .now) ?? .now
    @State private var expectedLength = ""
    @State private var citationStyle = "APA"
    @State private var criteria = ""
    @State private var researchQuestion = ""
    @State private var thesis = ""
    @State private var error: String?

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
        var project = ResearchPaperProject(title: cleanTitle, courseName: course.name, chapterTitle: selectedChapter?.title)
        project.prompt = prompt
        project.dueDate = hasDueDate ? dueDate : nil
        project.expectedLength = expectedLength
        project.citationStyle = citationStyle
        project.criteria = criteria
        project.researchQuestion.text = researchQuestion
        project.thesis.text = thesis
        project.outline = [
            ResearchOutlineSection(title: "Introduction", objective: "Présenter la question, le contexte et la thèse.", targetWords: 300),
            ResearchOutlineSection(title: "Développement", objective: "Déployer les arguments soutenus par les sources.", targetWords: 900),
            ResearchOutlineSection(title: "Conclusion", objective: "Répondre à la question et préciser les limites.", targetWords: 250)
        ]
        project.drafts = project.outline.map { ResearchDraftSection(sectionID: $0.id, title: $0.title) }
        let note = StudyNote(title: cleanTitle, course: course, chapter: selectedChapter)
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

private enum ResearchPaperWorkspaceTab: String, CaseIterable, Identifiable {
    case project = "Projet"
    case sources = "Sources"
    case arguments = "Arguments et plan"
    case drafting = "Rédaction"
    case revision = "Révision"

    var id: String { rawValue }
}

private struct ResearchPaperWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var projectNote: StudyNote
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @State private var project: ResearchPaperProject
    @State private var tab: ResearchPaperWorkspaceTab = .project
    @State private var selectedDraftID: UUID?
    @State private var blockedPasteMessage: String?
    @State private var message: String?
    @State private var showingMilestonePreview = false
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
                Button("Nouvelle source manuelle", systemImage: "plus") {
                    project.sources.append(ResearchSourceDraft())
                    save()
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
                        Stepper("Cible \(section.targetWords) mots", value: $section.targetWords, in: 50...3000, step: 50)
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
                        requestAIReview(pass: "Fond")
                    }
                    .disabled(feedbackInProgress)
                    Button(feedbackInProgress ? "Analyse..." : "Réviser la forme avec l’IA", systemImage: "text.magnifyingglass") {
                        requestAIReview(pass: "Forme")
                    }
                    .disabled(feedbackInProgress)
                }
                .buttonStyle(.borderedProminent)
                Text("Sans fournisseur IA, les contrôles déterministes restent disponibles : plan, arguments sans source, références incomplètes, sections vides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        return count == 0 ? "Aucun argument explicitement lié à cette section." : "\(count) argument(s) lié(s)."
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
            let daysBefore = max(1, (titles.count - index) * 2)
            let date = Calendar.current.date(byAdding: .day, value: -daysBefore, to: dueDate) ?? dueDate
            let task = AcademicTask(
                title: title,
                taskDescription: "Ouvre le Research Paper: \(project.title)",
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
                HStack {
                    TextField("Pages", text: $source.pages)
                    TextField("DOI", text: $source.doi)
                    TextField("ISBN", text: $source.isbn)
                }
                .textFieldStyle(.roundedBorder)
                TextField("URL", text: $source.url)
                    .textFieldStyle(.roundedBorder)
                TextField("Résumé personnel", text: $source.personalSummary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextField("Citations courtes avec page exacte", text: $source.quotations, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextField("Paraphrases personnelles", text: $source.paraphrases, axis: .vertical)
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
