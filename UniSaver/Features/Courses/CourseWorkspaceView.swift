import SwiftData
import SwiftUI

enum CourseWorkspaceTab: String, CaseIterable, Identifiable {
    case overview
    case chapters
    case sessions
    case resources
    case notes
    case study

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct CourseWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var tab: CourseWorkspaceTab = .overview
    @State private var editingCourse = false
    @State private var deleteConfirmation = false
    @State private var archiveConfirmation = false

    private var visibleChapters: [Chapter] {
        course.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order }
    }

    private var sortedSessions: [ClassSession] {
        course.sessions.sorted { $0.startTime < $1.startTime }
    }

    private var nextSession: ClassSession? {
        sortedSessions.first { $0.startTime >= .now }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Section", selection: $tab) {
                ForEach(CourseWorkspaceTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .bottom])

            Group {
                switch tab {
                case .overview:
                    CourseOverviewView(course: course, nextSession: nextSession, quickAddTarget: $quickAddTarget)
                case .chapters:
                    ChapterListView(course: course, quickAddTarget: $quickAddTarget)
                case .sessions:
                    SessionListView(course: course, quickAddTarget: $quickAddTarget)
                case .resources:
                    FutureCourseAreaView(title: "Resources", message: "PDF reader and file imports arrive in the Resources lot.", systemImage: "doc.richtext")
                case .notes:
                    FutureCourseAreaView(title: "Notes", message: "Rich notes, PencilKit and autosave arrive in the Notes lot.", systemImage: "note.text")
                case .study:
                    FutureCourseAreaView(title: "Study", message: "Flashcards, quizzes and spaced repetition arrive in Study Studio.", systemImage: "rectangle.stack.badge.play")
                }
            }
            .id(tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .navigationTitle(course.name)
        .toolbar {
            ToolbarItemGroup {
                Button("Edit Course", systemImage: "pencil") { editingCourse = true }
                    .help("Edit course identity and appearance")
                Menu {
                    Button("Edit Course", systemImage: "pencil") { editingCourse = true }
                    Divider()
                    Button("New Chapter", systemImage: "list.number") { quickAddTarget = .chapter(course) }
                    Button("New Session", systemImage: "calendar.badge.plus") { quickAddTarget = .session(course, nil) }
                    Divider()
                    Button(course.isArchived ? "Restore" : "Archive", systemImage: "archivebox") {
                        archiveConfirmation = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleteConfirmation = true
                    }
                } label: {
                    Label("Course Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editingCourse) {
            CourseFormView(mode: .edit(course))
        }
        .confirmationDialog("Archive this course?", isPresented: $archiveConfirmation) {
            Button(course.isArchived ? "Restore Course" : "Archive Course") {
                course.isArchived.toggle()
                course.updatedAt = .now
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archiving keeps chapters and sessions available without showing this course in active lists.")
        }
        .confirmationDialog("Delete this course?", isPresented: $deleteConfirmation) {
            Button("Delete Course", role: .destructive) {
                modelContext.delete(course)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AcademicValidationService.shouldPreferArchive(course: course) ? "This course has associated data. Archive is safer unless you are certain." : "This cannot be undone.")
        }
        .background(Color.studyDeskBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CourseColor.color(for: course.colorIdentifier).gradient)
                .frame(width: 64, height: 78)
                .overlay {
                    Image(systemName: CourseIconCatalog.sanitizedSymbolName(course.symbolName))
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(course.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                Text([course.code, course.professorName, course.semester?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                if let nextSession {
                    Text("Next: \(nextSession.title), \(UniDateFormatters.dayMonth.string(from: nextSession.date)) \(UniDateFormatters.interval(nextSession.startTime, nextSession.endTime))")
                        .font(.callout)
                }
                ProgressMeter(value: AcademicValidationService.courseStructuralProgress(course))
            }
            Spacer()
        }
        .padding()
    }
}

struct CourseOverviewView: View {
    let course: Course
    let nextSession: ClassSession?
    @Binding var quickAddTarget: QuickAddTarget?
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \ReadingProgress.lastOpenedAt, order: .reverse) private var readings: [ReadingProgress]

    private var currentChapter: Chapter? {
        course.chapters.filter { !$0.isArchived && $0.status != .mastered }.sorted { $0.order < $1.order }.first
    }

    private var recentSessions: [ClassSession] {
        course.sessions.filter { $0.startTime < .now }.sorted { $0.startTime > $1.startTime }.prefix(3).map(\.self)
    }

    private var upcomingSessions: [ClassSession] {
        course.sessions.filter { $0.startTime >= .now }.sorted { $0.startTime < $1.startTime }.prefix(4).map(\.self)
    }

    private var courseTasks: [AcademicTask] {
        tasks.filter { $0.course?.id == course.id && $0.status != .completed }.prefix(4).map(\.self)
    }

    private var courseReadings: [ReadingProgress] {
        readings.filter { $0.course?.id == course.id }.prefix(3).map(\.self)
    }

    private var isFreshCourse: Bool {
        course.chapters.isEmpty && course.sessions.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isFreshCourse {
                    CourseGettingStartedView(course: course, quickAddTarget: $quickAddTarget)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    infoCard("Current chapter", value: currentChapter?.title ?? "None", systemImage: "list.number")
                    infoCard("Next session", value: nextSession?.title ?? "None scheduled", systemImage: "calendar")
                    infoCard("Chapters", value: "\(course.chapters.filter { !$0.isArchived }.count)", systemImage: "number")
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Structural progress", systemImage: "chart.bar")
                        ProgressMeter(value: AcademicValidationService.courseStructuralProgress(course))
                        Text("Workflow progress only, not mastery.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .deskCard()
                }

                if !isFreshCourse {
                    overviewSection("Upcoming sessions", empty: "No future sessions yet.") {
                        ForEach(upcomingSessions) { SessionRow(session: $0) }
                    }

                    overviewSection("Recent sessions", empty: "No completed session history yet.") {
                        ForEach(recentSessions) { SessionRow(session: $0) }
                    }

                    overviewSection("Tasks", empty: "No open tasks for this course.") {
                        ForEach(courseTasks) { task in
                            HStack {
                                Text(task.title)
                                Spacer()
                                Text(UniDateFormatters.dayMonth.string(from: task.dueDate))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    overviewSection("Resources", empty: "No resources linked yet.") {
                        ForEach(courseReadings) { reading in
                            HStack {
                                Image(systemName: "doc.richtext")
                                    .foregroundStyle(CourseColor.color(for: reading.coverColorIdentifier))
                                Text(reading.resourceTitle)
                                Spacer()
                                Text("Page \(reading.currentPage)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack {
                    Button("Add Chapter", systemImage: "list.number") { quickAddTarget = .chapter(course) }
                    Button("Add Session", systemImage: "calendar.badge.plus") { quickAddTarget = .session(course, nil) }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
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

    private func overviewSection<Content: View>(_ title: String, empty: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            if isSectionEmpty(title) {
                Text(empty)
                    .foregroundStyle(.secondary)
            } else {
                content()
            }
        }
        .padding()
        .deskCard()
    }

    private func isSectionEmpty(_ title: String) -> Bool {
        switch title {
        case "Upcoming sessions": upcomingSessions.isEmpty
        case "Recent sessions": recentSessions.isEmpty
        case "Tasks": courseTasks.isEmpty
        case "Resources": courseReadings.isEmpty
        default: true
        }
    }
}

struct CourseGettingStartedView: View {
    let course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var editingCourse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your course is ready")
                .font(.headline)
            Text("Add the syllabus, create a chapter, then schedule the first class session.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                gettingStartedRow(1, "Complete course details", "doc.text", action: { editingCourse = true })
                gettingStartedRow(2, "Create first chapter", "list.number", action: { quickAddTarget = .chapter(course) })
                gettingStartedRow(3, "Schedule first session", "calendar.badge.plus", action: { quickAddTarget = .session(course, nil) })
                gettingStartedRow(4, "Add first resource", "doc.richtext", action: {})
                    .disabled(true)
                    .help("PDF reader arrives in the Resources lot.")
            }
        }
        .padding()
        .deskCard()
        .sheet(isPresented: $editingCourse) {
            CourseFormView(mode: .edit(course))
        }
    }

    private func gettingStartedRow(_ number: Int, _ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(StudyDeskTheme.surfaceTinted, in: Circle())
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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
