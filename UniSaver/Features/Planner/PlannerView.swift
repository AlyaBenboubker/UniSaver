import AppKit
import EventKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum PlannerTaskFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case open
    case priority
    case dueToday
    case upcoming
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .open: "Open"
        case .priority: "Priority"
        case .dueToday: "Due Today"
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        }
    }
}

enum PlannerTaskSort: String, CaseIterable, Identifiable {
    case dueDate
    case priority
    case course

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueDate: "Due Date"
        case .priority: "Priority"
        case .course: "Course"
        }
    }
}

enum PlannerTaskQuery {
    static func filteredTasks(_ tasks: [AcademicTask], filter: PlannerTaskFilter, searchText: String, courseID: UUID?) -> [AcademicTask] {
        let calendar = Calendar.current
        return tasks.filter { task in
            let matchesSearch = searchText.isEmpty
                || task.title.localizedCaseInsensitiveContains(searchText)
                || task.taskDescription.localizedCaseInsensitiveContains(searchText)
                || task.course?.name.localizedCaseInsensitiveContains(searchText) == true
            let matchesCourse = courseID == nil || task.course?.id == courseID
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .open:
                matchesFilter = task.status != .completed && task.status != .cancelled
            case .priority:
                matchesFilter = task.status != .completed && (task.priority == .urgent || task.priority == .high)
            case .dueToday:
                matchesFilter = calendar.isDateInToday(task.dueDate)
            case .upcoming:
                matchesFilter = task.dueDate != .distantFuture && task.dueDate > Date() && task.status != .completed
            case .completed:
                matchesFilter = task.status == .completed
            }
            return matchesSearch && matchesCourse && matchesFilter
        }
    }

    static func sortedTasks(_ tasks: [AcademicTask], sort: PlannerTaskSort) -> [AcademicTask] {
        switch sort {
        case .dueDate:
            tasks.sorted { $0.dueDate < $1.dueDate }
        case .priority:
            tasks.sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.dueDate < $1.dueDate
            }
        case .course:
            tasks.sorted { ($0.course?.name ?? "") < ($1.course?.name ?? "") }
        }
    }
}

private enum PlannerCalendarMode: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private enum PlannerSheet: Identifiable {
    case newTask(Date)
    case newStudyBlock(Date)
    case editTask(AcademicTask)
    case newSession(Course, Date)
    case editSession(ClassSession)
    case importCalendar
    case organizeImportedSessions
    case correctImportedTimeZones
    case associateSession(ClassSession)
    case associateAppleEvent(ApplePlannerCalendarEvent)

    var id: String {
        switch self {
        case .newTask(let date): "newTask-\(date.timeIntervalSinceReferenceDate)"
        case .newStudyBlock(let date): "newStudyBlock-\(date.timeIntervalSinceReferenceDate)"
        case .editTask(let task): "editTask-\(task.id)"
        case .newSession(let course, let date): "newSession-\(course.id)-\(date.timeIntervalSinceReferenceDate)"
        case .editSession(let session): "editSession-\(session.id)"
        case .importCalendar: "importCalendar"
        case .organizeImportedSessions: "organizeImportedSessions"
        case .correctImportedTimeZones: "correctImportedTimeZones"
        case .associateSession(let session): "associateSession-\(session.id)"
        case .associateAppleEvent(let event): "associateAppleEvent-\(event.id)"
        }
    }
}

private enum PlannerEvent: Identifiable {
    case session(ClassSession)
    case task(AcademicTask)
    case studyBlock(StudyBlock)
    case flashcard(Flashcard)
    case appleCalendar(ApplePlannerCalendarEvent)
    case appleReminder(ApplePlannerReminder)

    var id: String {
        switch self {
        case .session(let session): "session-\(session.id)"
        case .task(let task): "task-\(task.id)"
        case .studyBlock(let block): "study-\(block.id)"
        case .flashcard(let card): "flashcard-\(card.id)"
        case .appleCalendar(let event): "apple-calendar-\(event.id)"
        case .appleReminder(let reminder): "apple-reminder-\(reminder.id)"
        }
    }

    var startDate: Date {
        switch self {
        case .session(let session): session.startTime
        case .task(let task): task.dueDate
        case .studyBlock(let block): block.startDate
        case .flashcard(let card): card.reviewState.dueDate
        case .appleCalendar(let event): event.startDate
        case .appleReminder(let reminder): reminder.dueDate
        }
    }

    var title: String {
        switch self {
        case .session(let session): session.title
        case .task(let task): task.title
        case .studyBlock(let block): block.title
        case .flashcard(let card): card.front
        case .appleCalendar(let event): event.title
        case .appleReminder(let reminder): reminder.title
        }
    }

    var subtitle: String {
        switch self {
        case .session(let session):
            return [session.course?.name ?? "Cours", timeRange(session.startTime, session.endTime), session.room].compactMap { $0 }.joined(separator: " · ")
        case .task(let task):
            return [task.course?.name, "Échéance \(task.priority.title)"].compactMap { $0 }.joined(separator: " · ")
        case .studyBlock(let block):
            return [block.course?.name, timeRange(block.startDate, block.endDate)].compactMap { $0 }.joined(separator: " · ")
        case .flashcard(let card):
            return card.deck?.title ?? "Révision due"
        case .appleCalendar(let event):
            return [event.calendarTitle, timeRange(event.startDate, event.endDate), event.location].compactMap { $0 }.joined(separator: " · ")
        case .appleReminder(let reminder):
            return [reminder.listTitle, "Apple Reminders"].joined(separator: " · ")
        }
    }

    var symbolName: String {
        switch self {
        case .session: "person.2"
        case .task: "checklist"
        case .studyBlock: "timer"
        case .flashcard: "rectangle.stack"
        case .appleCalendar: "calendar"
        case .appleReminder: "list.bullet.rectangle"
        }
    }

    var sourceLabel: String {
        switch self {
        case .session, .task, .studyBlock, .flashcard:
            return "UniSaver"
        case .appleCalendar:
            return "Apple Calendar"
        case .appleReminder:
            return "Apple Reminders"
        }
    }

    var isAllDay: Bool {
        switch self {
        case .appleCalendar(let event):
            return event.isAllDay
        default:
            return false
        }
    }

    var sourceTimeZoneLabel: String {
        switch self {
        case .session(let session):
            return sourceTimeZone(from: session.sessionDescription) ?? TimeZone.current.identifier
        case .appleCalendar(let event):
            return event.timeZoneIdentifier ?? TimeZone.current.identifier
        default:
            return TimeZone.current.identifier
        }
    }

    private func sourceTimeZone(from text: String) -> String? {
        text.components(separatedBy: .newlines)
            .first { $0.hasPrefix("Source timezone:") }
            .map { $0.replacingOccurrences(of: "Source timezone:", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        "\(UniDateFormatters.time.string(from: start))-\(UniDateFormatters.time.string(from: end))"
    }

    var endDate: Date {
        switch self {
        case .session(let session): session.endTime
        case .task(let task): task.dueDate.addingTimeInterval(1800)
        case .studyBlock(let block): block.endDate
        case .flashcard(let card): card.reviewState.dueDate.addingTimeInterval(1800)
        case .appleCalendar(let event): event.endDate
        case .appleReminder(let reminder): reminder.dueDate.addingTimeInterval(1800)
        }
    }

    var courseColorIdentifier: String {
        switch self {
        case .session(let session): session.course?.colorIdentifier ?? "blueViolet"
        case .task(let task): task.course?.colorIdentifier ?? "mint"
        case .studyBlock(let block): block.course?.colorIdentifier ?? "gold"
        case .flashcard(let card): card.deck?.course?.colorIdentifier ?? "rose"
        case .appleCalendar: "sky"
        case .appleReminder: "indigo"
        }
    }
}

struct ApplePlannerCalendarEvent: Identifiable, Hashable {
    let id: String
    let stableID: String?
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let calendarIdentifier: String
    let location: String?
    let notes: String?
    let url: URL?
    let isAllDay: Bool
    let isRecurring: Bool
    let timeZoneIdentifier: String?
}

struct ApplePlannerReminder: Identifiable, Hashable {
    let id: String
    let title: String
    let dueDate: Date
    let listTitle: String
    let isCompleted: Bool
}

private struct AssociatedContentGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}

private func courseTitle(_ course: Course) -> String {
    course.code.isEmpty ? course.name : "\(course.code) · \(course.name)"
}

struct PlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \ClassSession.startTime) private var sessions: [ClassSession]
    @Query(sort: \StudyBlock.startDate) private var studyBlocks: [StudyBlock]
    @Query(sort: \Flashcard.updatedAt, order: .reverse) private var flashcards: [Flashcard]
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]
    @Query(sort: \Quiz.updatedAt, order: .reverse) private var quizzes: [Quiz]
    @Query(sort: \StudyDeck.updatedAt, order: .reverse) private var decks: [StudyDeck]
    @Query(sort: \ExternalCalendarEventLink.updatedAt, order: .reverse) private var externalEventLinks: [ExternalCalendarEventLink]

    @State private var filter: PlannerTaskFilter = .open
    @State private var searchText = ""
    @State private var selectedCourseID: UUID?
    @State private var mode: PlannerCalendarMode = .week
    @State private var selectedDate = Date()
    @State private var visibleDate = Date()
    @State private var activeSheet: PlannerSheet?
    @State private var deletingTask: AcademicTask?
    @State private var deletingSession: ClassSession?
    @State private var selectedEvent: PlannerEvent?
    @State private var quickAddTarget: QuickAddTarget?
    @State private var courseForNewSessionID: UUID?
    @State private var bannerMessage: String?
    @State private var isDayPanelCollapsed = false
    @State private var appleCalendarEvents: [ApplePlannerCalendarEvent] = []
    @State private var appleReminders: [ApplePlannerReminder] = []
    @State private var appleLoadMessage: String?
    @AppStorage("appleCalendarSelectedIDs") private var selectedAppleCalendarIDs = ""
    @AppStorage("appleReminderSelectedIDs") private var selectedAppleReminderListIDs = ""
    @AppStorage("hiddenAppleCalendarEventIDs") private var hiddenAppleCalendarEventIDs = ""
    @AppStorage("appleCalendarSeriesRules") private var appleCalendarSeriesRulesData = ""

    init(initialFilter: PlannerTaskFilter = .open) {
        _filter = State(initialValue: initialFilter)
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    private var dayEvents: [PlannerEvent] {
        events(on: selectedDate)
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 820
            VStack(spacing: 0) {
                plannerHeader
                Divider()
                if compact {
                    ScrollView {
                        VStack(spacing: 14) {
                            calendarSurface
                            selectedDayPanel
                        }
                        .padding()
                    }
                } else {
                    HStack(spacing: 0) {
                        calendarSurface
                            .frame(minWidth: 420)
                        Divider()
                        if !isDayPanelCollapsed {
                            Divider()
                            selectedDayPanel
                                .frame(width: 360)
                        }
                    }
                }
            }
            .background(StudyDeskTheme.backgroundPrimary)
        }
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItem {
                Button {
                    isDayPanelCollapsed.toggle()
                } label: {
                    Image(systemName: isDayPanelCollapsed ? "sidebar.right" : "sidebar.trailing")
                }
                .help(isDayPanelCollapsed ? "Afficher la journée" : "Replier la journée")
            }
            ToolbarItem {
                Menu("Ajouter / Importer", systemImage: "plus") {
                    Button("Nouvelle tâche", systemImage: "checklist") {
                        activeSheet = .newTask(selectedDate)
                    }
                    Button("Planifier une révision", systemImage: "timer") {
                        activeSheet = .newStudyBlock(selectedDate)
                    }
                    if let course = selectedCourse ?? courses.first {
                        Button("Nouvelle séance", systemImage: "person.2.badge.plus") {
                            activeSheet = .newSession(course, selectedDate)
                        }
                    }
                    Divider()
                    Button("Importer un calendrier .ics", systemImage: "calendar.badge.plus") {
                        activeSheet = .importCalendar
                    }
                    Button("Organiser les événements importés", systemImage: "wand.and.stars") {
                        activeSheet = .organizeImportedSessions
                    }
                    Button("Corriger le fuseau d’un import", systemImage: "clock.badge.exclamationmark") {
                        activeSheet = .correctImportedTimeZones
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newTask(let date):
                TaskFormView(initialCourse: selectedCourse, initialDueDate: defaultTaskDate(on: date))
            case .newStudyBlock(let date):
                StudyBlockFormView(initialCourse: selectedCourse, initialDate: date)
            case .editTask(let task):
                TaskFormView(task: task)
            case .newSession(let course, let date):
                SessionFormView(course: course, initialDate: date)
            case .editSession(let session):
                if let course = session.course {
                    SessionFormView(course: course, session: session)
                } else {
                    TaskFormView(initialDueDate: session.startTime)
                }
            case .importCalendar:
                CalendarImportSheet(courses: courses, existingSessions: sessions)
            case .organizeImportedSessions:
                CalendarOrganizationSheet(
                    title: "Organiser les événements importés",
                    source: .existingSessions(sessions.filter { $0.course == nil }),
                    courses: courses,
                    existingSessions: sessions
                )
            case .correctImportedTimeZones:
                CalendarTimeZoneCorrectionSheet(candidateSessions: sessions)
            case .associateSession(let session):
                SessionAssociationSheet(session: session, courses: courses)
            case .associateAppleEvent(let event):
                AppleCalendarEventAssociationSheet(
                    event: event,
                    existingLink: externalLink(for: .appleCalendar(event)),
                    allAppleEvents: appleCalendarEvents,
                    existingLinks: externalEventLinks,
                    courses: courses,
                    sessions: sessions,
                    seriesRulesData: $appleCalendarSeriesRulesData
                )
            }
        }
        .sheet(item: $selectedEvent) { event in
            PlannerEventDetailView(
                event: event,
                resources: resources,
                notes: notes,
                tasks: tasks,
                recordings: recordings,
                quizzes: quizzes,
                decks: decks,
                externalLink: externalLink(for: event),
                openCourse: { course, tab in
                    selectedEvent = nil
                    navigation.openCourse(course, tab: tab)
                },
                editSession: { session in
                    selectedEvent = nil
                    activeSheet = .editSession(session)
                },
                associateSession: { session in
                    selectedEvent = nil
                    activeSheet = .associateSession(session)
                },
                addNote: { session in
                    selectedEvent = nil
                    quickAddTarget = .note(session.course, session.chapter, session, nil)
                },
                addDocument: { session in
                    selectedEvent = nil
                    quickAddTarget = .resource(session.course, session.chapter, session)
                },
                deleteSession: { session in
                    selectedEvent = nil
                    deletingSession = session
                },
                editTask: { task in
                    selectedEvent = nil
                    activeSheet = .editTask(task)
                },
                hideAppleCalendar: { event in
                    hideAppleCalendar(event.calendarIdentifier)
                },
                hideAppleEvent: { event in
                    hideAppleEvent(event.id)
                },
                openAppleEvent: openAppleCalendarEvent,
                associateAppleEvent: { appleEvent in
                    selectedEvent = nil
                    activeSheet = .associateAppleEvent(appleEvent)
                },
                addAppleNote: { appleEvent in
                    guard let target = externalLink(for: .appleCalendar(appleEvent)) else {
                        bannerMessage = "Associe d’abord cet événement à un cours ou une séance."
                        return
                    }
                    selectedEvent = nil
                    quickAddTarget = .note(target.course, target.chapter, target.session, nil)
                },
                addAppleDocument: { appleEvent in
                    guard let target = externalLink(for: .appleCalendar(appleEvent)) else {
                        bannerMessage = "Associe d’abord cet événement à un cours ou une séance."
                        return
                    }
                    selectedEvent = nil
                    quickAddTarget = .resource(target.course, target.chapter, target.session)
                },
                openStudy: {
                    selectedEvent = nil
                    navigation.requestSelect(.study)
                }
            )
        }
        .sheet(item: $quickAddTarget) { target in
            QuickAddSheet(target: target)
        }
        .confirmationDialog("Delete task?", isPresented: Binding(
            get: { deletingTask != nil },
            set: { if !$0 { deletingTask = nil } }
        )) {
            Button("Delete Task", role: .destructive) {
                if let deletingTask {
                    modelContext.delete(deletingTask)
                    try? modelContext.save()
                    self.deletingTask = nil
                }
            }
            Button("Cancel", role: .cancel) { deletingTask = nil }
        }
        .confirmationDialog("Supprimer cette séance ?", isPresented: Binding(
            get: { deletingSession != nil },
            set: { if !$0 { deletingSession = nil } }
        )) {
            Button("Supprimer la séance uniquement", role: .destructive) {
                if let deletingSession {
                    deleteSessionPreservingLinkedContent(deletingSession)
                }
                deletingSession = nil
            }
            Button("Annuler", role: .cancel) { deletingSession = nil }
        } message: {
            Text("UniSaver ne stocke pas une série récurrente unique pour cette donnée. Les notes, documents, tâches et enregistrements liés seront conservés et simplement détachés de cette séance.")
        }
        .overlay(alignment: .bottom) {
            if let bannerMessage {
                Text(bannerMessage)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        self.bannerMessage = nil
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPlannerTasks)) { notification in
            if let incoming = notification.object as? PlannerTaskFilter {
                filter = incoming
            }
        }
        .task {
            loadExternalPlannerItems()
        }
        .onChange(of: selectedDate) { _, _ in
            loadExternalPlannerItems()
        }
        .onChange(of: visibleDate) { _, _ in
            loadExternalPlannerItems()
        }
        .onChange(of: selectedAppleCalendarIDs) { _, _ in
            loadExternalPlannerItems()
        }
        .onChange(of: selectedAppleReminderListIDs) { _, _ in
            loadExternalPlannerItems()
        }
    }

    private var plannerHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text(calendarTitle)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Spacer()
                Button("Aujourd'hui") {
                    selectedDate = Date()
                    visibleDate = Date()
                }
                Button {
                    stepVisibleDate(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                Button {
                    stepVisibleDate(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                Picker("Mode", selection: $mode) {
                    ForEach(PlannerCalendarMode.allCases) { mode in
                        Text(mode.title == "Week" ? "Semaine" : "Mois").tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Rechercher", text: $searchText)
                    .textFieldStyle(.plain)
                Picker("Cours", selection: $selectedCourseID) {
                    Text("Tous les cours").tag(UUID?.none)
                    ForEach(courses.filter { !$0.isArchived }) { course in
                        Text(course.name).tag(Optional(course.id))
                    }
                }
                Button("Organiser les événements importés", systemImage: "wand.and.stars") {
                    activeSheet = .organizeImportedSessions
                }
                .disabled(sessions.allSatisfy { $0.course != nil })
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
            }
        }
        .padding()
    }

    private var calendarSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .week {
                PlannerWeekGrid(days: daysForCurrentWeek, events: events(in: TodayDashboardService.weekInterval(containing: visibleDate)), selectedDate: $selectedDate, open: open)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(shortWeekdays, id: \.self) { label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(daysForCurrentMonth, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private var selectedDayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedDate.formatted(date: .complete, time: .omitted))
                        .font(.headline)
                    Text("\(dayEvents.count) élément\(dayEvents.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    activeSheet = .newTask(selectedDate)
                } label: {
                    Image(systemName: "plus")
                }
            }

            if dayEvents.isEmpty {
                VStack(spacing: 10) {
                    EmptyStateView(title: "Rien ce jour", message: "Ajoute une tâche, une séance ou importe un calendrier.", systemImage: "calendar")
                    if let appleLoadMessage {
                        Text(appleLoadMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                List {
                    ForEach(dayEvents) { event in
                        Button {
                            open(event)
                        } label: {
                            PlannerEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            contextMenu(for: event)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func contextMenu(for event: PlannerEvent) -> some View {
        switch event {
        case .task(let task):
            Button(task.status == .completed ? "Reopen" : "Complete") {
                task.status = task.status == .completed ? .todo : .completed
                task.updatedAt = .now
                try? modelContext.save()
            }
            Button("Edit") { activeSheet = .editTask(task) }
            Button("Delete", role: .destructive) { deletingTask = task }
        case .session(let session):
            Button("Edit") { activeSheet = .editSession(session) }
            Button("Associer au cours / chapitre") { activeSheet = .associateSession(session) }
            Button("Ajouter une note") { quickAddTarget = .note(session.course, session.chapter, session, nil) }
            Button("Ajouter un document") { quickAddTarget = .resource(session.course, session.chapter, session) }
            Button("Supprimer", role: .destructive) { deletingSession = session }
        case .studyBlock, .flashcard:
            if case .studyBlock(let block) = event {
                Button(block.status == .completed ? "Replanifier" : "Terminer") {
                    block.status = block.status == .completed ? .planned : .completed
                    block.updatedAt = .now
                    try? modelContext.save()
                }
                Button("Ignorer") {
                    block.status = .cancelled
                    block.updatedAt = .now
                    try? modelContext.save()
                }
            }
            Button("Open Study") { navigation.requestSelect(.study) }
        case .appleCalendar(let event):
            Button("Ouvrir dans Calendrier") { openAppleCalendarEvent(event) }
            Button("Associer à un cours") { activeSheet = .associateAppleEvent(event) }
            Button("Masquer ce calendrier") { hideAppleCalendar(event.calendarIdentifier) }
            Button("Masquer cet événement") { hideAppleEvent(event.id) }
        case .appleReminder:
            Button("Source externe en lecture seule") {}
                .disabled(true)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let events = events(on: day)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDateInToday(day)
        return Button {
            selectedDate = day
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(day.formatted(.dateTime.day()))
                        .font(.headline)
                    Spacer()
                    if isToday {
                        Circle()
                            .fill(StudyDeskTheme.accentPrimary)
                            .frame(width: 7, height: 7)
                    }
                }
                Text(shortWeekday(day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(events.prefix(4)) { event in
                        Image(systemName: event.symbolName)
                            .font(.caption2)
                    }
                    if events.count > 4 {
                        Text("+\(events.count - 4)")
                            .font(.caption2.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: mode == .week ? 116 : 82, alignment: .topLeading)
            .padding(10)
            .background(isSelected ? StudyDeskTheme.surfaceTinted : StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? StudyDeskTheme.accentPrimary : StudyDeskTheme.borderSubtle, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var calendarTitle: String {
        if mode == .week {
            let interval = TodayDashboardService.weekInterval(containing: visibleDate)
            return "\(UniDateFormatters.dayMonth.string(from: interval.start)) - \(UniDateFormatters.dayMonth.string(from: interval.end.addingTimeInterval(-1)))"
        }
        return visibleDate.formatted(.dateTime.month(.wide).year())
    }

    private var daysForCurrentWeek: [Date] {
        let interval = TodayDashboardService.weekInterval(containing: visibleDate)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var daysForCurrentMonth: [Date] {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: visibleDate),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: month.end.addingTimeInterval(-1)) else {
            return []
        }
        var days: [Date] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            days.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }
        return days
    }

    private var shortWeekdays: [String] {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }

    private func shortWeekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func events(on date: Date) -> [PlannerEvent] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return [] }
        return events(in: interval)
    }

    private func events(in interval: DateInterval) -> [PlannerEvent] {
        let courseMatches: (Course?) -> Bool = { course in
            selectedCourseID == nil || course?.id == selectedCourseID
        }
        let all: [PlannerEvent] =
            sessions.filter { interval.contains($0.startTime) && courseMatches($0.course) }.map(PlannerEvent.session)
            + tasks.filter { interval.contains($0.dueDate) && courseMatches($0.course) && matchesTaskFilter($0) }.map(PlannerEvent.task)
            + studyBlocks.filter { interval.intersects(DateInterval(start: $0.startDate, end: $0.endDate)) && courseMatches($0.course) }.map(PlannerEvent.studyBlock)
            + flashcards.filter { interval.contains($0.reviewState.dueDate) && courseMatches($0.deck?.course) }.map(PlannerEvent.flashcard)
            + appleCalendarEvents.filter {
                interval.intersects(DateInterval(start: $0.startDate, end: $0.endDate)) &&
                !isAppleEventRepresentedByLinkedSession($0, in: interval)
            }.map(PlannerEvent.appleCalendar)
            + appleReminders.filter { interval.contains($0.dueDate) && !$0.isCompleted }.map(PlannerEvent.appleReminder)
        return all
            .filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) || $0.subtitle.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func matchesTaskFilter(_ task: AcademicTask) -> Bool {
        PlannerTaskQuery.filteredTasks([task], filter: filter, searchText: "", courseID: nil).isEmpty == false
    }

    private func stepVisibleDate(_ value: Int) {
        let component: Calendar.Component = mode == .week ? .weekOfYear : .month
        visibleDate = Calendar.current.date(byAdding: component, value: value, to: visibleDate) ?? visibleDate
        selectedDate = visibleDate
    }

    private func defaultTaskDate(on date: Date) -> Date {
        Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: date) ?? date
    }

    private func open(_ event: PlannerEvent) {
        selectedEvent = event
    }

    private func externalLink(for event: PlannerEvent) -> ExternalCalendarEventLink? {
        guard case .appleCalendar(let appleEvent) = event else { return nil }
        if let direct = externalEventLinks.first(where: { $0.externalEventIdentifier == appleEvent.id }) {
            return direct
        }
        if let stableID = appleEvent.stableID {
            let stableMatches = externalEventLinks.filter { $0.externalStableIdentifier == stableID }
            if let sameOccurrence = stableMatches.first(where: { Calendar.current.isDate($0.occurrenceStartDate, inSameDayAs: appleEvent.startDate) }) {
                return sameOccurrence
            }
            if stableMatches.count == 1 {
                return stableMatches.first
            }
        }
        return nil
    }

    private func isAppleEventRepresentedByLinkedSession(_ event: ApplePlannerCalendarEvent, in interval: DateInterval) -> Bool {
        guard let link = externalLink(for: .appleCalendar(event)),
              let session = link.session else {
            return false
        }
        return interval.contains(session.startTime)
    }

    private func loadExternalPlannerItems() {
        let calendarIDs = Set(selectedAppleCalendarIDs.split(separator: ",").map(String.init))
        let reminderIDs = Set(selectedAppleReminderListIDs.split(separator: ",").map(String.init))
        let store = EKEventStore()
        let interval = visibleIntervalForExternalData()
        appleLoadMessage = nil

        if readableEventAccess, !calendarIDs.isEmpty {
            let hiddenEvents = Set(hiddenAppleCalendarEventIDs.split(separator: ",").map(String.init))
            let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
            let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
            appleCalendarEvents = store.events(matching: predicate).filter {
                !hiddenEvents.contains($0.eventIdentifier)
            }.map {
                ApplePlannerCalendarEvent(
                    id: $0.eventIdentifier,
                    stableID: $0.calendarItemExternalIdentifier,
                    title: $0.title ?? "Apple event",
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    calendarTitle: $0.calendar.title,
                    calendarIdentifier: $0.calendar.calendarIdentifier,
                    location: $0.location,
                    notes: $0.notes,
                    url: $0.url,
                    isAllDay: $0.isAllDay,
                    isRecurring: $0.hasRecurrenceRules,
                    timeZoneIdentifier: $0.timeZone?.identifier
                )
            }
            applyStoredAppleCalendarSeriesRules()
            autoAssociateReliableAppleEvents()
        } else {
            appleCalendarEvents = []
            if !calendarIDs.isEmpty {
                appleLoadMessage = "Accès Calendar révoqué ou indisponible."
            }
        }

        if readableReminderAccess, !reminderIDs.isEmpty {
            let lists = store.calendars(for: .reminder).filter { reminderIDs.contains($0.calendarIdentifier) }
            let predicate = store.predicateForReminders(in: lists)
            store.fetchReminders(matching: predicate) { reminders in
                let mapped = (reminders ?? []).compactMap { reminder -> ApplePlannerReminder? in
                    guard let dueDate = reminder.dueDateComponents?.date else { return nil }
                    guard interval.contains(dueDate) else { return nil }
                    return ApplePlannerReminder(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Apple reminder",
                        dueDate: dueDate,
                        listTitle: reminder.calendar.title,
                        isCompleted: reminder.isCompleted
                    )
                }
                Task { @MainActor in
                    self.appleReminders = mapped.sorted { $0.dueDate < $1.dueDate }
                }
            }
        } else {
            appleReminders = []
            if !reminderIDs.isEmpty {
                appleLoadMessage = [appleLoadMessage, "Accès Reminders révoqué ou indisponible."].compactMap { $0 }.joined(separator: " ")
            }
        }
    }

    private func autoAssociateReliableAppleEvents() {
        var didCreateLink = false
        for event in appleCalendarEvents {
            guard externalLink(for: .appleCalendar(event)) == nil else { continue }
            let suggestions = AppleCalendarAssociationSuggester.suggestions(for: event, courses: courses, sessions: sessions)
            guard let best = suggestions.first, best.isReliableAutomaticMatch else { continue }
            if suggestions.dropFirst().contains(where: { best.score - $0.score < 25 }) {
                continue
            }
            let link = ExternalCalendarEventLink(
                externalEventIdentifier: event.id,
                externalStableIdentifier: event.stableID,
                externalCalendarIdentifier: event.calendarIdentifier,
                occurrenceStartDate: event.startDate,
                titleSnapshot: event.title,
                calendarTitleSnapshot: event.calendarTitle,
                sourceURLString: event.url?.absoluteString,
                course: best.course,
                chapter: best.session?.chapter,
                session: best.session
            )
            modelContext.insert(link)
            didCreateLink = true
        }
        if didCreateLink {
            do {
                try modelContext.save()
                bannerMessage = "Événements Apple associés automatiquement aux matières fiables."
            } catch {
                bannerMessage = "Associations Apple non enregistrées : \(error.localizedDescription)"
            }
        }
    }

    private func applyStoredAppleCalendarSeriesRules() {
        let rules = AppleCalendarSeriesRuleStore.decode(appleCalendarSeriesRulesData)
        guard !rules.isEmpty else { return }
        var didChange = false
        for event in appleCalendarEvents {
            guard externalLink(for: .appleCalendar(event)) == nil,
                  let rule = rules.first(where: { $0.matches(event) }),
                  let courseID = UUID(uuidString: rule.courseID),
                  let course = courses.first(where: { $0.id == courseID }) else {
                continue
            }
            let session = AppleCalendarSeriesMatcher.matchingSession(for: event, course: course, sessions: sessions)
                ?? (rule.createsMissingSessions ? createSession(from: event, course: course) : nil)
            let link = ExternalCalendarEventLink(
                externalEventIdentifier: event.id,
                externalStableIdentifier: event.stableID,
                externalCalendarIdentifier: event.calendarIdentifier,
                occurrenceStartDate: event.startDate,
                titleSnapshot: event.title,
                calendarTitleSnapshot: event.calendarTitle,
                sourceURLString: event.url?.absoluteString,
                course: course,
                chapter: session?.chapter,
                session: session
            )
            modelContext.insert(link)
            didChange = true
        }
        if didChange {
            try? modelContext.save()
        }
    }

    private func createSession(from event: ApplePlannerCalendarEvent, course: Course) -> ClassSession {
        let session = ClassSession(
            number: (course.sessions.map(\.number).max() ?? 0) + 1,
            title: event.title,
            sessionDescription: "Source : Apple Calendar · \(event.calendarTitle)",
            date: Calendar.current.startOfDay(for: event.startDate),
            startTime: event.startDate,
            endTime: max(event.endDate, event.startDate.addingTimeInterval(900)),
            room: event.location,
            course: course
        )
        modelContext.insert(session)
        return session
    }

    private func hideAppleCalendar(_ calendarIdentifier: String) {
        var ids = Set(selectedAppleCalendarIDs.split(separator: ",").map(String.init))
        ids.remove(calendarIdentifier)
        selectedAppleCalendarIDs = ids.sorted().joined(separator: ",")
        appleCalendarEvents.removeAll { $0.calendarIdentifier == calendarIdentifier }
        bannerMessage = "Calendrier Apple masqué dans Planner. Les données Apple ne sont pas modifiées."
    }

    private func hideAppleEvent(_ eventIdentifier: String) {
        var ids = Set(hiddenAppleCalendarEventIDs.split(separator: ",").map(String.init))
        ids.insert(eventIdentifier)
        hiddenAppleCalendarEventIDs = ids.sorted().joined(separator: ",")
        appleCalendarEvents.removeAll { $0.id == eventIdentifier }
        bannerMessage = "Événement masqué dans UniSaver. Il reste inchangé dans Apple Calendar."
    }

    private func openAppleCalendarEvent(_ event: ApplePlannerCalendarEvent) {
        if let url = event.url {
            NSWorkspace.shared.open(url)
            return
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    Task { @MainActor in bannerMessage = error.localizedDescription }
                }
            }
        } else {
            bannerMessage = "Calendrier Apple est introuvable sur ce Mac."
        }
    }

    private func deleteSessionPreservingLinkedContent(_ session: ClassSession) {
        for resource in resources where resource.session?.id == session.id {
            resource.session = nil
            resource.updatedAt = .now
        }
        for note in notes where note.session?.id == session.id {
            note.session = nil
            note.updatedAt = .now
        }
        for task in tasks where task.session?.id == session.id {
            task.session = nil
            task.updatedAt = .now
        }
        for recording in recordings where recording.session?.id == session.id {
            recording.session = nil
            recording.updatedAt = .now
        }
        modelContext.delete(session)
        do {
            try modelContext.save()
            bannerMessage = "Séance supprimée. Les contenus associés ont été conservés."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    private var readableEventAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    private var readableReminderAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    private func visibleIntervalForExternalData() -> DateInterval {
        if mode == .week {
            return TodayDashboardService.weekInterval(containing: visibleDate)
        }
        guard let month = Calendar.current.dateInterval(of: .month, for: visibleDate) else {
            return DateInterval(start: selectedDate.addingTimeInterval(-86_400), end: selectedDate.addingTimeInterval(86_400))
        }
        return month
    }

    @MainActor
    private func importCalendarEvents(_ events: [CalendarImportEvent], course: Course?) {
        var imported = 0
        var skipped = 0
        for event in events where event.isSelected {
            let duplicate = sessions.contains { session in
                session.title == event.title &&
                abs(session.startTime.timeIntervalSince(event.startDate)) < 60
            }
            if duplicate {
                skipped += 1
                continue
            }
            let session = ClassSession(
                number: (course?.sessions.map(\.number).max() ?? 0) + imported + 1,
                title: event.title,
                sessionDescription: event.notes,
                date: Calendar.current.startOfDay(for: event.startDate),
                startTime: event.startDate,
                endTime: event.endDate,
                room: event.location?.emptyAsNil,
                course: course
            )
            modelContext.insert(session)
            imported += 1
        }
        do {
            try modelContext.save()
            bannerMessage = "\(imported) événement\(imported > 1 ? "s" : "") importé\(imported > 1 ? "s" : ""). \(skipped) doublon\(skipped > 1 ? "s" : "") ignoré\(skipped > 1 ? "s" : "")."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }
}

private struct PlannerEventRow: View {
    let event: PlannerEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.symbolName)
                .font(.title3)
                .foregroundStyle(StudyDeskTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(event.sourceLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(StudyDeskTheme.surfaceTinted, in: Capsule())
                }
                Text(event.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(event.isAllDay ? "Toute la journée" : UniDateFormatters.time.string(from: event.startDate))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct PlannerEventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let event: PlannerEvent
    let resources: [AcademicResource]
    let notes: [StudyNote]
    let tasks: [AcademicTask]
    let recordings: [CourseRecording]
    let quizzes: [Quiz]
    let decks: [StudyDeck]
    let externalLink: ExternalCalendarEventLink?
    let openCourse: (Course, CourseWorkspaceTab) -> Void
    let editSession: (ClassSession) -> Void
    let associateSession: (ClassSession) -> Void
    let addNote: (ClassSession) -> Void
    let addDocument: (ClassSession) -> Void
    let deleteSession: (ClassSession) -> Void
    let editTask: (AcademicTask) -> Void
    let hideAppleCalendar: (ApplePlannerCalendarEvent) -> Void
    let hideAppleEvent: (ApplePlannerCalendarEvent) -> Void
    let openAppleEvent: (ApplePlannerCalendarEvent) -> Void
    let associateAppleEvent: (ApplePlannerCalendarEvent) -> Void
    let addAppleNote: (ApplePlannerCalendarEvent) -> Void
    let addAppleDocument: (ApplePlannerCalendarEvent) -> Void
    let openStudy: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    nextActionSection
                    linkedContextSection
                    associatedContentSection
                    descriptionSection
                    sourceSection
                    actionsSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Détail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.symbolName)
                    .font(.title2)
                    .foregroundStyle(StudyDeskTheme.accentPrimary)
                    .frame(width: 42, height: 42)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(event.sourceLabel)
                        Text(event.isAllDay ? "Toute la journée" : localTimeRange)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
            detailLine("Date", event.startDate.formatted(date: .complete, time: .omitted))
            detailLine("Horaire", event.isAllDay ? "Toute la journée" : localTimeRange)
            if let location {
                detailLine("Lieu", location)
            }
        }
    }

    private var sourceSection: some View {
        section("Source") {
            switch event {
            case .session(let session):
                let origin = session.sessionDescription.localizedCaseInsensitiveContains("Imported from .ics") ? "Import .ics enregistré comme séance UniSaver" : "Séance UniSaver"
                detailLine("Provenance", origin)
                if session.sessionDescription.localizedCaseInsensitiveContains("UID:") {
                    detailLine("Identifiant externe", "Présent dans la description importée")
                }
            case .appleCalendar(let calendarEvent):
                detailLine("Calendrier", calendarEvent.calendarTitle)
                detailLine("Identifiant", calendarEvent.id)
                if let stableID = calendarEvent.stableID {
                    detailLine("Identifiant stable", stableID)
                }
                detailLine("Fuseau affiché", TimeZone.current.identifier)
                detailLine("Fuseau source", event.sourceTimeZoneLabel)
                if calendarEvent.isRecurring {
                    detailLine("Récurrence", "Définie dans Apple Calendar")
                }
                Text("Lecture seule dans UniSaver")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .appleReminder(let reminder):
                detailLine("Liste", reminder.listTitle)
                Text("Lecture seule dans UniSaver")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .task:
                detailLine("Type", "Tâche UniSaver")
            case .studyBlock:
                detailLine("Type", "Bloc d'étude UniSaver")
            case .flashcard:
                detailLine("Type", "Révision de flashcard UniSaver")
            }
        }
    }

    private var nextActionSection: some View {
        section("Prochaine action") {
            switch event {
            case .appleCalendar(let calendarEvent):
                if externalLink == nil {
                    Text("Associe cet événement à un cours UniSaver pour créer des notes, documents et tâches depuis ce créneau.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let suggestion = suggestedAssociationText {
                        Text("Suggestion : \(suggestion)")
                            .font(.callout.weight(.semibold))
                    }
                    Button("Associer à un cours", systemImage: "link") {
                        associateAppleEvent(calendarEvent)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Association confirmée dans UniSaver.")
                        .font(.callout.weight(.semibold))
                    WrapButtons {
                        Button("Créer une note", systemImage: "note.text.badge.plus") { addAppleNote(calendarEvent) }
                        Button("Ajouter un document", systemImage: "doc.badge.plus") { addAppleDocument(calendarEvent) }
                    }
                }
            case .session:
                Text("Séance UniSaver modifiable et reliée à ses contenus.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            default:
                Text("Ouvre la donnée source pour continuer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var linkedContextSection: some View {
        section("Contexte") {
            if let course {
                detailLine("Cours", courseTitle(course))
            } else {
                detailLine("Cours", "Non associé")
            }
            if let chapter {
                detailLine("Chapitre", "\(chapter.number). \(chapter.title)")
            } else {
                detailLine("Chapitre", "Non associé")
            }
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let description, !description.isEmpty {
            section("Description") {
                Text(description)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        if let url {
            section("URL") {
                Link(url.absoluteString, destination: url)
                    .font(.callout)
                    .lineLimit(2)
            }
        }
    }

    private var associatedContentSection: some View {
        section("Contenus associés") {
            let groups = associatedContentGroups
            if groups.allSatisfy({ $0.items.isEmpty }) {
                Text("Aucun contenu lié pour le moment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups.filter { !$0.items.isEmpty }) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.items, id: \.self) { item in
                            Text(item)
                                .font(.callout)
                        }
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        section("Actions") {
            switch event {
            case .session(let session):
                WrapButtons {
                    if let course = session.course {
                        Button("Ouvrir le cours", systemImage: "book.closed") {
                            openCourse(course, .sessions)
                        }
                    }
                    Button("Modifier", systemImage: "square.and.pencil") { editSession(session) }
                    Button("Associer", systemImage: "link") { associateSession(session) }
                    Button("Ajouter une note", systemImage: "note.text.badge.plus") { addNote(session) }
                    Button("Ajouter un document", systemImage: "doc.badge.plus") { addDocument(session) }
                    Button("Supprimer", systemImage: "trash", role: .destructive) { deleteSession(session) }
                }
            case .task(let task):
                WrapButtons {
                    Button("Modifier", systemImage: "square.and.pencil") { editTask(task) }
                    if let course = task.course {
                        Button("Ouvrir le cours", systemImage: "book.closed") {
                            openCourse(course, .overview)
                        }
                    }
                }
            case .appleCalendar(let calendarEvent):
                WrapButtons {
                    Button("Associer à un cours", systemImage: "link") { associateAppleEvent(calendarEvent) }
                    if externalLink != nil {
                        Button("Créer une note", systemImage: "note.text.badge.plus") { addAppleNote(calendarEvent) }
                        Button("Ajouter un document", systemImage: "doc.badge.plus") { addAppleDocument(calendarEvent) }
                    }
                    if let course {
                        Button("Voir le cours", systemImage: "book.closed") { openCourse(course, .overview) }
                    }
                    if let session = externalLink?.session, let targetCourse = session.course ?? course {
                        Button("Voir la séance", systemImage: "person.2") { openCourse(targetCourse, .sessions) }
                    }
                    Button("Ouvrir dans Calendrier", systemImage: "calendar") { openAppleEvent(calendarEvent) }
                    Button("Masquer ce calendrier", systemImage: "eye.slash") { hideAppleCalendar(calendarEvent) }
                    Button("Masquer cet événement", systemImage: "minus.circle") { hideAppleEvent(calendarEvent) }
                }
            case .appleReminder:
                Text("Les rappels Apple sont affichés en lecture seule dans cette version.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .studyBlock(let block):
                WrapButtons {
                    Button(block.status == .completed ? "Replanifier" : "Marquer terminé", systemImage: block.status == .completed ? "arrow.uturn.backward" : "checkmark.circle") {
                        block.status = block.status == .completed ? .planned : .completed
                        block.updatedAt = .now
                        try? modelContext.save()
                    }
                    Button("Ignorer", systemImage: "forward.end", role: .destructive) {
                        block.status = .cancelled
                        block.updatedAt = .now
                        try? modelContext.save()
                    }
                    Button("Ouvrir Study", systemImage: "graduationcap") {
                        dismiss()
                        openStudy()
                    }
                }
            case .flashcard:
                WrapButtons {
                    Button("Ouvrir Study", systemImage: "graduationcap") {
                        dismiss()
                        openStudy()
                    }
                }
            }
        }
    }

    private var localTimeRange: String {
        "\(UniDateFormatters.time.string(from: event.startDate)) - \(UniDateFormatters.time.string(from: event.endDate))"
    }

    private var location: String? {
        switch event {
        case .session(let session): session.room?.emptyAsNil
        case .appleCalendar(let event): event.location?.emptyAsNil
        default: nil
        }
    }

    private var description: String? {
        switch event {
        case .session(let session): session.sessionDescription.emptyAsNil
        case .task(let task): TaskStructureService.visibleDescription(task.taskDescription).emptyAsNil
        case .studyBlock: nil
        case .flashcard(let card): card.back.emptyAsNil
        case .appleCalendar(let event): event.notes?.emptyAsNil
        case .appleReminder: nil
        }
    }

    private var url: URL? {
        if case .appleCalendar(let event) = event {
            return event.url
        }
        return nil
    }

    private var course: Course? {
        switch event {
        case .session(let session): session.course
        case .task(let task): task.course
        case .studyBlock(let block): block.course
        case .flashcard(let card): card.deck?.course
        case .appleCalendar: externalLink?.course ?? externalLink?.session?.course
        case .appleReminder: nil
        }
    }

    private var chapter: Chapter? {
        switch event {
        case .session(let session): session.chapter
        case .task(let task): task.chapter
        case .flashcard(let card): card.deck?.chapter
        case .appleCalendar: externalLink?.chapter ?? externalLink?.session?.chapter
        default: nil
        }
    }

    private var suggestedAssociationText: String? {
        guard case .appleCalendar = event else { return nil }
        if let session = matchingSession {
            return session.course.map { "\(courseTitle($0)) · \(session.title)" } ?? session.title
        }
        return nil
    }

    private var matchingSession: ClassSession? {
        guard case .appleCalendar = event else {
            return nil
        }
        return nil
    }

    private var associatedContentGroups: [AssociatedContentGroup] {
        let linkedSession: ClassSession?
        let linkedCourse: Course?
        let linkedChapter: Chapter?
        switch event {
        case .session(let session):
            linkedSession = session
            linkedCourse = session.course
            linkedChapter = session.chapter
        case .appleCalendar:
            linkedSession = externalLink?.session
            linkedCourse = externalLink?.course ?? externalLink?.session?.course
            linkedChapter = externalLink?.chapter ?? externalLink?.session?.chapter
        default:
            linkedSession = nil
            linkedCourse = course
            linkedChapter = chapter
        }

        let eventNoteIDs = Set(notes.filter { linkedSession != nil && $0.session?.id == linkedSession?.id }.map(\.id))
        let eventResourceIDs = Set(resources.filter { linkedSession != nil && $0.session?.id == linkedSession?.id }.map(\.id))
        let eventTaskIDs = Set(tasks.filter { linkedSession != nil && $0.session?.id == linkedSession?.id }.map(\.id))
        let eventRecordingIDs = Set(recordings.filter { linkedSession != nil && $0.session?.id == linkedSession?.id }.map(\.id))
        let eventQuizIDs = Set(quizzes.filter { linkedSession != nil && $0.session?.id == linkedSession?.id }.map(\.id))
        let eventDeckIDs = Set(decks.filter { linkedSession != nil && $0.session?.id == linkedSession?.id }.map(\.id))

        var groups: [AssociatedContentGroup] = [
            AssociatedContentGroup(title: "Lié à cet événement", items: eventScopedItems(
                noteIDs: eventNoteIDs,
                resourceIDs: eventResourceIDs,
                taskIDs: eventTaskIDs,
                recordingIDs: eventRecordingIDs,
                quizIDs: eventQuizIDs,
                deckIDs: eventDeckIDs
            ))
        ]

        if let linkedSession {
            groups.append(AssociatedContentGroup(title: "Lié à la séance", items: sessionScopedItems(
                session: linkedSession,
                excludingNoteIDs: eventNoteIDs,
                excludingResourceIDs: eventResourceIDs,
                excludingTaskIDs: eventTaskIDs,
                excludingRecordingIDs: eventRecordingIDs,
                excludingQuizIDs: eventQuizIDs,
                excludingDeckIDs: eventDeckIDs
            )))
        }

        if let linkedCourse {
            groups.append(AssociatedContentGroup(title: "Disponible dans le cours", items: courseScopedItems(course: linkedCourse, chapter: linkedChapter)))
        }

        return groups
    }

    private func eventScopedItems(
        noteIDs: Set<UUID>,
        resourceIDs: Set<UUID>,
        taskIDs: Set<UUID>,
        recordingIDs: Set<UUID>,
        quizIDs: Set<UUID>,
        deckIDs: Set<UUID>
    ) -> [String] {
        labeled(notes.filter { noteIDs.contains($0.id) }, "Note")
        + labeled(resources.filter { resourceIDs.contains($0.id) }, "Document")
        + labeled(tasks.filter { taskIDs.contains($0.id) }, "Tâche")
        + labeled(recordings.filter { recordingIDs.contains($0.id) }, "Enregistrement")
        + labeled(quizzes.filter { quizIDs.contains($0.id) }, "Quiz")
        + labeled(decks.filter { deckIDs.contains($0.id) }, "Deck")
    }

    private func sessionScopedItems(
        session: ClassSession,
        excludingNoteIDs: Set<UUID>,
        excludingResourceIDs: Set<UUID>,
        excludingTaskIDs: Set<UUID>,
        excludingRecordingIDs: Set<UUID>,
        excludingQuizIDs: Set<UUID>,
        excludingDeckIDs: Set<UUID>
    ) -> [String] {
        labeled(notes.filter { $0.session?.id == session.id && !excludingNoteIDs.contains($0.id) }, "Note")
        + labeled(resources.filter { $0.session?.id == session.id && !excludingResourceIDs.contains($0.id) }, "Document")
        + labeled(tasks.filter { $0.session?.id == session.id && !excludingTaskIDs.contains($0.id) }, "Tâche")
        + labeled(recordings.filter { $0.session?.id == session.id && !excludingRecordingIDs.contains($0.id) }, "Enregistrement")
        + labeled(quizzes.filter { $0.session?.id == session.id && !excludingQuizIDs.contains($0.id) }, "Quiz")
        + labeled(decks.filter { $0.session?.id == session.id && !excludingDeckIDs.contains($0.id) }, "Deck")
    }

    private func courseScopedItems(course: Course, chapter: Chapter?) -> [String] {
        let chapterMatches: (Chapter?) -> Bool = { linkedChapter in
            chapter == nil || linkedChapter?.id == chapter?.id
        }
        return labeled(Array(notes.filter { $0.course?.id == course.id && $0.session == nil && chapterMatches($0.chapter) }.prefix(8)), "Note")
        + labeled(Array(resources.filter { $0.course?.id == course.id && $0.session == nil && chapterMatches($0.chapter) }.prefix(8)), "Document")
        + labeled(Array(tasks.filter { $0.course?.id == course.id && $0.session == nil && chapterMatches($0.chapter) }.prefix(8)), "Tâche")
        + labeled(Array(recordings.filter { $0.course?.id == course.id && $0.session == nil && chapterMatches($0.chapter) }.prefix(8)), "Enregistrement")
        + labeled(Array(quizzes.filter { $0.course?.id == course.id && $0.session == nil && chapterMatches($0.chapter) }.prefix(8)), "Quiz")
        + labeled(Array(decks.filter { $0.course?.id == course.id && $0.session == nil && chapterMatches($0.chapter) }.prefix(8)), "Deck")
    }

    private func labeled(_ values: [StudyNote], _ label: String) -> [String] {
        values.map { "\(label) · \($0.title)" }
    }

    private func labeled(_ values: [AcademicResource], _ label: String) -> [String] {
        values.map { "\(label) · \($0.title)" }
    }

    private func labeled(_ values: [AcademicTask], _ label: String) -> [String] {
        values.map { "\(label) · \($0.title)" }
    }

    private func labeled(_ values: [CourseRecording], _ label: String) -> [String] {
        values.map { "\(label) · \($0.title)" }
    }

    private func labeled(_ values: [Quiz], _ label: String) -> [String] {
        values.map { "\(label) · \($0.title)" }
    }

    private func labeled(_ values: [StudyDeck], _ label: String) -> [String] {
        values.map { "\(label) · \($0.title)" }
    }


    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func compactList(_ label: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            detailLine(label, values.joined(separator: ", "))
        }
    }
}

private struct SessionAssociationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: ClassSession
    let courses: [Course]
    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var errorMessage: String?

    init(session: ClassSession, courses: [Course]) {
        self.session = session
        self.courses = courses
        _selectedCourseID = State(initialValue: session.course?.id)
        _selectedChapterID = State(initialValue: session.chapter?.id)
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    private var chapters: [Chapter] {
        selectedCourse?.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Séance") {
                    Text(session.title)
                    Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                Section("Association") {
                    Picker("Cours", selection: $selectedCourseID) {
                        Text("Non associé").tag(UUID?.none)
                        ForEach(courses.filter { !$0.isArchived }) { course in
                            Text(courseTitle(course)).tag(Optional(course.id))
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
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Associer la séance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .onChange(of: selectedCourseID) { _, _ in
            if selectedCourse == nil || !chapters.contains(where: { $0.id == selectedChapterID }) {
                selectedChapterID = nil
            }
        }
    }

    private func save() {
        session.course = selectedCourse
        session.chapter = chapters.first { $0.id == selectedChapterID }
        session.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AppleCalendarEventAssociationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let event: ApplePlannerCalendarEvent
    let existingLink: ExternalCalendarEventLink?
    let allAppleEvents: [ApplePlannerCalendarEvent]
    let existingLinks: [ExternalCalendarEventLink]
    let courses: [Course]
    let sessions: [ClassSession]
    @Binding var seriesRulesData: String

    @State private var selectedCourseID: UUID?
    @State private var selectedChapterID: UUID?
    @State private var selectedSessionID: UUID?
    @State private var associationScope: AppleCalendarAssociationScope = .single
    @State private var createMissingSessions = false
    @State private var newCourseName = ""
    @State private var errorMessage: String?

    init(
        event: ApplePlannerCalendarEvent,
        existingLink: ExternalCalendarEventLink?,
        allAppleEvents: [ApplePlannerCalendarEvent],
        existingLinks: [ExternalCalendarEventLink],
        courses: [Course],
        sessions: [ClassSession],
        seriesRulesData: Binding<String>
    ) {
        self.event = event
        self.existingLink = existingLink
        self.allAppleEvents = allAppleEvents
        self.existingLinks = existingLinks
        self.courses = courses
        self.sessions = sessions
        _seriesRulesData = seriesRulesData
        let suggestion = AppleCalendarAssociationSuggester.bestSuggestion(for: event, courses: courses, sessions: sessions)
        _selectedCourseID = State(initialValue: existingLink?.course?.id ?? existingLink?.session?.course?.id ?? suggestion?.course.id)
        _selectedChapterID = State(initialValue: existingLink?.chapter?.id ?? existingLink?.session?.chapter?.id)
        _selectedSessionID = State(initialValue: existingLink?.session?.id ?? suggestion?.session?.id)
        _newCourseName = State(initialValue: AppleCalendarSeriesMatcher.displayCourseTitle(from: event.title))
    }

    private var selectedCourse: Course? {
        courses.first { $0.id == selectedCourseID }
    }

    private var selectedSession: ClassSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    private var chapters: [Chapter] {
        selectedCourse?.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order } ?? []
    }

    private var filteredSessions: [ClassSession] {
        sessions
            .filter { session in
                guard let selectedCourseID else { return true }
                return session.course?.id == selectedCourseID
            }
            .sorted { $0.startTime < $1.startTime }
    }

    private var suggestions: [AppleEventCourseSuggestion] {
        AppleCalendarAssociationSuggester.suggestions(for: event, courses: courses, sessions: sessions)
    }

    private var seriesPreview: AppleCalendarSeriesPreview {
        AppleCalendarSeriesMatcher.preview(
            anchor: event,
            events: allAppleEvents,
            course: selectedCourse,
            sessions: sessions,
            existingLinks: existingLinks
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                GroupBox("Événement Apple / Apple event") {
                    VStack(alignment: .leading, spacing: 8) {
                    Text(event.title)
                        .font(.headline)
                    Text(event.startDate.formatted(date: .complete, time: .shortened))
                        .foregroundStyle(.secondary)
                    if let location = event.location?.emptyAsNil {
                        Text(location)
                    }
                    Text("L’événement Apple Calendar restera en lecture seule.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !suggestions.isEmpty {
                    GroupBox("Suggestion de matière / Suggested course") {
                        VStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestions.prefix(3)) { suggestion in
                            Button {
                                selectedCourseID = suggestion.course.id
                                selectedSessionID = suggestion.session?.id
                                selectedChapterID = suggestion.session?.chapter?.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(courseTitle(suggestion.course))
                                            .font(.callout.weight(.semibold))
                                        Spacer()
                                        Text(suggestion.confidenceLabel)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(suggestion.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        }
                    }
                }

                GroupBox("Association confirmée / Confirmed association") {
                    VStack(alignment: .leading, spacing: 12) {
                    Picker("Portée", selection: $associationScope) {
                        Text("Cette séance uniquement").tag(AppleCalendarAssociationScope.single)
                        Text("Toutes les séances correspondantes").tag(AppleCalendarAssociationScope.series)
                    }
                    .pickerStyle(.segmented)
                    Text(associationScope == .single
                         ? "Cette séance uniquement crée ou met à jour le lien de cette occurrence Apple Calendar."
                         : "Toutes les séances correspondantes applique une règle aux occurrences qui partagent la même identité de cours normalisée. Les cas ambigus restent à vérifier.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("Cours", selection: $selectedCourseID) {
                        Text("Non associé").tag(UUID?.none)
                        ForEach(courses.filter { !$0.isArchived }) { course in
                            Text(courseTitle(course)).tag(Optional(course.id))
                        }
                    }
                    Picker("Chapitre", selection: $selectedChapterID) {
                        Text("Sans chapitre").tag(UUID?.none)
                        ForEach(chapters) { chapter in
                            Text("\(chapter.number). \(chapter.title)").tag(Optional(chapter.id))
                        }
                    }
                    .disabled(selectedCourse == nil)
                    Picker("Séance", selection: $selectedSessionID) {
                        Text("Aucune séance liée").tag(UUID?.none)
                        ForEach(filteredSessions) { session in
                            Text("\(session.title) · \(session.startTime.formatted(date: .abbreviated, time: .shortened))").tag(Optional(session.id))
                        }
                    }
                    Divider()
                    TextField("Créer une nouvelle matière si nécessaire", text: $newCourseName)
                    Text("Si aucune matière existante n’est choisie, UniSaver créera cette matière une seule fois puis l’utilisera pour la série confirmée.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if associationScope == .series {
                    GroupBox("Aperçu de la série / Series preview") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(seriesPreview.matchingEvents.count) événement(s) trouvé(s)")
                                .font(.headline)
                            Text(seriesPreview.periodLabel)
                                .foregroundStyle(.secondary)
                            Toggle("Créer les séances manquantes après confirmation", isOn: $createMissingSessions)
                            Text("\(seriesPreview.linkableExistingSessions.count) occurrence(s) liées à une séance existante · \(seriesPreview.missingSessionEvents.count) séance(s) manquante(s) · \(seriesPreview.excludedEvents.count) à vérifier")
                                .font(.callout)
                            ForEach(seriesPreview.examples, id: \.self) { example in
                                Text(example)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !seriesPreview.exclusionExamples.isEmpty {
                                Divider()
                                Text("À vérifier / To review")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(seriesPreview.exclusionExamples, id: \.self) { example in
                                    Text(example)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("Comportement / Behavior") {
                    Text("Les corrections manuelles existantes sont prioritaires. Les événements Apple restent en lecture seule. Si un titre ou horaire devient ambigu, UniSaver laisse l’occurrence à vérifier au lieu de la rattacher silencieusement.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                }
                .padding(20)
            }
            .navigationTitle("Associer l’événement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 640)
        .onChange(of: selectedSessionID) { _, _ in
            if let session = selectedSession {
                selectedCourseID = session.course?.id ?? selectedCourseID
                selectedChapterID = session.chapter?.id ?? selectedChapterID
            }
        }
        .onChange(of: selectedCourseID) { _, _ in
            if selectedCourse == nil {
                selectedChapterID = nil
            } else if !chapters.contains(where: { $0.id == selectedChapterID }) {
                selectedChapterID = nil
            }
            if let selectedSession, selectedCourseID != nil, selectedSession.course?.id != selectedCourseID {
                selectedSessionID = nil
            }
        }
    }

    private var canSave: Bool {
        selectedCourse != nil || selectedSession != nil || !newCourseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else {
            errorMessage = "Choisis ou crée une matière, ou associe une séance."
            return
        }
        let targetCourse = selectedCourse ?? selectedSession?.course ?? createCourseIfNeeded()
        guard targetCourse != nil || selectedSession != nil else {
            errorMessage = "Impossible de créer la matière."
            return
        }
        if associationScope == .series {
            saveSeries(course: targetCourse)
        } else {
            saveSingle(course: targetCourse)
        }
    }

    private func saveSingle(course: Course?) {
        let target = existingLink ?? ExternalCalendarEventLink(
            externalEventIdentifier: event.id,
            externalStableIdentifier: event.stableID,
            externalCalendarIdentifier: event.calendarIdentifier,
            occurrenceStartDate: event.startDate,
            titleSnapshot: event.title,
            calendarTitleSnapshot: event.calendarTitle,
            sourceURLString: event.url?.absoluteString
        )
        if existingLink == nil {
            modelContext.insert(target)
        }
        target.externalEventIdentifier = event.id
        target.externalStableIdentifier = event.stableID
        target.externalCalendarIdentifier = event.calendarIdentifier
        target.occurrenceStartDate = event.startDate
        target.titleSnapshot = event.title
        target.calendarTitleSnapshot = event.calendarTitle
        target.sourceURLString = event.url?.absoluteString
        target.course = course ?? selectedSession?.course
        target.chapter = chapters.first { $0.id == selectedChapterID } ?? selectedSession?.chapter
        target.session = selectedSession
        target.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSeries(course: Course?) {
        guard let course else {
            errorMessage = "Choisis ou crée une matière pour appliquer la série."
            return
        }
        let preview = seriesPreview
        guard !preview.matchingEvents.isEmpty else {
            errorMessage = "Aucune occurrence correspondante trouvée."
            return
        }
        for appleEvent in preview.matchingEvents {
            guard existingLinks.first(where: { $0.externalEventIdentifier == appleEvent.id }) == nil else {
                continue
            }
            let session = AppleCalendarSeriesMatcher.matchingSession(for: appleEvent, course: course, sessions: sessions)
                ?? (createMissingSessions ? createSession(from: appleEvent, course: course) : nil)
            guard session != nil || createMissingSessions || appleEvent.id == event.id else {
                continue
            }
            let link = ExternalCalendarEventLink(
                externalEventIdentifier: appleEvent.id,
                externalStableIdentifier: appleEvent.stableID,
                externalCalendarIdentifier: appleEvent.calendarIdentifier,
                occurrenceStartDate: appleEvent.startDate,
                titleSnapshot: appleEvent.title,
                calendarTitleSnapshot: appleEvent.calendarTitle,
                sourceURLString: appleEvent.url?.absoluteString,
                course: course,
                chapter: session?.chapter,
                session: session
            )
            modelContext.insert(link)
        }
        var rules = AppleCalendarSeriesRuleStore.decode(seriesRulesData)
        let rule = AppleCalendarSeriesRule(
            calendarIdentifier: event.calendarIdentifier,
            normalizedSeriesTitle: AppleCalendarSeriesMatcher.normalizedSeriesTitle(event.title),
            courseID: course.id.uuidString,
            createsMissingSessions: createMissingSessions,
            createdAt: Date()
        )
        rules.removeAll { $0.calendarIdentifier == rule.calendarIdentifier && $0.normalizedSeriesTitle == rule.normalizedSeriesTitle }
        rules.append(rule)
        seriesRulesData = AppleCalendarSeriesRuleStore.encode(rules)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createCourseIfNeeded() -> Course? {
        let name = newCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let course = Course(
            name: name,
            code: "",
            colorIdentifier: CourseColor.allCases.randomElement()?.rawValue ?? "blueViolet",
            symbolName: "book.closed"
        )
        modelContext.insert(course)
        selectedCourseID = course.id
        return course
    }

    private func createSession(from appleEvent: ApplePlannerCalendarEvent, course: Course) -> ClassSession {
        let session = ClassSession(
            number: (course.sessions.map(\.number).max() ?? 0) + 1,
            title: appleEvent.title,
            sessionDescription: "Source : Apple Calendar · \(appleEvent.calendarTitle)",
            date: Calendar.current.startOfDay(for: appleEvent.startDate),
            startTime: appleEvent.startDate,
            endTime: max(appleEvent.endDate, appleEvent.startDate.addingTimeInterval(900)),
            room: appleEvent.location,
            course: course
        )
        modelContext.insert(session)
        return session
    }
}

private struct AppleEventCourseSuggestion: Identifiable {
    let id = UUID()
    let course: Course
    let session: ClassSession?
    let score: Int
    let reason: String

    var isReliableAutomaticMatch: Bool {
        score >= 90 && session != nil
    }

    var confidenceLabel: String {
        if score >= 90 { return "Très probable" }
        if score >= 60 { return "Probable" }
        return "À confirmer"
    }
}

private enum AppleCalendarAssociationScope: String, CaseIterable, Identifiable {
    case single
    case series

    var id: String { rawValue }
}

struct AppleCalendarSeriesRule: Codable, Hashable, Identifiable {
    var id: String { "\(calendarIdentifier)-\(normalizedSeriesTitle)" }
    var calendarIdentifier: String
    var normalizedSeriesTitle: String
    var courseID: String
    var createsMissingSessions: Bool
    var createdAt: Date

    func matches(_ event: ApplePlannerCalendarEvent) -> Bool {
        event.calendarIdentifier == calendarIdentifier &&
        AppleCalendarSeriesMatcher.normalizedSeriesTitle(event.title) == normalizedSeriesTitle
    }
}

enum AppleCalendarSeriesRuleStore {
    static func decode(_ value: String) -> [AppleCalendarSeriesRule] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([AppleCalendarSeriesRule].self, from: data)) ?? []
    }

    static func encode(_ rules: [AppleCalendarSeriesRule]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

private struct AppleCalendarSeriesPreview {
    var matchingEvents: [ApplePlannerCalendarEvent]
    var linkableExistingSessions: [ClassSession]
    var missingSessionEvents: [ApplePlannerCalendarEvent]
    var excludedEvents: [ApplePlannerCalendarEvent]

    var periodLabel: String {
        guard let first = matchingEvents.map(\.startDate).min(),
              let last = matchingEvents.map(\.startDate).max() else {
            return "Aucune période."
        }
        return "\(UniDateFormatters.dayMonth.string(from: first)) - \(UniDateFormatters.dayMonth.string(from: last))"
    }

    var examples: [String] {
        matchingEvents.prefix(4).map {
            "\($0.title) · \($0.startDate.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    var exclusionExamples: [String] {
        excludedEvents.prefix(4).map {
            "\($0.title) · \($0.startDate.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}

private enum AppleCalendarSeriesMatcher {
    static func preview(
        anchor: ApplePlannerCalendarEvent,
        events: [ApplePlannerCalendarEvent],
        course: Course?,
        sessions: [ClassSession],
        existingLinks: [ExternalCalendarEventLink]
    ) -> AppleCalendarSeriesPreview {
        let identity = normalizedSeriesTitle(anchor.title)
        let candidates = events.filter {
            $0.calendarIdentifier == anchor.calendarIdentifier &&
            normalizedSeriesTitle($0.title) == identity
        }
        let manuallyLinkedIDs = Set(existingLinks.map(\.externalEventIdentifier))
        let matching = candidates.filter { event in
            !manuallyLinkedIDs.contains(event.id) || event.id == anchor.id
        }
        let excluded = events.filter {
            $0.calendarIdentifier == anchor.calendarIdentifier &&
            normalizedSeriesTitle($0.title) != identity &&
            hasLooseOverlap($0.title, anchor.title)
        } + candidates.filter { manuallyLinkedIDs.contains($0.id) && $0.id != anchor.id }
        let linkedSessions = matching.compactMap { event -> ClassSession? in
            guard let course else { return nil }
            return matchingSession(for: event, course: course, sessions: sessions)
        }
        let missing = matching.filter { event in
            guard let course else { return true }
            return matchingSession(for: event, course: course, sessions: sessions) == nil
        }
        return AppleCalendarSeriesPreview(
            matchingEvents: matching.sorted { $0.startDate < $1.startDate },
            linkableExistingSessions: linkedSessions,
            missingSessionEvents: missing,
            excludedEvents: excluded.sorted { $0.startDate < $1.startDate }
        )
    }

    static func matchingSession(for event: ApplePlannerCalendarEvent, course: Course, sessions: [ClassSession]) -> ClassSession? {
        sessions
            .filter { $0.course?.id == course.id }
            .filter {
                Calendar.current.isDate($0.startTime, inSameDayAs: event.startDate) &&
                abs($0.startTime.timeIntervalSince(event.startDate)) <= 45 * 60
            }
            .min { abs($0.startTime.timeIntervalSince(event.startDate)) < abs($1.startTime.timeIntervalSince(event.startDate)) }
    }

    static func normalizedSeriesTitle(_ title: String) -> String {
        let withoutParentheses = title.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: " ", options: .regularExpression)
        let withoutSeparators = withoutParentheses
            .replacingOccurrences(of: #"\s*[-–—|]\s*(lecture|class|session|room|salle|prof\.?|teacher|enseignant).*$"#, with: " ", options: [.regularExpression, .caseInsensitive])
        let tokens = normalizedTokens(withoutSeparators)
        return tokens.joined(separator: " ")
    }

    static func displayCourseTitle(from eventTitle: String) -> String {
        let normalized = normalizedSeriesTitle(eventTitle)
        guard !normalized.isEmpty else { return eventTitle }
        return normalized.split(separator: " ").map { token in
            token.prefix(1).uppercased() + token.dropFirst()
        }.joined(separator: " ")
    }

    private static func hasLooseOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let left = Set(normalizedTokens(lhs).filter { $0.count > 4 })
        let right = Set(normalizedTokens(rhs).filter { $0.count > 4 })
        return !left.intersection(right).isEmpty
    }

    private static func normalizedTokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !genericTokens.contains($0) }
    }

    private static let genericTokens: Set<String> = [
        "lecture", "session", "class", "course", "room", "salle", "prof", "teacher", "enseignant", "grupo", "group"
    ]
}

private enum AppleCalendarAssociationSuggester {
    static func bestSuggestion(for event: ApplePlannerCalendarEvent, courses: [Course], sessions: [ClassSession]) -> AppleEventCourseSuggestion? {
        suggestions(for: event, courses: courses, sessions: sessions).first
    }

    static func suggestions(for event: ApplePlannerCalendarEvent, courses: [Course], sessions: [ClassSession]) -> [AppleEventCourseSuggestion] {
        guard !courses.isEmpty else { return [] }
        return courses.compactMap { course in
            let titleScore = textualScore(eventTitle: event.title, course: course)
            let sessionMatch = sessions
                .filter { $0.course?.id == course.id }
                .min { abs($0.startTime.timeIntervalSince(event.startDate)) < abs($1.startTime.timeIntervalSince(event.startDate)) }
            let timeScore: Int
            if let sessionMatch, abs(sessionMatch.startTime.timeIntervalSince(event.startDate)) <= 15 * 60 {
                timeScore = 45
            } else if let sessionMatch, Calendar.current.isDate(sessionMatch.startTime, inSameDayAs: event.startDate) {
                timeScore = 20
            } else {
                timeScore = 0
            }
            let locationScore = (event.location?.isEmpty == false && event.location == course.defaultRoom) ? 15 : 0
            let score = titleScore + timeScore + locationScore
            guard score > 0 else { return nil }
            let reasons = [
                titleScore > 0 ? "titre/code" : nil,
                timeScore > 0 ? "horaire proche" : nil,
                locationScore > 0 ? "salle" : nil
            ].compactMap { $0 }.joined(separator: ", ")
            return AppleEventCourseSuggestion(course: course, session: timeScore >= 20 ? sessionMatch : nil, score: score, reason: "Indices utilisés : \(reasons).")
        }
        .sorted { $0.score > $1.score }
    }

    private static func textualScore(eventTitle: String, course: Course) -> Int {
        let title = normalized(eventTitle)
        let name = normalized(course.name)
        let code = normalized(course.code)
        if !code.isEmpty && title.contains(code) { return 55 }
        if !name.isEmpty && title.contains(name) { return 55 }
        let titleTokens = Set(title.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let courseTokens = Set(name.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let overlap = titleTokens.intersection(courseTokens).count
        if overlap >= 2 { return 40 }
        if overlap == 1 { return 20 }
        return 0
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct WrapButtons<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

private struct PlannerWeekGrid: View {
    let days: [Date]
    let events: [PlannerEvent]
    @Binding var selectedDate: Date
    let open: (PlannerEvent) -> Void

    private let hourHeight: CGFloat = 62
    private let hourRange = 7...21
    private let timeColumnWidth: CGFloat = 54

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("")
                    .frame(width: timeColumnWidth)
                ForEach(days, id: \.self) { day in
                    Button {
                        selectedDate = day
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption.weight(.semibold))
                            Text(day.formatted(.dateTime.day()))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? StudyDeskTheme.surfaceTinted : .clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            allDayRow
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(hourRange), id: \.self) { hour in
                            Text("\(hour):00")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: timeColumnWidth, height: hourHeight, alignment: .topTrailing)
                                .padding(.trailing, 6)
                        }
                    }
                    ForEach(days, id: \.self) { day in
                        dayColumn(day)
                    }
                }
                .frame(minHeight: CGFloat(hourRange.count) * hourHeight)
            }
        }
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var allDayRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("Toute\njournée")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .padding(.trailing, 6)
                .padding(.vertical, 8)

            ForEach(days, id: \.self) { day in
                let dayEvents = events.filter { $0.isAllDay && Calendar.current.isDate($0.startDate, inSameDayAs: day) }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(dayEvents.prefix(3)) { event in
                        Button {
                            selectedDate = day
                            open(event)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: event.symbolName)
                                    .font(.caption2)
                                Text(event.title)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CourseColor.color(for: event.courseColorIdentifier).opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    if dayEvents.count > 3 {
                        Text("+\(dayEvents.count - 3)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                .padding(4)
                .overlay(alignment: .trailing) {
                    Divider()
                }
            }
        }
        .background(StudyDeskTheme.backgroundSecondary.opacity(0.45))
    }

    private func dayColumn(_ day: Date) -> some View {
        let dayEvents = events.filter { !$0.isAllDay && Calendar.current.isDate($0.startDate, inSameDayAs: day) }
        let positioned = positionedEvents(dayEvents)
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(Array(hourRange), id: \.self) { _ in
                        Rectangle()
                            .fill(.clear)
                            .frame(height: hourHeight)
                            .overlay(alignment: .top) {
                                Divider()
                            }
                        }
                }
                ForEach(positioned) { item in
                    let laneWidth = max(46, proxy.size.width / CGFloat(max(item.laneCount, 1)))
                    eventBlock(item.event)
                        .frame(width: max(40, laneWidth - 6))
                        .offset(
                            x: CGFloat(item.lane) * laneWidth + 3,
                            y: offset(for: item.event.startDate)
                        )
                        .zIndex(Double(item.lane))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedDate = day
            }
            .overlay(alignment: .trailing) {
                Divider()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(hourRange.count) * hourHeight, alignment: .top)
    }

    private func positionedEvents(_ dayEvents: [PlannerEvent]) -> [PositionedPlannerEvent] {
        var laneEnds: [Date] = []
        var mapped: [(PlannerEvent, Int)] = []
        for event in dayEvents.sorted(by: { $0.startDate < $1.startDate }) {
            if let lane = laneEnds.firstIndex(where: { $0 <= event.startDate }) {
                laneEnds[lane] = event.endDate
                mapped.append((event, lane))
            } else {
                laneEnds.append(event.endDate)
                mapped.append((event, laneEnds.count - 1))
            }
        }
        let laneCount = max(laneEnds.count, 1)
        return mapped.map { PositionedPlannerEvent(event: $0.0, lane: $0.1, laneCount: laneCount) }
    }

    private struct PositionedPlannerEvent: Identifiable {
        let event: PlannerEvent
        let lane: Int
        let laneCount: Int

        var id: String {
            "\(event.id)-lane-\(lane)"
        }
    }

    private func eventBlock(_ event: PlannerEvent) -> some View {
        Button {
            selectedDate = event.startDate
            open(event)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Text("\(UniDateFormatters.time.string(from: event.startDate)) - \(UniDateFormatters.time.string(from: event.endDate))")
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                Text(event.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: height(for: event), alignment: .topLeading)
            .background(CourseColor.color(for: event.courseColorIdentifier).opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(CourseColor.color(for: event.courseColorIdentifier).opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func offset(for date: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let clampedHour = min(max(hour, hourRange.lowerBound), hourRange.upperBound)
        return CGFloat(clampedHour - hourRange.lowerBound) * hourHeight + CGFloat(minute) / 60 * hourHeight
    }

    private func height(for event: PlannerEvent) -> CGFloat {
        max(34, min(180, event.endDate.timeIntervalSince(event.startDate) / 3600 * hourHeight))
    }
}

private struct CalendarImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let courses: [Course]
    let existingSessions: [ClassSession]

    @State private var events: [CalendarImportEvent] = []
    @State private var errors: [CalendarImportError] = []
    @State private var proposals: [CalendarCourseProposal] = []
    @State private var importError: String?
    @State private var selectedFileName: String?
    @State private var calendarText: String?
    @State private var selectedFloatingTimeZoneID = TimeZone.current.identifier
    @State private var showsCourseForm = false

    private var importDisabledReason: String? {
        if events.isEmpty {
            return "Aucun événement valide à importer."
        }
        if proposals.allSatisfy({ $0.action == .ignore }) {
            return "Choisis au moins un cours ou événement à importer."
        }
        if proposals.contains(where: { $0.action == .linkExisting && $0.selectedCourseID == nil }) {
            return "Choisis le cours existant pour chaque groupe à lier."
        }
        return nil
    }

    private var importSummary: CalendarOrganizationSummary {
        CalendarOrganizationAnalyzer.summary(for: proposals, existingSessions: existingSessions)
    }

    private var eventDateSummary: String {
        guard let first = events.map(\.startDate).min(),
              let last = events.map(\.startDate).max() else {
            return "Aucun événement valide."
        }
        return "\(events.count) événement(s) trouvé(s), du \(first.formatted(date: .abbreviated, time: .shortened)) au \(last.formatted(date: .abbreviated, time: .shortened))."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Choisir un fichier .ics", systemImage: "doc.badge.plus") {
                        chooseICSFile()
                    }
                    if let selectedFileName {
                        Text("Fichier sélectionné : \(selectedFileName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(eventDateSummary)
                        .font(.callout.weight(.semibold))
                    Text("UniSaver regroupe les événements par intitulé, code éventuel, lieu, enseignant et horaires observés. Les règles RRULE non développées restent signalées ; aucune date n’est inventée.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if events.contains(where: \.isFloatingTime) {
                        Picker("Fuseau source des dates sans TZID", selection: $selectedFloatingTimeZoneID) {
                            ForEach(CalendarICSParser.suggestedTimeZoneIdentifiers, id: \.self) { identifier in
                                Text(identifier).tag(identifier)
                            }
                        }
                        .onChange(of: selectedFloatingTimeZoneID) { _, _ in
                            reparseWithSelectedFloatingTimeZone()
                        }
                        Text("Certaines dates du fichier n’indiquent ni Z ni TZID. Choisis le fuseau source avant import ; UniSaver enregistrera ensuite l’instant absolu et l’affichera dans le fuseau de ton Mac.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let importError {
                        Text(importError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding()

                List {
                    if proposals.isEmpty && errors.isEmpty {
                        EmptyStateView(title: "Aucun calendrier choisi", message: "Importe un fichier .ics pour prévisualiser ses événements.", systemImage: "calendar.badge.plus")
                    }
                    if !proposals.isEmpty {
                        Section("Cours détectés") {
                            ForEach($proposals) { $proposal in
                                CalendarCourseProposalRow(proposal: $proposal, courses: courses)
                            }
                        }
                        Section("Récapitulatif exact") {
                            Label("\(importSummary.coursesToCreate) cours à créer", systemImage: "books.vertical")
                            Label("\(importSummary.sessionsToAttach) séances à rattacher", systemImage: "link")
                            Label("\(importSummary.unfiledEvents) événements non classés", systemImage: "tray")
                            Label("\(importSummary.duplicatesIgnored) doublons ignorés", systemImage: "exclamationmark.triangle")
                        }
                    }
                    if !errors.isEmpty {
                        Section("Lignes ignorées") {
                            ForEach(errors) { error in
                                Text("Ligne \(error.line): \(error.message)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Importer un calendrier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importer") {
                        commitImport()
                    }
                    .disabled(importDisabledReason != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let importDisabledReason {
                    Text(importDisabledReason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.bar)
                }
            }
            .sheet(isPresented: $showsCourseForm) {
                CourseFormView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .courseCreated)) { notification in
                if let course = notification.object as? Course {
                    if let index = proposals.firstIndex(where: { $0.action == .linkExisting && $0.selectedCourseID == nil }) {
                        proposals[index].selectedCourseID = course.id
                    }
                    showsCourseForm = false
                }
            }
        }
        .frame(minWidth: 640, minHeight: 560)
    }

    private func chooseICSFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.calendarEvent]
        panel.allowsOtherFileTypes = false
        panel.message = "Choisis un fichier calendrier .ics"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            events = []
            errors = []
            proposals = []
            selectedFileName = nil
            importError = "Sélection annulée."
            return
        }
        load(url)
    }

    private func load(_ url: URL) {
        guard url.pathExtension.localizedCaseInsensitiveCompare("ics") == .orderedSame else {
            events = []
            errors = []
            proposals = []
            selectedFileName = url.lastPathComponent
            importError = "Le fichier sélectionné n’est pas un .ics."
            return
        }
        do {
            selectedFileName = url.lastPathComponent
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            calendarText = text
            guard text.localizedCaseInsensitiveContains("BEGIN:VCALENDAR") else {
                events = []
                errors = []
                proposals = []
                importError = "Le fichier .ics ne contient pas de calendrier VCALENDAR valide."
                return
            }
            let parsed = CalendarICSParser.parse(text, defaultFloatingTimeZone: TimeZone(identifier: selectedFloatingTimeZoneID) ?? .current)
            events = parsed.events
            errors = parsed.errors
            proposals = CalendarOrganizationAnalyzer.proposals(for: parsed.events, courses: courses, existingSessions: existingSessions)
            importError = parsed.events.isEmpty ? "Aucun événement valide n’a été trouvé." : nil
        } catch {
            events = []
            errors = []
            proposals = []
            calendarText = nil
            importError = "Lecture du fichier impossible : \(error.localizedDescription)"
        }
    }

    private func reparseWithSelectedFloatingTimeZone() {
        guard let calendarText else { return }
        let parsed = CalendarICSParser.parse(calendarText, defaultFloatingTimeZone: TimeZone(identifier: selectedFloatingTimeZoneID) ?? .current)
        events = parsed.events
        errors = parsed.errors
        proposals = CalendarOrganizationAnalyzer.proposals(for: parsed.events, courses: courses, existingSessions: existingSessions)
    }

    private func commitImport() {
        do {
            try CalendarOrganizationAnalyzer.saveCalendarImport(proposals, courses: courses, existingSessions: existingSessions, in: modelContext)
            dismiss()
        } catch {
            importError = "Import impossible : \(error.localizedDescription)"
        }
    }
}

struct CalendarImportEvent: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var startDate: Date
    var endDate: Date
    var sourceStartText: String = ""
    var sourceEndText: String = ""
    var sourceTimeZoneIdentifier: String?
    var isFloatingTime = false
    var location: String?
    var notes: String
    var recurrenceNote: String?
    var isSelected = true

    var sourceTimeDescription: String {
        let sourceZone = sourceTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let zoneLabel = sourceTimeZoneIdentifier ?? "sans fuseau"
        return "\(Self.timeFormatter(timeZone: sourceZone).string(from: startDate))-\(Self.timeFormatter(timeZone: sourceZone).string(from: endDate)) (\(zoneLabel))"
    }

    var deviceTimeDescription: String {
        "\(UniDateFormatters.interval(startDate, endDate)) (\(TimeZone.current.identifier))"
    }

    private static func timeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        return formatter
    }
}

struct CalendarImportError: Identifiable, Hashable, Error {
    let id = UUID()
    var line: Int
    var message: String
}

enum CalendarCourseAction: String, CaseIterable, Identifiable {
    case createCourse
    case linkExisting
    case keepUnfiled
    case ignore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createCourse: "Créer un cours"
        case .linkExisting: "Lier à un cours"
        case .keepUnfiled: "Non classé"
        case .ignore: "Ignorer"
        }
    }
}

struct CalendarCourseProposal: Identifiable, Hashable {
    let id = UUID()
    var sourceEventIDs: [UUID]
    var sourceSessionIDs: [UUID]
    var normalizedTitle: String
    var action: CalendarCourseAction
    var selectedCourseID: UUID?
    var proposedName: String
    var proposedCode: String
    var proposedProfessor: String
    var proposedRoom: String
    var proposedStartDate: Date?
    var proposedEndDate: Date?
    var confidence: Double
    var evidence: [String]
    var warnings: [String]
    var schedules: [String]
    var events: [CalendarImportEvent]
    var sessions: [ClassSession]
}

struct CalendarOrganizationSummary {
    var coursesToCreate: Int
    var sessionsToAttach: Int
    var unfiledEvents: Int
    var duplicatesIgnored: Int
}

struct CalendarCourseProposalRow: View {
    @Binding var proposal: CalendarCourseProposal
    let courses: [Course]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.proposedName)
                        .font(.headline)
                    Text("\(proposal.events.count + proposal.sessions.count) séance(s) · confiance \(proposal.confidence.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Action", selection: $proposal.action) {
                    ForEach(CalendarCourseAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            if proposal.action == .createCourse {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Nom")
                        TextField("Nom du cours", text: $proposal.proposedName)
                    }
                    GridRow {
                        Text("Code")
                        TextField("Code", text: $proposal.proposedCode)
                    }
                    GridRow {
                        Text("Professeur")
                        TextField("Professeur", text: $proposal.proposedProfessor)
                    }
                    GridRow {
                        Text("Salle")
                        TextField("Salle", text: $proposal.proposedRoom)
                    }
                }
                .textFieldStyle(.roundedBorder)
            } else if proposal.action == .linkExisting {
                Picker("Cours", selection: $proposal.selectedCourseID) {
                    Text("Choisir un cours").tag(UUID?.none)
                    ForEach(courses.filter { !$0.isArchived }) { course in
                        Text(course.name).tag(Optional(course.id))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Indices : \(proposal.evidence.joined(separator: " · "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !proposal.schedules.isEmpty {
                    Text("Horaires : \(proposal.schedules.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let sample = proposal.events.first {
                    Text("Source : \(sample.sourceTimeDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Affiché sur ce Mac : \(sample.deviceTimeDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(proposal.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct CalendarOrganizationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let title: String
    let source: CalendarOrganizationSource
    let courses: [Course]
    let existingSessions: [ClassSession]
    @State private var proposals: [CalendarCourseProposal] = []
    @State private var errorMessage: String?

    private var disabledReason: String? {
        if proposals.isEmpty { return "Aucun événement non classé à organiser." }
        if proposals.allSatisfy({ $0.action == .ignore }) { return "Choisis au moins un groupe à organiser." }
        if proposals.contains(where: { $0.action == .linkExisting && $0.selectedCourseID == nil }) { return "Choisis les cours existants à lier." }
        return nil
    }

    private var summary: CalendarOrganizationSummary {
        CalendarOrganizationAnalyzer.summary(for: proposals, existingSessions: existingSessions)
    }

    var body: some View {
        NavigationStack {
            List {
                if proposals.isEmpty {
                    EmptyStateView(title: "Rien à organiser", message: "Aucune séance importée sans cours n’a été trouvée.", systemImage: "tray")
                } else {
                    Section("Cours détectés") {
                        ForEach($proposals) { $proposal in
                            CalendarCourseProposalRow(proposal: $proposal, courses: courses)
                        }
                    }
                    Section("Récapitulatif") {
                        Label("\(summary.coursesToCreate) cours à créer", systemImage: "books.vertical")
                        Label("\(summary.sessionsToAttach) séances à rattacher", systemImage: "link")
                        Label("\(summary.unfiledEvents) séances laissées non classées", systemImage: "tray")
                        Label("\(summary.duplicatesIgnored) doublons ignorés", systemImage: "exclamationmark.triangle")
                    }
                }
                if let errorMessage {
                    Section("Erreur") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirmer") {
                        commit()
                    }
                    .disabled(disabledReason != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let disabledReason {
                    Text(disabledReason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.bar)
                }
            }
            .onAppear {
                proposals = CalendarOrganizationAnalyzer.proposals(for: source, courses: courses, existingSessions: existingSessions)
            }
        }
        .frame(minWidth: 760, minHeight: 620)
    }

    private func commit() {
        do {
            try CalendarOrganizationAnalyzer.organizeExistingSessions(proposals, courses: courses, existingSessions: existingSessions, in: modelContext)
            dismiss()
        } catch {
            errorMessage = "Organisation impossible : \(error.localizedDescription)"
        }
    }
}

enum CalendarOrganizationSource {
    case calendarEvents([CalendarImportEvent])
    case existingSessions([ClassSession])
}

struct CalendarTimeZoneCorrectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let candidateSessions: [ClassSession]
    @State private var sourceTimeZoneID = "Africa/Casablanca"
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var errorMessage: String?

    private var likelyImportedSessions: [ClassSession] {
        candidateSessions
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Fuseau source à appliquer", selection: $sourceTimeZoneID) {
                        ForEach(CalendarICSParser.suggestedTimeZoneIdentifiers, id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    }
                    Text("UniSaver prend l’heure actuellement affichée pour chaque séance sélectionnée et la réinterprète dans le fuseau source choisi. Cela corrige un ancien import où le TZID avait été ignoré, sans créer de doublon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Séances à corriger") {
                    ForEach(likelyImportedSessions) { session in
                        Toggle(isOn: Binding(
                            get: { selectedSessionIDs.contains(session.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedSessionIDs.insert(session.id)
                                } else {
                                    selectedSessionIDs.remove(session.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title)
                                    .font(.headline)
                                Text("Actuel : \(UniDateFormatters.interval(session.startTime, session.endTime)) \(TimeZone.current.identifier)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let corrected = correctedInterval(for: session) {
                                    Text("Après correction : \(UniDateFormatters.interval(corrected.start, corrected.end)) \(TimeZone.current.identifier)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                if session.course != nil {
                                    Text("Déjà rattachée à un cours : vérifie avant de sélectionner.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section("Erreur") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Corriger le fuseau")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        applyCorrection()
                    }
                    .disabled(selectedSessionIDs.isEmpty)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    private func correctedInterval(for session: ClassSession) -> DateInterval? {
        guard let sourceTimeZone = TimeZone(identifier: sourceTimeZoneID) else { return nil }
        let start = reinterpretDisplayedTime(session.startTime, as: sourceTimeZone)
        let end = reinterpretDisplayedTime(session.endTime, as: sourceTimeZone)
        return DateInterval(start: start, end: max(end, start.addingTimeInterval(900)))
    }

    private func reinterpretDisplayedTime(_ date: Date, as sourceTimeZone: TimeZone) -> Date {
        let displayedComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        return sourceCalendar.date(from: displayedComponents) ?? date
    }

    private func applyCorrection() {
        guard TimeZone(identifier: sourceTimeZoneID) != nil else {
            errorMessage = "Fuseau source invalide."
            return
        }
        for session in likelyImportedSessions where selectedSessionIDs.contains(session.id) {
            guard let corrected = correctedInterval(for: session) else { continue }
            session.startTime = corrected.start
            session.endTime = corrected.end
            session.date = Calendar.current.startOfDay(for: corrected.start)
            session.updatedAt = .now
            let marker = "Fuseau source corrigé : \(sourceTimeZoneID)"
            if !session.sessionDescription.contains(marker) {
                session.sessionDescription = [session.sessionDescription, marker].filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Correction impossible : \(error.localizedDescription)"
        }
    }
}

enum CalendarOrganizationAnalyzer {
    static func proposals(for source: CalendarOrganizationSource, courses: [Course], existingSessions: [ClassSession]) -> [CalendarCourseProposal] {
        switch source {
        case .calendarEvents(let events):
            return proposals(for: events, courses: courses, existingSessions: existingSessions)
        case .existingSessions(let sessions):
            return proposals(forSessions: sessions, courses: courses, existingSessions: existingSessions)
        }
    }

    static func proposals(for events: [CalendarImportEvent], courses: [Course], existingSessions: [ClassSession]) -> [CalendarCourseProposal] {
        let grouped = Dictionary(grouping: events) { normalizedCourseTitle($0.title) }
        return grouped.map { key, group in
            makeProposal(key: key, events: group.sorted { $0.startDate < $1.startDate }, sessions: [], courses: courses, existingSessions: existingSessions)
        }
        .sorted { $0.proposedName.localizedStandardCompare($1.proposedName) == .orderedAscending }
    }

    private static func proposals(forSessions sessions: [ClassSession], courses: [Course], existingSessions: [ClassSession]) -> [CalendarCourseProposal] {
        let grouped = Dictionary(grouping: sessions) { normalizedCourseTitle($0.title) }
        return grouped.map { key, group in
            makeProposal(key: key, events: [], sessions: group.sorted { $0.startTime < $1.startTime }, courses: courses, existingSessions: existingSessions)
        }
        .sorted { $0.proposedName.localizedStandardCompare($1.proposedName) == .orderedAscending }
    }

    static func summary(for proposals: [CalendarCourseProposal], existingSessions: [ClassSession]) -> CalendarOrganizationSummary {
        CalendarOrganizationSummary(
            coursesToCreate: proposals.filter { $0.action == .createCourse }.count,
            sessionsToAttach: proposals.reduce(0) { partial, proposal in
                guard proposal.action == .createCourse || proposal.action == .linkExisting else { return partial }
                return partial + proposal.events.filter { !isDuplicate($0, existingSessions: existingSessions) }.count + proposal.sessions.count
            },
            unfiledEvents: proposals.reduce(0) { partial, proposal in
                proposal.action == .keepUnfiled ? partial + proposal.events.count + proposal.sessions.count : partial
            },
            duplicatesIgnored: proposals.reduce(0) { partial, proposal in
                partial + proposal.events.filter { isDuplicate($0, existingSessions: existingSessions) }.count
            }
        )
    }

    @MainActor
    static func saveCalendarImport(_ proposals: [CalendarCourseProposal], courses: [Course], existingSessions: [ClassSession], in context: ModelContext) throws {
        for proposal in proposals where proposal.action != .ignore {
            let course = try courseForProposal(proposal, courses: courses, in: context)
            var importedOffset = 0
            for event in proposal.events where !isDuplicate(event, existingSessions: existingSessions) {
                let session = ClassSession(
                    number: nextSessionNumber(for: course, importedOffset: importedOffset),
                    title: event.title,
                    sessionDescription: importNotes(for: event),
                    date: Calendar.current.startOfDay(for: event.startDate),
                    startTime: event.startDate,
                    endTime: event.endDate,
                    room: event.location?.emptyAsNil ?? proposal.proposedRoom.emptyAsNil,
                    professorName: proposal.proposedProfessor.emptyAsNil,
                    course: course
                )
                context.insert(session)
                importedOffset += 1
            }
        }
        try context.save()
    }

    @MainActor
    static func organizeExistingSessions(_ proposals: [CalendarCourseProposal], courses: [Course], existingSessions: [ClassSession], in context: ModelContext) throws {
        for proposal in proposals where proposal.action != .ignore {
            let course = try courseForProposal(proposal, courses: courses, in: context)
            for sessionID in proposal.sourceSessionIDs {
                guard let session = existingSessions.first(where: { $0.id == sessionID }) else { continue }
                session.course = course
                if session.room == nil {
                    session.room = proposal.proposedRoom.emptyAsNil
                }
                if session.professorName == nil {
                    session.professorName = proposal.proposedProfessor.emptyAsNil
                }
                session.updatedAt = .now
            }
        }
        try context.save()
    }

    private static func makeProposal(key: String, events: [CalendarImportEvent], sessions: [ClassSession], courses: [Course], existingSessions: [ClassSession]) -> CalendarCourseProposal {
        let titles = events.map(\.title) + sessions.map(\.title)
        let firstTitle = titles.first ?? key
        let code = extractedCode(from: firstTitle)
        let cleanName = cleanedCourseName(firstTitle)
        let rooms = (events.compactMap(\.location) + sessions.compactMap(\.room)).filter { !$0.isEmpty }
        let professor = extractedProfessor(from: events.map(\.notes).joined(separator: "\n")) ?? sessions.compactMap(\.professorName).first ?? ""
        let dates = events.map(\.startDate) + sessions.map(\.startTime)
        let matchingCourse = courses.first { course in
            normalizedCourseTitle(course.name) == key || (!code.isEmpty && course.code.localizedCaseInsensitiveCompare(code) == .orderedSame)
        }
        let count = events.count + sessions.count
        var warnings: [String] = []
        if count == 1 {
            warnings.append("Événement ponctuel : UniSaver ne déduit pas un semestre entier d’une seule occurrence.")
        }
        if events.contains(where: { $0.recurrenceNote != nil }) {
            warnings.append("Récurrence RRULE signalée : seules les occurrences présentes/interprétées sont utilisées.")
        }
        if Set(titles.map(normalizedCourseTitle)).count > 1 {
            warnings.append("Intitulés proches regroupés : vérifie que ce n’est pas deux cours différents.")
        }
        let duplicateCount = events.filter { isDuplicate($0, existingSessions: existingSessions) }.count
        if duplicateCount > 0 {
            warnings.append("\(duplicateCount) doublon(s) probable(s) seront ignorés.")
        }
        let evidence = [
            code.isEmpty ? nil : "code \(code)",
            rooms.first.map { "salle \($0)" },
            professor.isEmpty ? nil : "prof. \(professor)",
            count > 1 ? "\(count) occurrences" : nil
        ].compactMap { $0 }
        let confidence = min(0.95, max(0.35, 0.4 + (count > 1 ? 0.25 : 0) + (code.isEmpty ? 0 : 0.15) + (rooms.isEmpty ? 0 : 0.1) + (matchingCourse == nil ? 0 : 0.2)))
        return CalendarCourseProposal(
            sourceEventIDs: events.map(\.id),
            sourceSessionIDs: sessions.map(\.id),
            normalizedTitle: key,
            action: matchingCourse == nil && (count > 1 || !sessions.isEmpty) ? .createCourse : (matchingCourse == nil ? .keepUnfiled : .linkExisting),
            selectedCourseID: matchingCourse?.id,
            proposedName: cleanName,
            proposedCode: code,
            proposedProfessor: professor,
            proposedRoom: mostCommon(rooms) ?? "",
            proposedStartDate: dates.min(),
            proposedEndDate: dates.max(),
            confidence: confidence,
            evidence: evidence.isEmpty ? ["intitulé normalisé"] : evidence,
            warnings: warnings,
            schedules: schedules(events: events, sessions: sessions),
            events: events,
            sessions: sessions
        )
    }

    @MainActor
    private static func courseForProposal(_ proposal: CalendarCourseProposal, courses: [Course], in context: ModelContext) throws -> Course? {
        switch proposal.action {
        case .createCourse:
            let course = Course(
                name: proposal.proposedName.trimmingCharacters(in: .whitespacesAndNewlines),
                code: proposal.proposedCode.trimmingCharacters(in: .whitespacesAndNewlines),
                professorName: proposal.proposedProfessor,
                defaultRoom: proposal.proposedRoom.emptyAsNil,
                colorIdentifier: colorIdentifier(for: proposal.proposedName),
                startDate: proposal.proposedStartDate,
                endDate: proposal.proposedEndDate
            )
            context.insert(course)
            return course
        case .linkExisting:
            return courses.first { $0.id == proposal.selectedCourseID }
        case .keepUnfiled:
            return nil
        case .ignore:
            return nil
        }
    }

    private static func nextSessionNumber(for course: Course?, importedOffset: Int) -> Int {
        (course?.sessions.map(\.number).max() ?? 0) + importedOffset + 1
    }

    private static func importNotes(for event: CalendarImportEvent) -> String {
        let metadata = "Import calendrier : source \(event.sourceTimeDescription), affiché \(event.deviceTimeDescription)"
        return [event.notes, metadata].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private nonisolated static func isDuplicate(_ event: CalendarImportEvent, existingSessions: [ClassSession]) -> Bool {
        existingSessions.contains { session in
            normalizedCourseTitle(session.title) == normalizedCourseTitle(event.title) &&
            abs(session.startTime.timeIntervalSince(event.startDate)) < 60
        }
    }

    nonisolated static func normalizedCourseTitle(_ title: String) -> String {
        cleanedCourseName(title)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    nonisolated static func cleanedCourseName(_ title: String) -> String {
        title
            .replacingOccurrences(of: #"\s*\([^)]*\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b[A-Z]{2,6}\s*\d{2,4}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func extractedCode(from title: String) -> String {
        guard let range = title.range(of: #"\b[A-Z]{2,6}\s*\d{2,4}\b"#, options: .regularExpression) else { return "" }
        return String(title[range]).replacingOccurrences(of: " ", with: "")
    }

    private nonisolated static func extractedProfessor(from notes: String) -> String? {
        let patterns = ["Professor", "Professeur", "Teacher", "Enseignant"]
        for pattern in patterns {
            if let range = notes.range(of: "\(pattern)\\s*:?\\s*([^\\n]+)", options: [.regularExpression, .caseInsensitive]) {
                let value = String(notes[range]).components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let value, !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func schedules(events: [CalendarImportEvent], sessions: [ClassSession]) -> [String] {
        let dates = events.map { ($0.startDate, $0.endDate) } + sessions.map { ($0.startTime, $0.endTime) }
        let labels = dates.map { start, end in
            "\(start.formatted(.dateTime.weekday(.abbreviated))) \(UniDateFormatters.time.string(from: start))-\(UniDateFormatters.time.string(from: end))"
        }
        return Array(Set(labels)).sorted()
    }

    private nonisolated static func mostCommon(_ values: [String]) -> String? {
        Dictionary(grouping: values, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    private nonisolated static func colorIdentifier(for name: String) -> String {
        let colors = CourseColor.allCases.map(\.rawValue)
        return colors[abs(name.hashValue) % max(colors.count, 1)]
    }
}

enum CalendarICSParser {
    struct ICSField {
        var value: String
        var parameters: [String: String]
        var rawName: String
    }

    struct Result {
        var events: [CalendarImportEvent]
        var errors: [CalendarImportError]
    }

    nonisolated static var suggestedTimeZoneIdentifiers: [String] {
        let preferred = [TimeZone.current.identifier, "Europe/Madrid", "Africa/Casablanca", "UTC"]
        return Array(NSOrderedSet(array: preferred + TimeZone.knownTimeZoneIdentifiers)) as? [String] ?? preferred
    }

    nonisolated static func parse(_ text: String, defaultFloatingTimeZone: TimeZone = .current) -> Result {
        let lines = unfold(text)
        var events: [CalendarImportEvent] = []
        var errors: [CalendarImportError] = []
        var current: [String: ICSField]?
        var eventStartLine = 1

        for (index, line) in lines.enumerated() {
            if line == "BEGIN:VEVENT" {
                current = [:]
                eventStartLine = index + 1
                continue
            }
            if line == "END:VEVENT" {
                if let current {
                    switch makeEvent(current, line: eventStartLine, defaultFloatingTimeZone: defaultFloatingTimeZone) {
                    case .success(let event):
                        events.append(event)
                    case .failure(let error):
                        errors.append(error)
                    }
                }
                current = nil
                continue
            }
            guard current != nil else { continue }
            guard let property = parseProperty(line) else {
                errors.append(CalendarImportError(line: index + 1, message: "Ligne VEVENT illisible."))
                continue
            }
            current?[property.rawName.uppercased()] = property
        }
        return Result(events: events, errors: errors)
    }

    private nonisolated static func makeEvent(_ fields: [String: ICSField], line: Int, defaultFloatingTimeZone: TimeZone = .current) -> Swift.Result<CalendarImportEvent, CalendarImportError> {
        guard let title = fields["SUMMARY"]?.value, !title.isEmpty else {
            return .failure(CalendarImportError(line: line, message: "Résumé manquant."))
        }
        guard let startField = fields["DTSTART"], let startInfo = parseDate(startField, defaultFloatingTimeZone: defaultFloatingTimeZone) else {
            return .failure(CalendarImportError(line: line, message: "Date de début invalide ou manquante."))
        }
        let endInfo = fields["DTEND"].flatMap { parseDate($0, defaultFloatingTimeZone: defaultFloatingTimeZone) }
        let end = endInfo?.date ?? startInfo.date.addingTimeInterval(3600)
        let recurrence = fields["RRULE"].map { "Récurrence détectée (\($0.value)). Import de l’occurrence de départ uniquement." }
        return .success(CalendarImportEvent(
            title: title,
            startDate: startInfo.date,
            endDate: max(end, startInfo.date.addingTimeInterval(900)),
            sourceStartText: startField.value,
            sourceEndText: fields["DTEND"]?.value ?? "",
            sourceTimeZoneIdentifier: startInfo.timeZoneIdentifier,
            isFloatingTime: startInfo.isFloating,
            location: fields["LOCATION"]?.value,
            notes: fields["DESCRIPTION"]?.value ?? "",
            recurrenceNote: recurrence
        ))
    }

    private nonisolated static func parseProperty(_ line: String) -> ICSField? {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let nameAndParameters = parts[0].split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let rawName = nameAndParameters.first else { return nil }
        var parameters: [String: String] = [:]
        for parameter in nameAndParameters.dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            parameters[String(pair[0]).uppercased()] = String(pair[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return ICSField(value: unescape(String(parts[1])), parameters: parameters, rawName: rawName)
    }

    private struct ParsedDate {
        var date: Date
        var timeZoneIdentifier: String?
        var isFloating: Bool
    }

    private nonisolated static func parseDate(_ field: ICSField, defaultFloatingTimeZone: TimeZone) -> ParsedDate? {
        let cleaned = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitTZID = field.parameters["TZID"]
        let valueType = field.parameters["VALUE"]?.uppercased()
        let isDateOnly = valueType == "DATE" || !cleaned.contains("T")
        let isUTC = cleaned.hasSuffix("Z")
        let timeZone: TimeZone
        let timeZoneIdentifier: String?
        let isFloating: Bool
        if isUTC {
            timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            timeZoneIdentifier = "UTC"
            isFloating = false
        } else if let explicitTZID, let zone = TimeZone(identifier: explicitTZID) {
            timeZone = zone
            timeZoneIdentifier = explicitTZID
            isFloating = false
        } else {
            timeZone = defaultFloatingTimeZone
            timeZoneIdentifier = defaultFloatingTimeZone.identifier
            isFloating = explicitTZID == nil
        }
        let value = isUTC ? String(cleaned.dropLast()) : cleaned
        let formats = isDateOnly ? ["yyyyMMdd"] : ["yyyyMMdd'T'HHmmss", "yyyyMMdd'T'HHmm"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = timeZone
            if let date = formatter.date(from: value) {
                return ParsedDate(date: date, timeZoneIdentifier: timeZoneIdentifier, isFloating: isFloating)
            }
        }
        return nil
    }

    private nonisolated static func unfold(_ text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if rawLine.first == " " || rawLine.first == "\t", !result.isEmpty {
                result[result.count - 1] += rawLine.dropFirst()
            } else {
                result.append(rawLine.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return result
    }

    private nonisolated static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
    }
}
