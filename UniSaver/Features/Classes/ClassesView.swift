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
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Semester.order) private var semesters: [Semester]
    @Binding var quickAddTarget: QuickAddTarget?

    @State private var searchText = ""
    @State private var displayMode: ClassDisplayMode = .grid
    @State private var filter: ClassFilter = .active
    @State private var selectedCourse: Course?

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
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        Group {
            if courses.isEmpty {
                EmptyStateView(
                    title: "No classes yet",
                    message: "Add your first class to start organizing chapters and dated sessions.",
                    systemImage: "books.vertical",
                    actionTitle: "New Course",
                    action: { quickAddTarget = .course(nil) }
                )
            } else {
                HSplitLikeLayout {
                    courseCollection
                } trailing: {
                    if let selectedCourse {
                        CoursePreviewPane(course: selectedCourse)
                    } else {
                        EmptyStateView(title: "Select a class", message: "Choose a binder to inspect its chapters, sessions, and structural progress.", systemImage: "rectangle.stack")
                    }
                }
            }
        }
        .navigationTitle("Classes")
        .searchable(text: $searchText, prompt: "Search classes")
        .toolbar {
            ToolbarItemGroup {
                Picker("Filter", selection: $filter) {
                    ForEach(ClassFilter.allCases) { filter in
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
                    quickAddTarget = .course(nil)
                }
            }
        }
        .background(Color.studyDeskBackground)
    }

    private var activeSemesterTitle: String {
        semesters.first(where: { $0.status == .active })?.name ?? "No active semester"
    }

    private var courseCollection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(activeSemesterTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if filteredCourses.isEmpty {
                    EmptyStateView(title: "Nothing matches", message: "Adjust search or filter to find a class.", systemImage: "line.3.horizontal.decrease.circle")
                        .frame(minHeight: 300)
                } else if displayMode == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                        ForEach(filteredCourses) { course in
                            NavigationLink {
                                CourseWorkspaceView(course: course, quickAddTarget: $quickAddTarget)
                            } label: {
                                CourseBinderCard(course: course, isSelected: selectedCourse?.id == course.id)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded { selectedCourse = course })
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredCourses) { course in
                            NavigationLink {
                                CourseWorkspaceView(course: course, quickAddTarget: $quickAddTarget)
                            } label: {
                                CourseListRow(course: course)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded { selectedCourse = course })
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            selectedCourse = selectedCourse ?? filteredCourses.first
        }
    }
}

struct HSplitLikeLayout<Content: View, Trailing: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ViewThatFits {
            HStack(spacing: 0) {
                content
                Divider()
                trailing
                    .frame(width: 320)
                    .background(.regularMaterial)
            }
            content
        }
    }
}
