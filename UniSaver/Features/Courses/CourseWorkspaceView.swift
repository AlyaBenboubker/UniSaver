import SwiftData
import SwiftUI

enum CourseWorkspaceTab: String, CaseIterable, Identifiable {
    case overview
    case chapters
    case sessions
    case resources
    case notes
    case study
    case assignments
    case progress

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
                case .resources, .notes, .study, .assignments, .progress:
                    EmptyStateView(title: "\(tab.title) is planned", message: "This area is reserved for the relevant future lot and has no inactive controls in this build.", systemImage: "clock.badge")
                }
            }
        }
        .navigationTitle(course.name)
        .toolbar {
            ToolbarItemGroup {
                Button("Edit", systemImage: "pencil") { editingCourse = true }
                Menu {
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
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editingCourse) {
            CourseFormView(course: course)
        }
        .confirmationDialog("Archive this course?", isPresented: $archiveConfirmation) {
            Button(course.isArchived ? "Restore Course" : "Archive Course") {
                course.isArchived.toggle()
                course.updatedAt = .now
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archiving keeps chapters and sessions available without showing this course in active lists.")
        }
        .confirmationDialog("Delete this course?", isPresented: $deleteConfirmation) {
            Button("Delete Course", role: .destructive) {
                modelContext.delete(course)
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
                .frame(width: 76, height: 96)
                .overlay {
                    Image(systemName: course.symbolName ?? "book.closed")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(course.name)
                    .font(.title2.weight(.bold))
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

    private var currentChapter: Chapter? {
        course.chapters.filter { !$0.isArchived && $0.status != .mastered }.sorted { $0.order < $1.order }.first
    }

    private var recentSessions: [ClassSession] {
        course.sessions.filter { $0.startTime < .now }.sorted { $0.startTime > $1.startTime }.prefix(3).map(\.self)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                infoCard("Current chapter", value: currentChapter?.title ?? "None", systemImage: "list.number")
                infoCard("Next session", value: nextSession?.title ?? "None scheduled", systemImage: "calendar")
                infoCard("Chapters", value: "\(course.chapters.filter { !$0.isArchived }.count)", systemImage: "number")
                VStack(alignment: .leading, spacing: 12) {
                    Label("Structural progress", systemImage: "chart.bar")
                    ProgressMeter(value: AcademicValidationService.courseStructuralProgress(course))
                    Text("This is workflow progress, not an academic mastery score.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .deskCard()
            }
            .padding()

            VStack(alignment: .leading, spacing: 12) {
                Text("Recent sessions")
                    .font(.headline)
                if recentSessions.isEmpty {
                    Text("No completed session history yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentSessions) { SessionRow(session: $0) }
                }
            }
            .padding()
            .deskCard()
            .padding(.horizontal)

            HStack {
                Button("New Chapter", systemImage: "list.number") { quickAddTarget = .chapter(course) }
                Button("New Session", systemImage: "calendar.badge.plus") { quickAddTarget = .session(course, nil) }
            }
            .buttonStyle(.bordered)
            .padding()
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
}
