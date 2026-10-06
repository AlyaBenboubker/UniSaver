import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [ClassSession]
    @State private var navigation = AppNavigationState()
    @State private var quickAddTarget: QuickAddTarget?
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var currentWindowWidth: CGFloat = 0
    @State private var pendingWorkspaceAction: WorkspaceResetAction?
    @State private var workspaceError: WorkspaceError?
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    private let primarySections: [AppSection] = [.today, .classes, .study, .planner, .progress, .library]

    var body: some View {
        GeometryReader { proxy in
            let navigationMode = navigationLayoutMode(totalWidth: proxy.size.width)
            let sidebarWidth = sidebarWidth(for: proxy.size.width)

            NavigationSplitView(columnVisibility: $columnVisibility) {
                VStack(spacing: 0) {
                    VStack(spacing: navigationMode == .wide ? 8 : 6) {
                        ForEach(primarySections) { section in
                            SidebarNavigationButton(
                                section: section,
                                isSelected: navigation.selectedSection == section,
                                isCondensed: navigationMode != .wide,
                                action: {
                                    navigation.requestSelect(section)
                                    closeSidebarIfCompact()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, navigationMode == .compact ? 18 : 24)

                    Spacer(minLength: 18)

                    if navigationMode != .compact {
                        StudyStreakCard(sessions: sessions, isCondensed: navigationMode != .wide)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }

                    SidebarNavigationButton(
                        section: .settings,
                        isSelected: navigation.selectedSection == .settings,
                        isCondensed: navigationMode != .wide,
                        action: {
                            navigation.requestSelect(.settings)
                            closeSidebarIfCompact()
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background {
                    StudyDeskTheme.backgroundSecondary
                        .ignoresSafeArea(.container, edges: [.top, .bottom, .leading])
                }
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(StudyDeskTheme.borderSubtle)
                        .frame(width: 1)
                        .ignoresSafeArea(.container, edges: .vertical)
                }
                .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth)
            } detail: {
                NavigationStack {
                    Group {
                        switch navigation.selectedSection {
                        case .today:
                            TodayView(quickAddTarget: $quickAddTarget)
                        case .classes:
                            ClassesView(quickAddTarget: $quickAddTarget)
                        case .study:
                            StudyStudioView(quickAddTarget: $quickAddTarget)
                        case .planner:
                            PlannerView(initialFilter: navigation.plannerTaskFilter)
                        case .progress:
                            ProgressDashboardView()
                        case .library:
                            LibraryView()
                        case .settings:
                            SettingsView()
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                toggleSidebar(for: currentWindowWidth)
                            } label: {
                                Label("Toggle Sidebar", systemImage: "sidebar.left")
                            }
                            .accessibilityIdentifier("globalSidebarToggle")
                        }
                        ToolbarItemGroup {
                            QuickAddMenu(quickAddTarget: $quickAddTarget)
                        }
                    }
                    .sheet(item: $quickAddTarget, onDismiss: {
                        quickAddTarget = nil
                    }) { target in
                        QuickAddSheet(target: target)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .openQuickAddCourse)) { _ in
                        quickAddTarget = .course(nil)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .selectAppSection)) { notification in
                        if let section = notification.object as? AppSection {
                            navigation.requestSelect(section)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .loadDemoWorkspace)) { _ in
                        DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                        navigation.requestSelect(.today)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .resetDemoData)) { _ in
                        pendingWorkspaceAction = .resetDemoData
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .resetWorkspaceChoice)) { _ in
                        DemoWorkspaceService.resetWorkspaceChoice(in: modelContext)
                        navigation.requestSelect(.today)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .startEmptyWorkspace)) { _ in
                        pendingWorkspaceAction = .startEmptyWorkspace
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .openPlannerTasks)) { notification in
                        if let filter = notification.object as? PlannerTaskFilter {
                            navigation.plannerTaskFilter = filter
                        }
                        navigation.requestSelect(.planner)
                    }
                }
                .id(navigation.selectedSection)
            }
            .onAppear {
                currentWindowWidth = proxy.size.width
                updateColumnVisibility(for: proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                currentWindowWidth = newWidth
                updateColumnVisibility(for: newWidth)
            }
            .confirmationDialog(
                pendingWorkspaceAction?.title ?? "Confirm workspace action",
                isPresented: Binding(
                    get: { pendingWorkspaceAction != nil },
                    set: { if !$0 { pendingWorkspaceAction = nil } }
                )
            ) {
                if let pendingWorkspaceAction {
                    Button(pendingWorkspaceAction.confirmTitle, role: .destructive) {
                        performWorkspaceAction(pendingWorkspaceAction)
                    }
                }
                Button("Cancel", role: .cancel) { pendingWorkspaceAction = nil }
            } message: {
                Text(pendingWorkspaceAction?.message ?? "")
            }
            .alert(item: $workspaceError) { error in
                Alert(title: Text("Workspace update failed"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
        }
        .environment(navigation)
        .environment(\.locale, (AppLanguage(rawValue: appLanguageRawValue) ?? .system).locale)
        .environment(\.layoutDirection, (AppLanguage(rawValue: appLanguageRawValue) ?? .system).layoutDirection)
    }

    private func navigationLayoutMode(totalWidth: CGFloat) -> StudyDeskLayoutMode {
        if totalWidth < 900 { return .compact }
        if totalWidth < 1180 { return .tabletExpanded }
        return .wide
    }

    private func sidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        switch navigationLayoutMode(totalWidth: totalWidth) {
        case .wide:
            #if os(iOS)
            return 224
            #else
            return totalWidth >= 1280 ? 178 : 216
            #endif
        case .tabletExpanded:
            return 224
        case .medium:
            return 220
        case .compact:
            return 300
        }
    }

    private func updateColumnVisibility(for totalWidth: CGFloat) {
        let targetVisibility: NavigationSplitViewVisibility = totalWidth < 900 ? .detailOnly : .all
        if columnVisibility != targetVisibility {
            columnVisibility = targetVisibility
        }
    }

    private func closeSidebarIfCompact() {
        if currentWindowWidth < 900 {
            columnVisibility = .detailOnly
        }
    }

    private func toggleSidebar(for totalWidth: CGFloat) {
        if totalWidth < 900 {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        } else {
            columnVisibility = columnVisibility == .all ? .detailOnly : .all
        }
    }

    private func performWorkspaceAction(_ action: WorkspaceResetAction) {
        do {
            try DemoWorkspaceService.resetWorkspaceThrowing(in: modelContext)
            switch action {
            case .resetDemoData:
                DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
            case .startEmptyWorkspace:
                DemoWorkspaceService.startEmptyWorkspace(in: modelContext)
            }
            navigation.select(.today)
        } catch {
            workspaceError = WorkspaceError(message: error.localizedDescription)
        }
        pendingWorkspaceAction = nil
    }
}

private enum WorkspaceResetAction: Identifiable {
    case resetDemoData
    case startEmptyWorkspace

    var id: String {
        switch self {
        case .resetDemoData: "resetDemoData"
        case .startEmptyWorkspace: "startEmptyWorkspace"
        }
    }

    var title: String {
        switch self {
        case .resetDemoData: "Reset demo data?"
        case .startEmptyWorkspace: "Start empty workspace?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .resetDemoData: "Reset and Load Demo"
        case .startEmptyWorkspace: "Erase and Start Empty"
        }
    }

    var message: String {
        switch self {
        case .resetDemoData: "This replaces the current workspace with demo data. Existing courses, study data, files metadata, and understanding checks in this store will be removed."
        case .startEmptyWorkspace: "This removes the current workspace data and starts with a blank workspace."
        }
    }
}

private struct WorkspaceError: Identifiable {
    let id = UUID()
    let message: String
}

private struct SidebarNavigationButton: View {
    let section: AppSection
    let isSelected: Bool
    var isCondensed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(section.title(for: AppLanguage.current), systemImage: section.symbolName)
                .font((isCondensed ? Font.caption : Font.callout).weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, isCondensed ? 8 : 9)
                .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : StudyDeskTheme.textPrimary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct StudyStreakCard: View {
    let sessions: [ClassSession]
    var isCondensed = false

    private var summary: SessionStreakSummary {
        SessionStreakCalculator.summary(from: sessions, calendar: .current, now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCondensed ? 5 : 8) {
            HStack {
                Text("Study Streak")
                    .font(.caption.weight(.medium))
                Spacer()
                Image(systemName: "sparkle")
                    .font(.caption)
                    .foregroundStyle(StudyDeskTheme.accentPrimary)
            }
            if summary.completedSessionCount == 0 {
                Text(AppLanguage.current == .french ? "Aucune séance terminée" : "No completed sessions yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(summary.currentStreak)")
                    .font(.system(isCondensed ? .headline : .title2, design: .rounded).weight(.bold))
                Text(AppLanguage.current == .french ? "jours" : "days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(summary.recentDays) { day in
                    Circle()
                        .fill(day.hasCompletedSession ? Color.accentColor : StudyDeskTheme.borderSubtle)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(day.hasCompletedSession ? "Completed session" : "No completed session")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }
}

struct SessionStreakSummary {
    let currentStreak: Int
    let completedSessionCount: Int
    let recentDays: [SessionStreakDay]
}

struct SessionStreakDay: Identifiable {
    let date: Date
    let hasCompletedSession: Bool

    var id: Date { date }
}

enum SessionStreakCalculator {
    static func summary(from sessions: [ClassSession], calendar: Calendar, now: Date) -> SessionStreakSummary {
        let completedDays = Set(
            sessions
                .filter { $0.attendanceStatus == .attended && $0.endTime <= now }
                .map { calendar.startOfDay(for: $0.date) }
        )
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var cursor = completedDays.contains(today) ? today : yesterday
        var currentStreak = 0

        while completedDays.contains(cursor) {
            currentStreak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        let recentDays = (0..<9).reversed().compactMap { offset -> SessionStreakDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return SessionStreakDay(date: date, hasCompletedSession: completedDays.contains(date))
        }

        return SessionStreakSummary(
            currentStreak: currentStreak,
            completedSessionCount: sessions.filter { $0.attendanceStatus == .attended && $0.endTime <= now }.count,
            recentDays: recentDays
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.previewContainer())
}
