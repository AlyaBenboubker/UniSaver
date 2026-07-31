import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \ClassSession.startTime) private var sessions: [ClassSession]
    @Binding var quickAddTarget: QuickAddTarget?

    private var activeCourses: [Course] {
        courses.filter { !$0.isArchived && $0.status != .mastered }
    }

    private var todaySessions: [ClassSession] {
        sessions.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.startTime < $1.startTime }
    }

    private var upcomingSessions: [ClassSession] {
        sessions.filter { $0.startTime >= .now }.sorted { $0.startTime < $1.startTime }
    }

    private var reviewChapters: [Chapter] {
        activeCourses.flatMap(\.chapters)
            .filter { !$0.isArchived && $0.status == .needsReview }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if courses.isEmpty {
                    bootstrapState
                } else {
                    nextClassCard
                    scheduleCard
                    HStack(alignment: .top, spacing: 18) {
                        activeCoursesCard
                        reviewCard
                    }
                    quickActions
                }
            }
            .padding()
        }
        .background(Color.studyDeskBackground)
        .navigationTitle("Today")
        .onReceive(NotificationCenter.default.publisher(for: .openQuickAddCourse)) { _ in
            quickAddTarget = .course(nil)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .minimumScaleFactor(0.8)
            Text(UniDateFormatters.fullDate.string(from: .now))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return "\(greeting), Alya"
    }

    private var bootstrapState: some View {
        VStack(spacing: 12) {
            EmptyStateView(
                title: "Build your study desk",
                message: "Create the academic structure first, then add courses, chapters, and dated sessions.",
                systemImage: "graduationcap",
                actionTitle: "Add first course",
                action: { quickAddTarget = .course(nil) }
            )
            HStack {
                Button("Create academic year", systemImage: "calendar.badge.plus") {
                    createDefaultAcademicYear()
                }
                Button("Create semester", systemImage: "calendar") {
                    _ = ensureActiveSemester()
                }
                Button("Add first course", systemImage: "plus") {
                    quickAddTarget = .course(nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
        }
        .deskCard()
    }

    private var nextClassCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Next class", systemImage: "clock")
                .font(.headline)

            if let next = upcomingSessions.first {
                SessionRow(session: next, prominent: true)
            } else {
                Text("No upcoming sessions. Add a dated class to make Today useful.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .deskCard()
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)

            if todaySessions.isEmpty {
                Text("No sessions today.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todaySessions) { session in
                    SessionRow(session: session)
                    if session.id != todaySessions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .deskCard()
    }

    private var activeCoursesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active classes")
                .font(.headline)
            ForEach(activeCourses.prefix(5)) { course in
                HStack {
                    Circle()
                        .fill(CourseColor.color(for: course.colorIdentifier))
                        .frame(width: 10, height: 10)
                    Text(course.name)
                    Spacer()
                    Text(AcademicValidationService.courseStructuralProgress(course), format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .deskCard()
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chapters to review")
                .font(.headline)
            if reviewChapters.isEmpty {
                Text("No chapter is marked for review.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reviewChapters.prefix(5)) { chapter in
                    Text(chapter.title)
                        .font(.callout)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .deskCard()
    }

    private var quickActions: some View {
        HStack {
            Button("New Course", systemImage: "books.vertical") { quickAddTarget = .course(nil) }
            Button("New Chapter", systemImage: "list.number") { quickAddTarget = .chapter(activeCourses.first) }
                .disabled(activeCourses.isEmpty)
            Button("New Session", systemImage: "calendar.badge.plus") { quickAddTarget = .session(activeCourses.first, nil) }
                .disabled(activeCourses.isEmpty)
        }
        .buttonStyle(.bordered)
    }

    private func createDefaultAcademicYear() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: .now), month: 9, day: 1)) ?? .now
        let end = calendar.date(byAdding: .month, value: 10, to: start) ?? start.addingTimeInterval(30_000_000)
        let year = AcademicYear(name: "Academic Year \(calendar.component(.year, from: start))", startDate: start, endDate: end)
        modelContext.insert(year)
    }

    @discardableResult
    private func ensureActiveSemester() -> Semester {
        if let semester = courses.compactMap(\.semester).first(where: { $0.status == .active }) {
            return semester
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .month, value: 4, to: start) ?? start.addingTimeInterval(12_000_000)
        let year = AcademicYear(name: "Academic Year \(calendar.component(.year, from: start))", startDate: start, endDate: calendar.date(byAdding: .month, value: 10, to: start) ?? end)
        let semester = Semester(name: "Current Semester", order: 1, startDate: start, endDate: end, academicYear: year)
        modelContext.insert(year)
        modelContext.insert(semester)
        return semester
    }
}

struct SessionRow: View {
    let session: ClassSession
    var prominent = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(UniDateFormatters.time.string(from: session.startTime))
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.course?.name ?? "Class")
                    .font(prominent ? .title3.weight(.semibold) : .body.weight(.semibold))
                Text(session.title)
                    .foregroundStyle(.secondary)
                Text("\(UniDateFormatters.interval(session.startTime, session.endTime))\(session.room.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
