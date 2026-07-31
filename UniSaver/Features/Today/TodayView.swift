import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \ClassSession.startTime) private var sessions: [ClassSession]
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query(sort: \StudyBlock.startDate) private var studyBlocks: [StudyBlock]
    @Query(sort: \ReadingProgress.lastOpenedAt, order: .reverse) private var readingProgress: [ReadingProgress]
    @Query private var workspaces: [AppWorkspace]

    @Binding var quickAddTarget: QuickAddTarget?
    @State private var selectedDate = Date()
    @State private var showsCompletedTasks = false
    @State private var showsWorkspaceChooser = false
    @State private var isPreparingWorkspace = false

    private var snapshot: TodayDashboardSnapshot {
        TodayDashboardService.makeSnapshot(
            selectedDate: selectedDate,
            workspace: workspaces.first,
            courses: courses,
            sessions: sessions,
            tasks: visibleTasks,
            exams: exams,
            studyBlocks: studyBlocks,
            readingProgress: readingProgress
        )
    }

    private var visibleTasks: [AcademicTask] {
        showsCompletedTasks ? tasks : tasks.filter { $0.status != .completed }
    }

    var body: some View {
        TodayDashboardView(
            snapshot: snapshot,
            showsCompletedTasks: $showsCompletedTasks,
            selectedDate: $selectedDate,
            quickAddTarget: $quickAddTarget,
            onLoadDemo: {
                DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                showsWorkspaceChooser = false
                selectedDate = .now
            },
            onShowWorkspaceChooser: { showsWorkspaceChooser = true }
        )
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showsWorkspaceChooser) {
            WorkspaceChooserSheet(
                isPreparingWorkspace: isPreparingWorkspace,
                onLoadDemo: {
                    isPreparingWorkspace = true
                    DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                    isPreparingWorkspace = false
                    showsWorkspaceChooser = false
                    selectedDate = .now
                },
                onStartEmpty: {
                    isPreparingWorkspace = true
                    DemoWorkspaceService.startEmptyWorkspace(in: modelContext)
                    isPreparingWorkspace = false
                    showsWorkspaceChooser = false
                    selectedDate = .now
                }
            )
            .presentationSizing(.fitted)
        }
        .onAppear {
            showsWorkspaceChooser = workspaces.isEmpty && courses.isEmpty
        }
    }
}

struct TodayDashboardView: View {
    let snapshot: TodayDashboardSnapshot
    @Binding var showsCompletedTasks: Bool
    @Binding var selectedDate: Date
    @Binding var quickAddTarget: QuickAddTarget?
    let onLoadDemo: () -> Void
    let onShowWorkspaceChooser: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layoutMode = StudyDeskLayoutMode(contentWidth: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: layoutMode.cardSpacing) {
                    DashboardHeader(
                        firstName: snapshot.workspace?.firstName ?? "Alya",
                        selectedDate: $selectedDate,
                        layoutMode: layoutMode
                    )

                    if snapshot.workspace == nil && snapshot.courseProgress.isEmpty {
                        DashboardEmptyState(
                            quickAddTarget: $quickAddTarget,
                            onLoadDemo: onLoadDemo,
                            onShowWorkspaceChooser: onShowWorkspaceChooser
                        )
                    } else if snapshot.isEmptyDay {
                        EmptyTodayPlanningView(
                            snapshot: snapshot,
                            quickAddTarget: $quickAddTarget,
                            onLoadDemo: onLoadDemo
                        )
                    } else {
                        dashboardGrid(layoutMode: layoutMode)
                    }
                }
                .padding(layoutMode.outerPadding)
                .frame(maxWidth: layoutMode == .wide ? StudyDeskTheme.dashboardMaxWidth : .infinity)
                .frame(maxWidth: .infinity)
            }
            .background(StudyDeskTheme.backgroundPrimary)
        }
    }

    @ViewBuilder
    private func dashboardGrid(layoutMode: StudyDeskLayoutMode) -> some View {
        switch layoutMode {
        case .wide, .tabletExpanded:
            HStack(alignment: .top, spacing: StudyDeskTheme.spacing) {
                VStack(spacing: StudyDeskTheme.spacing) {
                    ScheduleTimeline(items: snapshot.timelineItems, quickAddTarget: $quickAddTarget)
                    PriorityTaskList(
                        tasks: snapshot.priorityTasks,
                        showsCompletedTasks: $showsCompletedTasks,
                        quickAddTarget: $quickAddTarget
                    )
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(layoutMode == .tabletExpanded ? 1.4 : 1.2)

                VStack(spacing: StudyDeskTheme.spacing) {
                    NextClassCard(session: snapshot.nextSession, layoutMode: layoutMode)
                    HStack(spacing: StudyDeskTheme.spacing) {
                        UpcomingExamCard(exam: snapshot.upcomingExam)
                        AssignmentDueCard(task: snapshot.assignmentDue)
                    }
                    StudyProgressSection(progress: snapshot.courseProgress, studyBlocks: snapshot.studyBlocks)
                    HStack(alignment: .top, spacing: StudyDeskTheme.spacing) {
                        FlashcardsDueSummary(summary: snapshot.flashcards)
                        ContinueReadingCard(reading: snapshot.recentReading)
                    }
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            }
        case .medium:
            VStack(spacing: layoutMode.cardSpacing) {
                NextClassCard(session: snapshot.nextSession, layoutMode: layoutMode)
                Grid(horizontalSpacing: layoutMode.cardSpacing, verticalSpacing: layoutMode.cardSpacing) {
                    GridRow {
                        ScheduleTimeline(items: snapshot.timelineItems, quickAddTarget: $quickAddTarget)
                        VStack(spacing: layoutMode.cardSpacing) {
                            UpcomingExamCard(exam: snapshot.upcomingExam)
                            AssignmentDueCard(task: snapshot.assignmentDue)
                        }
                    }
                    GridRow {
                        PriorityTaskList(
                            tasks: snapshot.priorityTasks,
                            showsCompletedTasks: $showsCompletedTasks,
                            quickAddTarget: $quickAddTarget
                        )
                        StudyProgressSection(progress: snapshot.courseProgress, studyBlocks: snapshot.studyBlocks)
                    }
                    GridRow {
                        FlashcardsDueSummary(summary: snapshot.flashcards)
                        ContinueReadingCard(reading: snapshot.recentReading)
                    }
                }
            }
        case .compact:
            VStack(spacing: layoutMode.cardSpacing) {
                NextClassCard(session: snapshot.nextSession, layoutMode: layoutMode)
                ScheduleTimeline(items: snapshot.timelineItems, quickAddTarget: $quickAddTarget)
                PriorityTaskList(
                    tasks: snapshot.priorityTasks,
                    showsCompletedTasks: $showsCompletedTasks,
                    quickAddTarget: $quickAddTarget
                )
                UpcomingExamCard(exam: snapshot.upcomingExam)
                AssignmentDueCard(task: snapshot.assignmentDue)
                StudyProgressSection(progress: snapshot.courseProgress, studyBlocks: snapshot.studyBlocks)
                FlashcardsDueSummary(summary: snapshot.flashcards)
                ContinueReadingCard(reading: snapshot.recentReading)
            }
        }
    }
}

private extension TodayDashboardSnapshot {
    var isEmptyDay: Bool {
        timelineItems.isEmpty
            && priorityTasks.isEmpty
            && upcomingExam == nil
            && assignmentDue == nil
            && recentReading == nil
            && !flashcards.isConfigured
    }
}

struct DashboardHeader: View {
    let firstName: String
    @Binding var selectedDate: Date
    let layoutMode: StudyDeskLayoutMode

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                titleBlock
                    .layoutPriority(2)
                Spacer(minLength: 16)
                DayNavigationControl(selectedDate: $selectedDate, layoutMode: layoutMode)
                    .layoutPriority(1)
                if layoutMode == .wide || layoutMode == .tabletExpanded {
                    secondaryButtons
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                HStack(spacing: 10) {
                    DayNavigationControl(selectedDate: $selectedDate, layoutMode: .compact)
                    Spacer()
                if layoutMode != .compact {
                    secondaryButtons
                }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greeting), \(firstName)")
                .font(.system(layoutMode == .compact ? .title2 : .title2, design: .rounded).weight(.bold))
                .foregroundStyle(StudyDeskTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(UniDateFormatters.fullDate.string(from: selectedDate))
                .font(.callout)
                .foregroundStyle(StudyDeskTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private var secondaryButtons: some View {
        HStack(spacing: 8) {
            Button {} label: {
                Image(systemName: "bell")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Notifications not configured")
            .help("Notifications arrive in a later lot.")
            Text("A")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(StudyDeskTheme.accentPrimary.opacity(0.72), in: Circle())
                .accessibilityLabel("Profile for \(firstName)")
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }
}

struct DayNavigationControl: View {
    @Binding var selectedDate: Date
    var layoutMode: StudyDeskLayoutMode = .wide

    var body: some View {
        HStack(spacing: layoutMode == .compact ? 6 : 10) {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")

            Text(compactDate)
                .font((layoutMode == .compact ? Font.subheadline : Font.callout).weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: layoutMode == .compact ? 88 : 132)

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next day")

            Menu {
                DatePicker("Selected date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            } label: {
                Image(systemName: "calendar")
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Open calendar")
        }
        .padding(.horizontal, layoutMode == .compact ? 7 : 10)
        .padding(.vertical, 5)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var compactDate: String {
        switch layoutMode {
        case .wide, .tabletExpanded, .medium:
            selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        case .compact:
            selectedDate.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}

struct ScheduleTimeline: View {
    let items: [DashboardTimelineItem]
    @Binding var quickAddTarget: QuickAddTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's Schedule")
                    .font(.headline)
                Spacer()
                Button("View full day") {}
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .help("Planner day view arrives in a later lot.")
            }

            if items.isEmpty {
                Text("No sessions or study blocks for this date.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        ScheduleTimelineRow(item: item)
                        if item.id != items.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
            }

            Divider()
            Button("Add time block", systemImage: "plus") {
                quickAddTarget = .studyBlock(nil, nil)
            }
            .font(.callout.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(StudyDeskTheme.accentPrimary)
        }
        .padding()
        .deskCard()
    }
}

struct ScheduleTimelineRow: View {
    let item: DashboardTimelineItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(UniDateFormatters.time.string(from: item.startDate))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(StudyDeskTheme.borderSubtle)
                    .frame(width: 2, height: 50)
                    .offset(y: 9)
                CourseColorBadge(colorIdentifier: item.colorIdentifier, size: 13)
                    .padding(.top, 4)
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(item.status)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(StudyDeskTheme.surfaceTinted, in: Capsule())
                }
                Text(item.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(UniDateFormatters.interval(item.startDate, item.endDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct NextClassCard: View {
    let session: ClassSession?
    var layoutMode: StudyDeskLayoutMode = .wide

    private var ringSize: CGFloat {
        switch layoutMode {
        case .wide: 108
        case .tabletExpanded: 92
        case .medium: 104
        case .compact: 84
        }
    }

    private var cardPadding: CGFloat {
        switch layoutMode {
        case .wide: 20
        case .tabletExpanded: 18
        case .medium: 18
        case .compact: 16
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: layoutMode == .compact ? 12 : 16) {
            if let session {
                VStack(alignment: .leading, spacing: layoutMode == .tabletExpanded ? 11 : 15) {
                    Text("Next Class")
                        .font(.headline)
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(StudyDeskTheme.accentPrimary)
                                .shadow(color: StudyDeskTheme.accentPrimary.opacity(0.24), radius: 10, y: 5)
                            Image(systemName: CourseIconCatalog.sanitizedSymbolName(session.course?.symbolName))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: layoutMode == .tabletExpanded ? 42 : 48, height: layoutMode == .tabletExpanded ? 42 : 48)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.course?.name ?? "Class")
                                .font(.title3.weight(.bold))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(2)
                            Text(session.chapter?.title ?? session.title)
                                .font(layoutMode == .tabletExpanded ? .callout : .title3)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .layoutPriority(2)
                    }

                    HStack(spacing: 10) {
                        Label(UniDateFormatters.interval(session.startTime, session.endTime), systemImage: "clock")
                        if let room = session.room {
                            Label(room, systemImage: "mappin.and.ellipse")
                        }
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        NavigationLink("View Details") {
                            if let course = session.course {
                                CourseWorkspaceView(course: course, quickAddTarget: .constant(nil))
                            } else {
                                MissingContextView(title: "No course", message: "This session is not linked to a course.")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudyDeskTheme.accentPrimary)

                        Button("Open Notes") {}
                            .buttonStyle(.bordered)
                            .disabled(true)
                            .help("Notes arrive in a later lot.")
                    }
                }
                Spacer(minLength: 8)
                TimeRing(progress: countdownProgress(for: session), tint: StudyDeskTheme.accentPrimary)
                    .frame(width: ringSize, height: ringSize)
                    .layoutPriority(0)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next Class")
                        .font(.headline)
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                    Text("No upcoming class.")
                        .font(.title3.weight(.semibold))
                    Text("Schedule a session to make this your class launchpad.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(cardPadding)
        .background {
            LinearGradient(
                colors: [StudyDeskTheme.accentPrimary.opacity(0.15), StudyDeskTheme.surfacePrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StudyDeskTheme.accentPrimary.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: StudyDeskTheme.shadow, radius: 12, y: 5)
    }

    private func countdownProgress(for session: ClassSession) -> Double {
        let total = max(session.endTime.timeIntervalSince(session.startTime), 1)
        let elapsed = Date().timeIntervalSince(session.startTime)
        return min(max(elapsed / total, 0), 1)
    }
}

struct TimeRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(StudyDeskTheme.surfacePrimary.opacity(0.74))
            Circle()
                .stroke(.white.opacity(0.7), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(progress, 0.18), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(index % 3 == 0 ? 0.38 : 0.18))
                    .frame(width: 2, height: index % 3 == 0 ? 8 : 5)
                    .offset(y: -43)
                    .rotationEffect(.degrees(Double(index) * 30))
            }
            Rectangle()
                .fill(StudyDeskTheme.textPrimary)
                .frame(width: 2, height: 32)
                .offset(y: -14)
            Rectangle()
                .fill(StudyDeskTheme.textPrimary)
                .frame(width: 30, height: 2)
                .rotationEffect(.degrees(-22))
                .offset(x: 12, y: 4)
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
        }
        .accessibilityLabel("Class time indicator")
    }
}

struct UpcomingExamCard: View {
    let exam: Exam?

    var body: some View {
        CompactDeadlineCard(
            title: "Upcoming Exam",
            systemImage: "doc.text",
            tint: .red,
            courseName: exam?.course?.name,
            courseColorIdentifier: exam?.course?.colorIdentifier,
            primaryText: exam?.title,
            secondaryText: exam.map { "\(UniDateFormatters.dayMonth.string(from: $0.date)) · \(TodayDashboardService.daysUntil($0.date)) days left" },
            progress: exam.map { timelineValue(until: $0.date) }
        )
    }

    private func timelineValue(until date: Date) -> Double {
        let days = max(TodayDashboardService.daysUntil(date), 0)
        return min(1, max(0.08, 1 - Double(days) / 30))
    }
}

struct AssignmentDueCard: View {
    let task: AcademicTask?

    var body: some View {
        CompactDeadlineCard(
            title: "Assignment Due",
            systemImage: "doc.text.fill",
            tint: .orange,
            courseName: task?.course?.name,
            courseColorIdentifier: task?.course?.colorIdentifier,
            primaryText: task?.title,
            secondaryText: task.map { "\(UniDateFormatters.dayMonth.string(from: $0.dueDate)) · \($0.priority.title)" },
            progress: task.map { $0.status == .completed ? 1 : $0.status == .inProgress ? 0.45 : 0.08 }
        )
    }
}

struct CompactDeadlineCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let courseName: String?
    let courseColorIdentifier: String?
    let primaryText: String?
    let secondaryText: String?
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)

            if let primaryText {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle().fill(tint.opacity(0.12))
                        Image(systemName: systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        if let courseName {
                            Text(courseName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CourseColor.color(for: courseColorIdentifier ?? "blueViolet"))
                        }
                        Text(primaryText)
                            .font(.callout.weight(.semibold))
                        if let secondaryText {
                            Text(secondaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ProgressBar(value: progress ?? 0, color: tint)
            } else {
                Text("Nothing scheduled.")
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 76, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .deskCard()
    }
}

struct PriorityTaskList: View {
    let tasks: [AcademicTask]
    @Binding var showsCompletedTasks: Bool
    @Binding var quickAddTarget: QuickAddTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Priority Tasks")
                    .font(.headline)
                Spacer()
                Button {
                    showsCompletedTasks.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showsCompletedTasks ? "checkmark.square.fill" : "square")
                        Text("Done")
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button("View all") {}
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .help("Full task view arrives with Planner.")
            }

            if tasks.isEmpty {
                Text("No priority tasks.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks.prefix(5)) { task in
                        PriorityTaskRow(task: task)
                        if task.id != tasks.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }

            Divider()
            Button("Add task", systemImage: "plus") {
                quickAddTarget = .task(nil, nil, nil)
            }
            .font(.callout.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(StudyDeskTheme.accentPrimary)
        }
        .padding()
        .deskCard()
    }
}

struct PriorityTaskRow: View {
    @Bindable var task: AcademicTask

    var body: some View {
        HStack(spacing: 11) {
            Button {
                task.status = task.status == .completed ? .todo : .completed
                task.updatedAt = .now
            } label: {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(task.status == .completed ? .green : .secondary)
            .accessibilityLabel(task.status == .completed ? "Reopen task" : "Complete task")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.callout.weight(.semibold))
                    .strikethrough(task.status == .completed)
                HStack(spacing: 5) {
                    CourseColorBadge(colorIdentifier: task.course?.colorIdentifier ?? "blueViolet", size: 7)
                    Text(task.course?.name ?? "General")
                    Text("·")
                    Text("due \(UniDateFormatters.dayMonth.string(from: task.dueDate))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(dueLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(dueColor)
                .frame(minWidth: 62, alignment: .trailing)
            Image(systemName: "flag")
                .font(.callout)
                .foregroundStyle(priorityColor)
                .accessibilityLabel(task.priority.title)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private var priorityColor: Color {
        switch task.priority {
        case .urgent: .red
        case .high: .orange
        case .medium: .blue
        case .low: .secondary
        }
    }

    private var dueLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(task.dueDate) { return "Today" }
        if calendar.isDateInTomorrow(task.dueDate) { return "Tomorrow" }
        return UniDateFormatters.dayMonth.string(from: task.dueDate)
    }

    private var dueColor: Color {
        Calendar.current.isDateInToday(task.dueDate) ? .red : .secondary
    }
}

struct StudyProgressSection: View {
    let progress: [CourseProgressSummary]
    let studyBlocks: [StudyBlock]

    var body: some View {
        SummaryCard(title: "Study Progress", systemImage: "chart.line.uptrend.xyaxis") {
            if progress.isEmpty {
                Text("No active courses yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(progress.prefix(5)) { item in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(CourseColor.color(for: item.course.colorIdentifier).opacity(0.12))
                            Image(systemName: CourseIconCatalog.sanitizedSymbolName(item.course.symbolName))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CourseColor.color(for: item.course.colorIdentifier))
                        }
                        .frame(width: 28, height: 28)

                        Text(item.course.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .frame(width: 130, alignment: .leading)
                        ProgressBar(value: item.progress, color: CourseColor.color(for: item.course.colorIdentifier))
                        Text(item.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                        Text(plannedDuration(for: item.course))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Text("Structural workflow progress only.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func plannedDuration(for course: Course) -> String {
        let seconds = studyBlocks
            .filter { $0.course?.id == course.id }
            .reduce(0) { $0 + max($1.endDate.timeIntervalSince($1.startDate), 0) }
        guard seconds > 0 else { return "Planned" }
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }
}

struct FlashcardsDueSummary: View {
    let summary: FlashcardsSummary

    var body: some View {
        SummaryCard(title: "Flashcards Due", systemImage: "rectangle.stack") {
            if summary.isConfigured {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CourseColor.teal.color.opacity(0.12))
                        Image(systemName: "rectangle.stack")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(CourseColor.teal.color)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(summary.dueCount)")
                            .font(.system(.title, design: .rounded).weight(.bold))
                        Text("cards due today")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("\(summary.courseCount) courses")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CourseColor.teal.color)
                if let lastActivity = summary.lastActivity {
                    Text("Last activity \(UniDateFormatters.dayMonth.string(from: lastActivity))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Study not configured")
                    .font(.headline)
                Text("Open Study when the flashcards engine is available.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ContinueReadingCard: View {
    let reading: ReadingProgress?

    var body: some View {
        SummaryCard(title: "Continue Reading", systemImage: "book") {
            if let reading {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CourseColor.color(for: reading.coverColorIdentifier))
                        .frame(width: 50, height: 66)
                        .overlay(Image(systemName: "doc.richtext").foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(reading.resourceTitle)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        Text(reading.course?.name ?? "Resource")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Page \(reading.currentPage) of \(reading.totalPages) · \(reading.progress.formatted(.percent.precision(.fractionLength(0))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressBar(value: reading.progress, color: CourseColor.color(for: reading.coverColorIdentifier))
                Text("Last opened \(UniDateFormatters.dayMonth.string(from: reading.lastOpenedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No reading progress yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DashboardEmptyState: View {
    @Binding var quickAddTarget: QuickAddTarget?
    let onLoadDemo: () -> Void
    let onShowWorkspaceChooser: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                title: "Choose a workspace",
                message: "Explore a realistic demo dashboard or start with an empty academic workspace.",
                systemImage: "rectangle.grid.2x2",
                actionTitle: "Choose Workspace",
                action: onShowWorkspaceChooser
            )
            HStack {
                #if DEBUG
                Button("Load Demo Workspace", systemImage: "sparkles", action: onLoadDemo)
                    .buttonStyle(.borderedProminent)
                #endif
                Button("Add First Course", systemImage: "books.vertical") {
                    quickAddTarget = .course(nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .deskCard()
    }
}

struct EmptyTodayPlanningView: View {
    let snapshot: TodayDashboardSnapshot
    @Binding var quickAddTarget: QuickAddTarget?
    let onLoadDemo: () -> Void

    private var firstCourse: Course? {
        snapshot.courseProgress.first?.course
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your day is ready to be planned")
                        .font(.title3.weight(.bold))
                    Text(recommendedAction)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                #if DEBUG
                Button("Load Demo Workspace", systemImage: "sparkles", action: onLoadDemo)
                    .buttonStyle(.bordered)
                #endif
            }

            HStack {
                Button("Add Study Block", systemImage: "timer") {
                    quickAddTarget = .studyBlock(firstCourse, nil)
                }
                .buttonStyle(.borderedProminent)
                Button("Add Task", systemImage: "checklist") {
                    quickAddTarget = .task(firstCourse, nil, nil)
                }
                .buttonStyle(.bordered)
                if let firstCourse {
                    Button("Add Chapter", systemImage: "list.number") {
                        quickAddTarget = .chapter(firstCourse)
                    }
                    .buttonStyle(.bordered)
                    Button("Schedule First Session", systemImage: "calendar.badge.plus") {
                        quickAddTarget = .session(firstCourse, nil)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Add First Course", systemImage: "books.vertical") {
                        quickAddTarget = .course(nil)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !snapshot.courseProgress.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Courses")
                        .font(.headline)
                    ForEach(snapshot.courseProgress.prefix(3)) { item in
                        HStack {
                            CourseColorBadge(colorIdentifier: item.course.colorIdentifier)
                            Text(item.course.name)
                            Spacer()
                            Text(item.progress, format: .percent.precision(.fractionLength(0)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .deskCard()
    }

    private var recommendedAction: String {
        if let firstCourse {
            return "\(firstCourse.name) is ready. Add a chapter, then schedule the first class session."
        }
        return "Create a course or load the demo workspace to see a populated academic dashboard."
    }
}

struct WorkspaceChooserSheet: View {
    let isPreparingWorkspace: Bool
    let onLoadDemo: () -> Void
    let onStartEmpty: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isPreparingWorkspace ? "hourglass" : "rectangle.grid.2x2")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(StudyDeskTheme.accentPrimary)
                .accessibilityHidden(true)
            Text("Choose a workspace")
                .font(.title2.weight(.bold))
            Text("Start with a realistic demo set or keep UniSaver empty and build your own desk.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if isPreparingWorkspace {
                ProgressView("Preparing workspace")
                    .padding(.top, 4)
            } else {
                HStack(spacing: 12) {
                    #if DEBUG
                    Button("Explore Demo Workspace", systemImage: "sparkles", action: onLoadDemo)
                        .buttonStyle(.borderedProminent)
                    #endif
                    Button("Start Empty Workspace", systemImage: "plus", action: onStartEmpty)
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 640)
    }
}

struct CourseColorBadge: View {
    let colorIdentifier: String
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(CourseColor.color(for: colorIdentifier))
            .frame(width: size, height: size)
            .overlay {
                Circle().stroke(.white.opacity(0.65), lineWidth: max(1, size / 14))
            }
            .accessibilityHidden(true)
    }
}

struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 7)
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(value.formatted(.percent.precision(.fractionLength(0)))))
    }
}

struct SummaryCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .deskCard()
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
                Text("\(session.sessionType.title) · \(UniDateFormatters.interval(session.startTime, session.endTime))\(session.room.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
