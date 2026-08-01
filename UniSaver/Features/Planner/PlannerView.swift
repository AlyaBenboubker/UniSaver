import SwiftData
import SwiftUI

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
                matchesFilter = task.dueDate > Date() && task.status != .completed
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

struct PlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \Course.name) private var courses: [Course]
    @State private var filter: PlannerTaskFilter = .open
    @State private var sort: PlannerTaskSort = .dueDate
    @State private var searchText = ""
    @State private var selectedCourseID: UUID?
    @State private var editingTask: AcademicTask?
    @State private var deletingTask: AcademicTask?
    @State private var creatingTask = false

    init(initialFilter: PlannerTaskFilter = .open) {
        _filter = State(initialValue: initialFilter)
    }

    private var visibleTasks: [AcademicTask] {
        PlannerTaskQuery.sortedTasks(
            PlannerTaskQuery.filteredTasks(tasks, filter: filter, searchText: searchText, courseID: selectedCourseID),
            sort: sort
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            List {
                if visibleTasks.isEmpty {
                    EmptyStateView(title: "No tasks", message: "Create a task or adjust the filters.", systemImage: "checklist", actionTitle: "New Task") {
                        creatingTask = true
                    }
                } else {
                    ForEach(visibleTasks) { task in
                        Button {
                            editingTask = task
                        } label: {
                            PlannerTaskRow(task: task)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("taskRow_\(task.id.uuidString)")
                        .contextMenu {
                            Button(task.status == .completed ? "Reopen" : "Complete") {
                                task.status = task.status == .completed ? .todo : .completed
                                task.updatedAt = .now
                                try? modelContext.save()
                            }
                            Button("Edit") { editingTask = task }
                            Button("Delete", role: .destructive) { deletingTask = task }
                        }
                    }
                }
            }
            .accessibilityIdentifier("tasksDestination")
        }
        .navigationTitle("Planner")
        .background(StudyDeskTheme.backgroundPrimary)
        .toolbar {
            ToolbarItem {
                Button("New Task", systemImage: "plus") { creatingTask = true }
            }
        }
        .sheet(isPresented: $creatingTask) {
            TaskFormView()
        }
        .sheet(item: $editingTask) { task in
            TaskFormView(task: task)
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
        .onReceive(NotificationCenter.default.publisher(for: .openPlannerTasks)) { notification in
            if let incoming = notification.object as? PlannerTaskFilter {
                filter = incoming
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Task filter", selection: $filter) {
                ForEach(PlannerTaskFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tasks", text: $searchText)
                    .textFieldStyle(.plain)
                Picker("Course", selection: $selectedCourseID) {
                    Text("All courses").tag(UUID?.none)
                    ForEach(courses.filter { !$0.isArchived }) { course in
                        Text(course.name).tag(Optional(course.id))
                    }
                }
                Picker("Sort", selection: $sort) {
                    ForEach(PlannerTaskSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
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
}

private struct PlannerTaskRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: AcademicTask

    var body: some View {
        HStack(spacing: 12) {
            Button {
                task.status = task.status == .completed ? .todo : .completed
                task.updatedAt = .now
                try? modelContext.save()
            } label: {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(task.status == .completed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.status == .completed)
                Text([task.course?.name, UniDateFormatters.dayMonth.string(from: task.dueDate), task.priority.title].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(task.status.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(StudyDeskTheme.surfaceTinted, in: Capsule())
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
