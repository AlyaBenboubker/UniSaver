import SwiftData
import SwiftUI

enum ClassDisplayMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ClassFilter: String, CaseIterable, Identifiable {
    case active
    case review
    case archived
    case all

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ClassesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \ClassSession.startTime) private var sessions: [ClassSession]
    @Query(sort: \Semester.order) private var semesters: [Semester]
    @Binding var quickAddTarget: QuickAddTarget?

    @State private var searchText = ""
    @State private var displayMode: ClassDisplayMode = .grid
    @State private var filter: ClassFilter = .active
    @State private var selectedCourse: Course?
    @State private var selectedSemesterID: UUID?
    @State private var editingCourse: Course?
    @State private var archiveCourse: Course?
    @State private var deleteCourse: Course?
    @State private var moodleCourseIDs: Set<UUID> = []
    @State private var showsImportedOrganizer = false

    private var filteredCourses: [Course] {
        courses.filter { course in
            let matchesSearch = searchText.isEmpty
                || course.name.localizedStandardContains(searchText)
                || course.code.localizedStandardContains(searchText)
                || course.professorName.localizedStandardContains(searchText)
            let matchesFilter: Bool
            switch filter {
            case .active: matchesFilter = !course.isArchived
            case .review: matchesFilter = !course.isArchived && course.status == .needsReview
            case .archived: matchesFilter = course.isArchived
            case .all: matchesFilter = true
            }
            let matchesSemester = selectedSemesterID == nil || course.semester?.id == selectedSemesterID
            return matchesSearch && matchesFilter && matchesSemester
        }
    }

    private var selectedSemester: Semester? {
        if let selectedSemesterID {
            return semesters.first { $0.id == selectedSemesterID }
        }
        return semesters.first { $0.status == .active } ?? semesters.first
    }

    var body: some View {
        Group {
            if courses.isEmpty {
                VStack(spacing: 14) {
                    EmptyStateView(
                        title: "Aucun cours pour l’instant",
                        message: "Crée ton premier cours ou organise les événements importés depuis Planner.",
                        systemImage: "books.vertical",
                        actionTitle: "Nouveau cours",
                        action: { quickAddTarget = .course(nil) }
                    )
                    Button("Organiser les événements importés", systemImage: "wand.and.stars") {
                        showsImportedOrganizer = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sessions.allSatisfy { $0.course != nil })
                }
            } else {
                GeometryReader { proxy in
                    let layoutMode = StudyDeskLayoutMode(contentWidth: proxy.size.width)
                    courseCollection(layoutMode: layoutMode)
                }
            }
        }
        .navigationTitle("Classes")
        .searchable(text: $searchText, prompt: "Search classes")
        .navigationDestination(item: courseNavigationBinding) { target in
            if let course = courses.first(where: { $0.id == target.id }) {
                CourseWorkspaceView(course: course, quickAddTarget: $quickAddTarget)
                    .environment(navigation)
            } else {
                EmptyStateView(title: "Course unavailable", message: "This course was removed or is no longer available in the current workspace.", systemImage: "exclamationmark.triangle")
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Semester", selection: $selectedSemesterID) {
                    Text("All semesters").tag(UUID?.none)
                    ForEach(semesters) { semester in
                        Text(semester.name).tag(Optional(semester.id))
                    }
                }
                Picker("Filter", selection: $filter) {
                    ForEach([ClassFilter.active, .archived, .all]) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                Picker("View", selection: $displayMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(ClassDisplayMode.grid)
                    Label("List", systemImage: "list.bullet").tag(ClassDisplayMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Button("New Course", systemImage: "plus") {
                    quickAddTarget = .course(selectedSemester)
                }
                Button("Organiser", systemImage: "wand.and.stars") {
                    showsImportedOrganizer = true
                }
                .disabled(sessions.allSatisfy { $0.course != nil })
            }
        }
        .sheet(isPresented: $showsImportedOrganizer) {
            CalendarOrganizationSheet(
                title: "Organiser les événements importés",
                source: .existingSessions(sessions.filter { $0.course == nil }),
                courses: courses,
                existingSessions: sessions
            )
        }
        .background(Color.studyDeskBackground)
        .onReceive(NotificationCenter.default.publisher(for: .courseCreated)) { notification in
            if let course = notification.object as? Course {
                selectedCourse = course
                navigation.openCourse(course)
                selectedSemesterID = course.semester?.id
            }
        }
        .onAppear {
            selectedSemesterID = selectedSemesterID ?? selectedSemester?.id
        }
    }

    private var activeSemesterTitle: String {
        semesters.first(where: { $0.status == .active })?.name ?? "No active semester"
    }

    private func courseCollection(layoutMode: StudyDeskLayoutMode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layoutMode.cardSpacing) {
                SemesterSummaryBand(semester: selectedSemester, courses: filteredCourses)

                if filteredCourses.count < 2 {
                    GettingStartedClassesPanel(course: filteredCourses.first, quickAddTarget: $quickAddTarget)
                }

                if filteredCourses.isEmpty {
                    EmptyStateView(title: "Nothing matches", message: "Adjust search or filter to find a class.", systemImage: "line.3.horizontal.decrease.circle")
                        .frame(minHeight: 300)
                } else if displayMode == .grid {
                    LazyVGrid(columns: gridColumns(for: layoutMode), spacing: layoutMode.cardSpacing) {
                        ForEach(filteredCourses) { course in
                            Button {
                                openCourse(course)
                            } label: {
                                CourseBinderCard(course: course, isSelected: selectedCourse?.id == course.id, isCompact: layoutMode != .wide, isMoodleImported: moodleCourseIDs.contains(course.id))
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("courseCard_\(course.id.uuidString)")
                            .accessibilityLabel("Open \(course.name)")
                            .contextMenu {
                                courseMenu(course)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredCourses) { course in
                            Button {
                                openCourse(course)
                            } label: {
                                CourseListRow(course: course, isMoodleImported: moodleCourseIDs.contains(course.id))
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("courseCard_\(course.id.uuidString)")
                            .accessibilityLabel("Open \(course.name)")
                            .contextMenu {
                                courseMenu(course)
                            }
                        }
                    }
                }
            }
            .padding(layoutMode.outerPadding)
        }
        .onAppear {
            selectedCourse = selectedCourse ?? filteredCourses.first
            moodleCourseIDs = MoodleSyncMetadataStore().remoteIDs(kind: .course)
        }
        .sheet(item: $editingCourse) { course in
            CourseFormView(mode: .edit(course))
        }
        .confirmationDialog("Archive course?", isPresented: Binding(
            get: { archiveCourse != nil },
            set: { if !$0 { archiveCourse = nil } }
        )) {
            if let archiveCourse {
                Button(archiveCourse.isArchived ? "Unarchive Course" : "Archive Course") {
                    archiveCourse.isArchived.toggle()
                    archiveCourse.updatedAt = .now
                    try? modelContext.save()
                    self.archiveCourse = nil
                }
            }
            Button("Cancel", role: .cancel) { archiveCourse = nil }
        } message: {
            Text("Archiving keeps chapters and sessions but removes the course from Active.")
        }
        .confirmationDialog("Delete course?", isPresented: Binding(
            get: { deleteCourse != nil },
            set: { if !$0 { deleteCourse = nil } }
        )) {
            if let deleteCourse {
                Button("Delete Course", role: .destructive) {
                    modelContext.delete(deleteCourse)
                    try? modelContext.save()
                    self.deleteCourse = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteCourse = nil }
        } message: {
            Text(deleteCourse.map { AcademicValidationService.shouldPreferArchive(course: $0) } == true ? "This course has associated data. Archive is safer unless you are certain." : "This cannot be undone.")
        }
    }

    @ViewBuilder
    private func courseMenu(_ course: Course) -> some View {
        Button("Open Course", systemImage: "arrow.right") {
            openCourse(course)
        }
        Button("Edit Course", systemImage: "pencil") {
            editingCourse = course
        }
        Button(course.isArchived ? "Unarchive Course" : "Archive Course", systemImage: "archivebox") {
            archiveCourse = course
        }
        Button("Delete Course", systemImage: "trash", role: .destructive) {
            deleteCourse = course
        }
    }

    private func gridColumns(for layoutMode: StudyDeskLayoutMode) -> [GridItem] {
        switch layoutMode {
        case .wide:
            [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: StudyDeskTheme.spacing)]
        case .tabletExpanded:
            [GridItem(.flexible(minimum: 250), spacing: 14), GridItem(.flexible(minimum: 250), spacing: 14)]
        case .medium:
            [GridItem(.flexible(minimum: 250), spacing: 14), GridItem(.flexible(minimum: 250), spacing: 14)]
        case .compact:
            [GridItem(.flexible(minimum: 260), spacing: 12)]
        }
    }

    private func openCourse(_ course: Course) {
        selectedCourse = course
        navigation.openCourse(course)
    }

    private var courseNavigationBinding: Binding<CourseNavigationTarget?> {
        Binding {
            guard navigation.selectedSection == .classes,
                  let openedCourseID = navigation.openedCourseID else {
                return nil
            }
            return CourseNavigationTarget(id: openedCourseID)
        } set: { target in
            navigation.openedCourseID = target?.id
            if target == nil {
                navigation.requestedCourseTab = nil
            }
        }
    }
}

private struct CourseNavigationTarget: Identifiable, Hashable {
    let id: UUID
}

struct SemesterSummaryBand: View {
    let semester: Semester?
    let courses: [Course]

    private var upcomingSessions: [ClassSession] {
        courses.flatMap(\.sessions).filter { $0.startTime >= .now }.sorted { $0.startTime < $1.startTime }
    }

    private var totalSessions: Int {
        courses.reduce(0) { $0 + $1.sessions.count }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(semester?.name ?? "All semesters")
                        .font(.headline)
                    if let semester {
                        Text("\(UniDateFormatters.dayMonth.string(from: semester.startDate)) - \(UniDateFormatters.dayMonth.string(from: semester.endDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                metric("Matières", "\(courses.count)", "books.vertical")
                metric("Séances", "\(totalSessions)", "calendar")
                metric("À venir", "\(upcomingSessions.count)", "clock")
                Button("Manage", systemImage: "slider.horizontal.3") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .help("Semester management arrives in a later lot.")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(semester?.name ?? "All semesters")
                        .font(.headline)
                    Spacer()
                    Text("\(courses.count) courses")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text("\(upcomingSessions.count) séances à venir sur \(totalSessions) séances enregistrées.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .deskCard()
    }

    private func metric(_ title: String, _ value: String, _ systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(StudyDeskTheme.accentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GettingStartedClassesPanel: View {
    let course: Course?
    @Binding var quickAddTarget: QuickAddTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Getting Started")
                    .font(.headline)
                Spacer()
                #if DEBUG
                Button("Explore Sample Semester", systemImage: "sparkles") {
                    NotificationCenter.default.post(name: .loadDemoWorkspace, object: nil)
                }
                .buttonStyle(.bordered)
                #endif
            }
            VStack(alignment: .leading, spacing: 8) {
                actionRow(number: 1, title: "Add syllabus information", systemImage: "doc.text", action: {
                    quickAddTarget = .course(nil)
                })
                actionRow(number: 2, title: "Create first chapter", systemImage: "list.number", action: {
                    quickAddTarget = .chapter(course)
                }, isDisabled: course == nil)
                actionRow(number: 3, title: "Schedule first session", systemImage: "calendar.badge.plus", action: {
                    quickAddTarget = .session(course, nil)
                }, isDisabled: course == nil)
            }
        }
        .padding()
        .deskCard()
    }

    private func actionRow(number: Int, title: String, systemImage: String, action: @escaping () -> Void, isDisabled: Bool = false) -> some View {
        Button(action: action) {
            HStack {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(StudyDeskTheme.surfaceTinted, in: Circle())
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(isDisabled ? "Create or select a course first." : title)
    }
}

struct HSplitLikeLayout<Content: View, Trailing: View>: View {
    let contentWidth: CGFloat
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    var body: some View {
        if contentWidth >= 980 {
            HStack(spacing: 0) {
                content
                Divider()
                trailing
                    .frame(minWidth: 330, idealWidth: 360, maxWidth: 420)
                    .background(StudyDeskTheme.backgroundSecondary)
            }
        } else {
            content
        }
    }
}
