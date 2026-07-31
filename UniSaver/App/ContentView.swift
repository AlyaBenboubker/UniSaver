import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selection: AppSection? = .today
    @State private var quickAddTarget: QuickAddTarget?
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var currentWindowWidth: CGFloat = 0

    private let primarySections: [AppSection] = [.today, .classes, .study, .planner, .progress, .library]

    var body: some View {
        GeometryReader { proxy in
            let navigationMode = navigationLayoutMode(totalWidth: proxy.size.width)
            let sidebarWidth = sidebarWidth(for: proxy.size.width)

            NavigationSplitView(columnVisibility: $columnVisibility) {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "sidebar.left")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, navigationMode == .compact ? 14 : 22)

                    VStack(spacing: navigationMode == .wide ? 8 : 6) {
                        ForEach(primarySections) { section in
                            SidebarNavigationButton(
                                section: section,
                                isSelected: selection == section,
                                isCondensed: navigationMode != .wide,
                                action: {
                                    selection = section
                                    closeSidebarIfCompact()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 14)

                    Spacer(minLength: 18)

                    if navigationMode != .compact {
                        StudyStreakCard(isCondensed: navigationMode != .wide)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }

                    SidebarNavigationButton(
                        section: .settings,
                        isSelected: selection == .settings,
                        isCondensed: navigationMode != .wide,
                        action: {
                            selection = .settings
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
                        switch selection ?? .today {
                        case .today:
                            TodayView(quickAddTarget: $quickAddTarget)
                        case .classes:
                            ClassesView(quickAddTarget: $quickAddTarget)
                        case .study:
                            PlaceholderFeatureView(section: .study)
                        case .planner:
                            PlaceholderFeatureView(section: .planner)
                        case .progress:
                            PlaceholderFeatureView(section: .progress)
                        case .library:
                            PlaceholderFeatureView(section: .library)
                        case .settings:
                            SettingsView()
                        }
                    }
                    .toolbar {
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
                            selection = section
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .loadDemoWorkspace)) { _ in
                        DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                        selection = .today
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .resetDemoData)) { _ in
                        DemoWorkspaceService.resetWorkspace(in: modelContext)
                        DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                        selection = .today
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .resetWorkspaceChoice)) { _ in
                        DemoWorkspaceService.resetWorkspaceChoice(in: modelContext)
                        selection = .today
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .startEmptyWorkspace)) { _ in
                        DemoWorkspaceService.resetWorkspace(in: modelContext)
                        DemoWorkspaceService.startEmptyWorkspace(in: modelContext)
                        selection = .today
                    }
                }
            }
            .onAppear {
                currentWindowWidth = proxy.size.width
                updateColumnVisibility(for: proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                currentWindowWidth = newWidth
                updateColumnVisibility(for: newWidth)
            }
        }
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
}

private struct SidebarNavigationButton: View {
    let section: AppSection
    let isSelected: Bool
    var isCondensed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.symbolName)
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
    var isCondensed = false

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
            Text("12")
                .font(.system(isCondensed ? .headline : .title2, design: .rounded).weight(.bold))
            Text("days")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<9, id: \.self) { index in
                    Circle()
                        .fill(index < 7 ? Color.accentColor : StudyDeskTheme.borderSubtle)
                        .frame(width: 7, height: 7)
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

#Preview {
    ContentView()
        .modelContainer(PersistenceController.previewContainer())
}
