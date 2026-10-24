import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var exams: [Exam]
    @Query private var sessions: [ClassSession]
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var agentResources: [AcademicResource]
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \StudyBlock.startDate) private var studyBlocks: [StudyBlock]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @State private var stopAccountObservation: (() -> Void)?
    @State private var navigation = AppNavigationState()
    @State private var quickAddTarget: QuickAddTarget?
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var currentWindowWidth: CGFloat = 0
    @State private var pendingWorkspaceAction: WorkspaceResetAction?
    @State private var workspaceError: WorkspaceError?
    @AppStorage("globalAgentDraft") private var globalAgentDraft = ""
    @State private var globalConversationState = TodayConversationState()
    @State private var globalConversationProposal: ConversationAnalysisProposal?
    @State private var activeConversationRequestID: UUID?
    @State private var isGlobalAgentSending = false
    @State private var globalAgentError: String?
    @State private var showsGlobalAgent = false
    @State private var globalAgentTask: Task<Void, Never>?
    @State private var appliedGlobalProposalIDs: Set<String> = []
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
                            TabView {
                                ProgressDashboardView().tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                                RevisionHistoryView().tabItem { Label("Revision History", systemImage: "clock.arrow.circlepath") }
                            }
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
                            Button {
                                showsGlobalAgent = true
                            } label: {
                                Label("UniSaver agent", systemImage: "sparkles")
                            }
                            .accessibilityIdentifier("globalAgentButton")
                            QuickAddMenu(quickAddTarget: $quickAddTarget)
                        }
                    }
                    .sheet(item: $quickAddTarget, onDismiss: {
                        quickAddTarget = nil
                    }) { target in
                        QuickAddSheet(target: target)
                    }
                    .sheet(isPresented: $showsGlobalAgent) {
                        TodayConversationDetailSheet(
                            draft: $globalAgentDraft,
                            state: globalConversationState,
                            isSending: isGlobalAgentSending,
                            errorMessage: globalAgentError,
                            onSend: sendGlobalAgentMessage,
                            onCancel: cancelGlobalAgentMessage,
                            onNewConversation: clearGlobalConversation,
                            onOpenProposal: openGlobalConversationProposal,
                onUndoCreation: undoCreationHandler,
                sharedResources: agentResources,
                sharedResourceIDs: globalConversationState.sharedResourceIDs ?? [],
                onSelectResource: selectConversationResource
                        )
                    }
                    .sheet(item: $globalConversationProposal) { proposal in
                        ConversationProposalReviewSheet(
                            proposal: proposal,
                            courses: courses,
                            onCancel: { globalConversationProposal = nil },
                            onApply: applyGlobalConversationProposal,
                            onEditProposal: retainGlobalConversationProposal
                        )
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
                    .onReceive(NotificationCenter.default.publisher(for: .openGlobalAgent)) { _ in
                        showsGlobalAgent = true
                    }
                }
                .id(navigation.selectedSection)
            }
            .allowsHitTesting(navigation.focusTask == nil)
            .accessibilityHidden(navigation.focusTask != nil)
            .overlay {
                if let task = navigation.focusTask {
                    TaskWorkSessionHostView(task: task, onClose: { navigation.focusTask = nil })
                        .id(task.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(StudyDeskTheme.backgroundPrimary)
                }
            }
            .onAppear {
                currentWindowWidth = proxy.size.width
                updateColumnVisibility(for: proxy.size.width)
                globalConversationState = TodayConversationStore.decode(globalConversationNote)
                if stopAccountObservation == nil { stopAccountObservation = AccountSyncService().observeConversationAccount() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .uniSaverConversationAccountChanged), perform: conversationAccountChanged)
            .onDisappear { stopAccountObservation?(); stopAccountObservation = nil }
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

    private var globalConversationNote: StudyNote {
        TodayConversationStore.conversationNote(in: notes, context: modelContext)
    }

    private func persistGlobalConversation() {
        TodayConversationStore.save(globalConversationState, into: globalConversationNote)
        do { try modelContext.save() }
        catch { globalAgentError = "Could not save the conversation: \(error.localizedDescription)" }
    }

    private func sendGlobalAgentMessage() {
        let message = globalAgentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            globalAgentError = "Tell UniSaver what you need first."
            return
        }
        globalAgentTask?.cancel()
        let requestID = UUID()
        activeConversationRequestID = requestID
        isGlobalAgentSending = true
        globalAgentError = nil

        globalAgentTask = Task { @MainActor in
            do {
                let identity = await AccountSyncService().restoreSession()
                let accountID: String
                if case .signedIn(let account) = identity { accountID = account.stableUserID } else { accountID = "local-signed-out" }
                try Task.checkCancellation()
                guard activeConversationRequestID == requestID else { return }
                // Read the shared store again: Today and the global popup share one conversation.
                var current = TodayConversationStore.decode(TodayConversationStore.conversationNote(in: notes, context: modelContext))
                current.prepareForAccount(accountID)
                current.messages.append(TodayConversationMessage(role: .student, text: message))
                current.compact()
                globalConversationState = current
                persistGlobalConversation()
                let provider = try AIRevisionAssistantClient().conversationProvider()
                let sharedIDs = Set(current.sharedResourceIDs ?? [])
                let sources = try TaskWorkspaceService.sources(resources: agentResources.filter { sharedIDs.contains($0.id) }, query: message)
                let service = ConversationProviderService(courses: courses, tasks: tasks, studyBlocks: studyBlocks,
                    page: navigation.selectedSection.rawValue, selectedCourseID: navigation.openedCourseID ?? navigation.libraryCourseID,
                    selectedTaskID: navigation.selectedTaskID, selectedSources: sources, classSessions: sessions, exams: exams)
                let result = try await service.respond(state: current, provider: provider, performCreation: { proposal in
                    guard activeConversationRequestID == requestID, !Task.isCancelled,
                          AccountSyncService().conversationAccountID() == accountID else { throw CancellationError() }
                    let saved = try ConversationActionExecutor.apply(proposal, state: &globalConversationState, note: TodayConversationStore.conversationNote(in: notes, context: modelContext), context: modelContext)
                    let result: [String: Any] = ["status": "saved", "result": saved,
                        "task_ids": globalConversationState.lastExecutionTaskIDs?.map(\.uuidString) ?? []]
                    return String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
                }, refreshTasks: { try modelContext.fetch(FetchDescriptor<AcademicTask>()) })
                try Task.checkCancellation()
                guard activeConversationRequestID == requestID else { return }
                let latest = await AccountSyncService().restoreSession()
                let latestID: String
                if case .signedIn(let account) = latest { latestID = account.stableUserID } else { latestID = "local-signed-out" }
                guard latestID == accountID else {
                    globalConversationState = TodayConversationState()
                    isGlobalAgentSending = false
                    persistGlobalConversation()
                    return
                }
                globalConversationState = TodayConversationStore.decode(TodayConversationStore.conversationNote(in: notes, context: modelContext))
                if globalAgentDraft == message { globalAgentDraft = "" }
                if let proposal = result.proposal {
                    if let previousID = proposal.supersedesProposalID {
                        globalConversationState.pendingProposals.removeValue(forKey: previousID)
                        globalConversationState.supersededProposalIDs = Array(Set((globalConversationState.supersededProposalIDs ?? []) + [previousID]))
                    }
                    globalConversationState.pendingProposals[proposal.id] = proposal
                }
                globalConversationState.messages.append(TodayConversationMessage(role: .agent, text: result.text, proposalID: result.proposal?.id))
                globalConversationState.toolResults = Array(((globalConversationState.toolResults ?? []) + result.toolResults).suffix(12))

                isGlobalAgentSending = false
                activeConversationRequestID = nil
                persistGlobalConversation()
            } catch is CancellationError {
                guard activeConversationRequestID == requestID else { return }
                activeConversationRequestID = nil
                isGlobalAgentSending = false
                if globalAgentDraft.isEmpty { globalAgentDraft = message }
            } catch {
                guard !Task.isCancelled, activeConversationRequestID == requestID else { return }
                activeConversationRequestID = nil
                isGlobalAgentSending = false
                globalAgentError = error.localizedDescription
                if globalAgentDraft.isEmpty { globalAgentDraft = message }
                globalConversationState.messages.append(TodayConversationMessage(role: .system, text: error.localizedDescription, isError: true))
                persistGlobalConversation()
            }
        }
    }

    private func cancelGlobalAgentMessage() {
        activeConversationRequestID = nil
        globalAgentTask?.cancel()
        isGlobalAgentSending = false
        globalConversationState.messages.append(TodayConversationMessage(role: .system, text: "Request cancelled."))
        persistGlobalConversation()
    }

    private func clearGlobalConversation() {
        activeConversationRequestID = nil
        globalAgentTask?.cancel()
        globalAgentDraft = ""
        globalAgentError = nil
        isGlobalAgentSending = false
        globalConversationState = TodayConversationState()
        persistGlobalConversation()
    }

    private func openGlobalConversationProposal(_ proposalID: String) {
        guard let proposal = globalConversationState.pendingProposals[proposalID] else {
            globalAgentError = "That suggestion is no longer available."
            return
        }
        globalConversationProposal = proposal
    }

    private func retainGlobalConversationProposal(_ proposal: ConversationAnalysisProposal) {
        globalConversationState = TodayConversationStore.decode(TodayConversationStore.conversationNote(in: notes, context: modelContext))
        guard !(globalConversationState.appliedProposalIDs ?? []).contains(proposal.id) else { return }
        globalConversationState.pendingProposals[proposal.id] = proposal
        persistGlobalConversation()
    }

    private func applyGlobalConversationProposal(_ proposal: ConversationAnalysisProposal) -> String {
        guard globalConversationState.accountID == AccountSyncService().conversationAccountID() else { return "Account changed. Send the request again in the current account." }
        do {
            let result = try ConversationActionExecutor.apply(proposal, state: &globalConversationState, note: TodayConversationStore.conversationNote(in: notes, context: modelContext), context: modelContext)
            return result
        } catch {
            globalAgentError = error.localizedDescription
            return "Could not save changes: \(error.localizedDescription)"
        }
    }

    private func conversationAccountChanged(_ notification: Notification) {
        guard let id = notification.object as? String, globalConversationState.accountID != id else { return }
        globalAgentTask?.cancel()
        activeConversationRequestID = nil
        isGlobalAgentSending = false
        globalAgentDraft = ""
        globalConversationProposal = nil
        navigation.selectedTaskID = nil
        globalConversationState.prepareForAccount(id)
        persistGlobalConversation()
    }

    private func selectConversationResource(_ id: UUID, shared: Bool) {
        globalConversationState = TodayConversationStore.decode(TodayConversationStore.conversationNote(in: notes, context: modelContext))
        var selected = Set(globalConversationState.sharedResourceIDs ?? [])
        if shared { selected.insert(id) } else { selected.remove(id) }
        globalConversationState.sharedResourceIDs = Array(selected.prefix(4))
        globalConversationState.toolResults = (globalConversationState.toolResults ?? []).filter { !$0.hasPrefix("read_selected_resource:") }
        persistGlobalConversation()
    }

    private var undoCreationHandler: (() -> Void)? {
        guard globalConversationState.creationReceipt != nil else { return nil }
        return { undoConversationCreation() }
    }

    private func undoConversationCreation() {
        guard globalConversationState.accountID == AccountSyncService().conversationAccountID() else { return }
        do { try ConversationActionExecutor.undoCreation(state: &globalConversationState, note: TodayConversationStore.conversationNote(in: notes, context: modelContext), context: modelContext) }
        catch { globalAgentError = error.localizedDescription }
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
