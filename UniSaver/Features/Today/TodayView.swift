import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var agentResources: [AcademicResource]
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \ClassSession.startTime) private var sessions: [ClassSession]
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query(sort: \StudyBlock.startDate) private var studyBlocks: [StudyBlock]
    @Query(sort: \ReadingProgress.lastOpenedAt, order: .reverse) private var readingProgress: [ReadingProgress]
    @Query(sort: \Flashcard.updatedAt, order: .reverse) private var flashcards: [Flashcard]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query private var workspaces: [AppWorkspace]

    @Binding var quickAddTarget: QuickAddTarget?
    @State private var selectedDate = Date()
    @State private var showsCompletedTasks = false
    @State private var showsWorkspaceChooser = false
    @State private var isPreparingWorkspace = false
    @State private var moodleTaskIDs: Set<UUID> = []
    @State private var gamificationLedger = GamificationLedger()
    @State private var completionMessage: String?
    @AppStorage("todayConversationDraft") private var conversationDraft = ""
    @State private var conversationState = TodayConversationState()
    @State private var conversationProposal: ConversationAnalysisProposal?
    @State private var activeConversationRequestID: UUID?
    @State private var isAnalyzingConversation = false
    @State private var conversationError: String?
    @State private var appliedConversationIDs: Set<String> = []
    @State private var conversationTask: Task<Void, Never>?
    @State private var showsConversationDetail = false
    @State private var taskExecutionLedger = TaskExecutionLedger()
    @State private var activeWorkTask: AcademicTask?
    @State private var showsTodoWorkspace = false

    private var snapshot: TodayDashboardSnapshot {
        TodayDashboardService.makeSnapshot(
            selectedDate: selectedDate,
            workspace: workspaces.first,
            courses: courses,
            sessions: sessions,
            tasks: visibleTasks,
            exams: exams,
            studyBlocks: studyBlocks,
            readingProgress: readingProgress,
            flashcardsDue: flashcards
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
            moodleTaskIDs: moodleTaskIDs,
            onLoadDemo: {
                DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                showsWorkspaceChooser = false
                selectedDate = .now
            },
            onShowWorkspaceChooser: { showsWorkspaceChooser = true },
            onOpenCourse: { course, tab in navigation.openCourse(course, tab: tab) },
            onOpenStudy: { navigation.requestSelect(.study) },
            onCompleteTask: { task in
                setTask(task, completed: true)
            },
            gamificationSummary: GamificationEngine.weeklySummary(tasks: tasks, ledger: gamificationLedger),
            quests: GamificationEngine.quests(tasks: tasks, studyBlocks: studyBlocks, flashcards: flashcards, ledger: gamificationLedger),
            completionMessage: completionMessage,
            onStartQuest: startQuest,
            onCompleteQuest: completeQuest,
            onReplaceQuest: replaceQuest,
            onPostponeQuest: postponeQuest,
            onReduceGoals: reduceGoals,
            onWeeklyGoalChange: updateWeeklyGoal,
            onToggleGamificationHidden: toggleGamificationHidden,
            conversationDraft: $conversationDraft,
            conversationState: conversationState,
            isAnalyzingConversation: isAnalyzingConversation,
            conversationError: conversationError,
            onAnalyzeConversation: analyzeConversation,
            onCancelConversation: cancelConversation,
            onOpenConversation: { showsConversationDetail = true },
            onNewConversation: clearConversation,
            onOpenConversationProposal: openConversationProposal,
            onOpenTodo: { showsTodoWorkspace = true }
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
        .sheet(item: $conversationProposal) { proposal in
            ConversationProposalReviewSheet(
                proposal: proposal,
                courses: courses,
                onCancel: { conversationProposal = nil },
                onApply: applyConversationProposal,
                onEditProposal: retainConversationProposal
            )
        }
        .sheet(isPresented: $showsConversationDetail) {
            TodayConversationDetailSheet(
                draft: $conversationDraft,
                state: conversationState,
                isSending: isAnalyzingConversation,
                errorMessage: conversationError,
                onSend: analyzeConversation,
                onCancel: cancelConversation,
                onNewConversation: clearConversation,
                onOpenProposal: openConversationProposal,
                onUndoCreation: undoCreationHandler,
                sharedResources: agentResources,
                sharedResourceIDs: conversationState.sharedResourceIDs ?? [],
                onSelectResource: selectConversationResource
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .uniSaverConversationAccountChanged), perform: conversationAccountChanged)
        .onChange(of: activeWorkTask?.id) { _, id in navigation.selectedTaskID = id }
        .onChange(of: activeWorkTask?.id) { _, _ in
            if let task = activeWorkTask { navigation.focusTask = task; activeWorkTask = nil }
        }
        .sheet(isPresented: $showsTodoWorkspace) {
            TodoWorkspaceSheet(
                tasks: tasks,
                onStartTask: { task in
                    showsTodoWorkspace = false
                    Task { @MainActor in
                        activeWorkTask = task
                    }
                },
                onUpdateTask: { task, status in
                    if status == .completed {
                        setTask(task, completed: true)
                    } else {
                        task.status = status
                        task.updatedAt = .now
                        GamificationLedgerStore.annul(activityType: .taskCompletion, sourceID: task.id.uuidString, ledger: &gamificationLedger)
                        persistGamification()
                        try? modelContext.save()
                    }
                },
                onDeleteTask: { task in
                    modelContext.delete(task)
                    try? modelContext.save()
                }
            )
        }
        .onAppear {
            showsWorkspaceChooser = workspaces.isEmpty && courses.isEmpty
            moodleTaskIDs = MoodleSyncMetadataStore().remoteIDs(kind: .task)
            gamificationLedger = GamificationLedgerStore.decode(gamificationNote)
            conversationState = TodayConversationStore.decode(conversationNote)
            taskExecutionLedger = TaskExecutionLedgerStore.decode(taskExecutionNote)
            syncEligibleCompletions()
        }
    }

    private var gamificationNote: StudyNote {
        GamificationLedgerStore.ledgerNote(in: notes, context: modelContext)
    }

    private var conversationNote: StudyNote {
        TodayConversationStore.conversationNote(in: notes, context: modelContext)
    }

    private var taskExecutionNote: StudyNote {
        TaskExecutionLedgerStore.ledgerNote(in: notes, context: modelContext)
    }

    private func persistGamification() {
        GamificationLedgerStore.save(gamificationLedger, into: gamificationNote)
        try? modelContext.save()
    }

    private func setTask(_ task: AcademicTask, completed: Bool) {
        task.status = completed ? .completed : .todo
        task.updatedAt = .now
        if completed {
            GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: task.id.uuidString, courseID: task.course?.id, ledger: &gamificationLedger)
            completionMessage = "One step completed."
        } else {
            GamificationLedgerStore.annul(activityType: .taskCompletion, sourceID: task.id.uuidString, ledger: &gamificationLedger)
            completionMessage = nil
        }
        persistGamification()
    }

    private func completeStudyBlock(_ block: StudyBlock) {
        block.status = .completed
        block.updatedAt = .now
        GamificationLedgerStore.award(activityType: .studyBlockCompletion, sourceID: block.id.uuidString, courseID: block.course?.id, ledger: &gamificationLedger)
        completionMessage = "Your weekly plan is moving forward."
        persistGamification()
    }

    private func startQuest(_ quest: DailyQuest) {
        switch quest.kind {
        case .task, .comeback:
            if let taskID = UUID(uuidString: quest.sourceID),
               let task = tasks.first(where: { $0.id == taskID }) {
                if task.status == .todo {
                    task.status = .inProgress
                    task.updatedAt = .now
                    try? modelContext.save()
                }
                activeWorkTask = task
            } else {
                NotificationCenter.default.post(name: .openPlannerTasks, object: PlannerTaskFilter.all)
            }
        case .studyBlock:
            NotificationCenter.default.post(name: .selectAppSection, object: AppSection.planner)
        case .practice:
            navigation.requestSelect(.study)
        }
    }

    private func completeQuest(_ quest: DailyQuest) {
        switch quest.kind {
        case .task, .comeback:
            guard let taskID = UUID(uuidString: quest.sourceID),
                  let task = tasks.first(where: { $0.id == taskID }) else { return }
            setTask(task, completed: true)
        case .studyBlock:
            guard let blockID = UUID(uuidString: quest.sourceID),
                  let block = studyBlocks.first(where: { $0.id == blockID }) else { return }
            completeStudyBlock(block)
        case .practice:
            navigation.requestSelect(.study)
        }
    }

    private func replaceQuest(_ quest: DailyQuest) {
        gamificationLedger.settings.dismissedQuestIDs.append(quest.id)
        persistGamification()
    }

    private func postponeQuest(_ quest: DailyQuest) {
        gamificationLedger.settings.postponedQuestIDs[quest.id] = .now
        persistGamification()
    }

    private func reduceGoals() {
        gamificationLedger.settings.weeklyActiveDayGoal = max(1, gamificationLedger.settings.weeklyActiveDayGoal - 1)
        gamificationLedger.settings.comebackAfterInactiveDays += 1
        persistGamification()
    }

    private func updateWeeklyGoal(_ value: Int) {
        gamificationLedger.settings.weeklyActiveDayGoal = min(max(value, 1), 7)
        persistGamification()
    }

    private func toggleGamificationHidden() {
        gamificationLedger.settings.isGamificationHidden.toggle()
        persistGamification()
    }

    private func syncEligibleCompletions() {
        var changed = false
        for task in tasks where task.status == .completed {
            let before = gamificationLedger.events
            GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: task.id.uuidString, courseID: task.course?.id, occurredAt: task.updatedAt, ledger: &gamificationLedger)
            changed = changed || before != gamificationLedger.events
        }
        for block in studyBlocks where block.status == .completed {
            let before = gamificationLedger.events
            GamificationLedgerStore.award(activityType: .studyBlockCompletion, sourceID: block.id.uuidString, courseID: block.course?.id, occurredAt: block.updatedAt, ledger: &gamificationLedger)
            changed = changed || before != gamificationLedger.events
        }
        if changed {
            persistGamification()
        }
    }

    private func analyzeConversation() {
        let message = conversationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            conversationError = "Tell UniSaver what changed first."
            return
        }
        conversationTask?.cancel()
        let requestID = UUID()
        activeConversationRequestID = requestID
        isAnalyzingConversation = true
        conversationError = nil

        conversationTask = Task { @MainActor in
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
                conversationState = current
                persistConversation()
                let provider = try AIRevisionAssistantClient().conversationProvider()
                let sharedIDs = Set(current.sharedResourceIDs ?? [])
                let sources = try TaskWorkspaceService.sources(resources: agentResources.filter { sharedIDs.contains($0.id) }, query: message)
                let service = ConversationProviderService(courses: courses, tasks: tasks, studyBlocks: studyBlocks,
                    page: navigation.selectedSection.rawValue, selectedCourseID: navigation.openedCourseID ?? navigation.libraryCourseID,
                    selectedTaskID: navigation.selectedTaskID, selectedSources: sources, classSessions: sessions, exams: exams)
                let result = try await service.respond(state: current, provider: provider, performCreation: { proposal in
                    guard activeConversationRequestID == requestID, !Task.isCancelled,
                          AccountSyncService().conversationAccountID() == accountID else { throw CancellationError() }
                    let saved = try ConversationActionExecutor.apply(proposal, state: &conversationState, note: conversationNote, context: modelContext)
                    let result: [String: Any] = ["status": "saved", "result": saved,
                        "task_ids": conversationState.lastExecutionTaskIDs?.map(\.uuidString) ?? []]
                    return String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
                }, refreshTasks: { try modelContext.fetch(FetchDescriptor<AcademicTask>()) })
                try Task.checkCancellation()
                guard activeConversationRequestID == requestID else { return }
                let latest = await AccountSyncService().restoreSession()
                let latestID: String
                if case .signedIn(let account) = latest { latestID = account.stableUserID } else { latestID = "local-signed-out" }
                guard latestID == accountID else {
                    conversationState = TodayConversationState()
                    isAnalyzingConversation = false
                    persistConversation()
                    return
                }
                conversationState = TodayConversationStore.decode(TodayConversationStore.conversationNote(in: notes, context: modelContext))
                if conversationDraft == message { conversationDraft = "" }
                if let proposal = result.proposal {
                    if let previousID = proposal.supersedesProposalID {
                        conversationState.pendingProposals.removeValue(forKey: previousID)
                        conversationState.supersededProposalIDs = Array(Set((conversationState.supersededProposalIDs ?? []) + [previousID]))
                    }
                    conversationState.pendingProposals[proposal.id] = proposal
                }
                conversationState.messages.append(TodayConversationMessage(role: .agent, text: result.text, proposalID: result.proposal?.id))
                conversationState.toolResults = Array(((conversationState.toolResults ?? []) + result.toolResults).suffix(12))

                isAnalyzingConversation = false
                activeConversationRequestID = nil
                persistConversation()
            } catch is CancellationError {
                guard activeConversationRequestID == requestID else { return }
                activeConversationRequestID = nil
                isAnalyzingConversation = false
                if conversationDraft.isEmpty { conversationDraft = message }
            } catch {
                guard !Task.isCancelled, activeConversationRequestID == requestID else { return }
                activeConversationRequestID = nil
                isAnalyzingConversation = false
                conversationError = error.localizedDescription
                if conversationDraft.isEmpty { conversationDraft = message }
                conversationState.messages.append(TodayConversationMessage(role: .system, text: error.localizedDescription, isError: true))
                persistConversation()
            }
        }
    }

    private func cancelConversation() {
        activeConversationRequestID = nil
        conversationTask?.cancel()
        conversationTask = nil
        isAnalyzingConversation = false
        conversationState.messages.append(TodayConversationMessage(role: .system, text: "Request cancelled."))
        persistConversation()
    }

    private func clearConversation() {
        activeConversationRequestID = nil
        conversationTask?.cancel()
        conversationDraft = ""
        conversationError = nil
        isAnalyzingConversation = false
        conversationState = TodayConversationState()
        persistConversation()
    }

    private func openConversationProposal(_ proposalID: String) {
        guard let proposal = conversationState.pendingProposals[proposalID] else {
            conversationError = "That suggestion is no longer available. Send the message again to rebuild it."
            return
        }
        conversationProposal = proposal
    }

    private func persistConversation() {
        TodayConversationStore.save(conversationState, into: conversationNote)
        do { try modelContext.save() }
        catch { conversationError = "Could not save the conversation: \(error.localizedDescription)" }
    }

    private func saveTaskExecutionLedger(_ ledger: TaskExecutionLedger) throws {
        let note = taskExecutionNote
        let previous = note.body
        TaskExecutionLedgerStore.save(ledger, into: note)
        do {
            try modelContext.save()
            taskExecutionLedger = ledger
        } catch {
            note.body = previous
            throw error
        }
    }

    private func retainConversationProposal(_ proposal: ConversationAnalysisProposal) {
        conversationState = TodayConversationStore.decode(conversationNote)
        guard !(conversationState.appliedProposalIDs ?? []).contains(proposal.id) else { return }
        conversationState.pendingProposals[proposal.id] = proposal
        persistConversation()
    }

    private func applyConversationProposal(_ proposal: ConversationAnalysisProposal) -> String {
        guard conversationState.accountID == AccountSyncService().conversationAccountID() else { return "Account changed. Send the request again in the current account." }
        do {
            let result = try ConversationActionExecutor.apply(proposal, state: &conversationState, note: conversationNote, context: modelContext)
            return result
        } catch {
            conversationError = error.localizedDescription
            return "Could not save changes: \(error.localizedDescription)"
        }
    }

    private func conversationAccountChanged(_ notification: Notification) {
        guard let id = notification.object as? String, conversationState.accountID != id else { return }
        conversationTask?.cancel()
        activeConversationRequestID = nil
        isAnalyzingConversation = false
        conversationDraft = ""
        conversationProposal = nil
        navigation.selectedTaskID = nil
        conversationState.prepareForAccount(id)
        persistConversation()
    }

    private func selectConversationResource(_ id: UUID, shared: Bool) {
        conversationState = TodayConversationStore.decode(conversationNote)
        var selected = Set(conversationState.sharedResourceIDs ?? [])
        if shared { selected.insert(id) } else { selected.remove(id) }
        conversationState.sharedResourceIDs = Array(selected.prefix(4))
        conversationState.toolResults = (conversationState.toolResults ?? []).filter { !$0.hasPrefix("read_selected_resource:") }
        persistConversation()
    }

    private var undoCreationHandler: (() -> Void)? {
        guard conversationState.creationReceipt != nil else { return nil }
        return { undoConversationCreation() }
    }

    private func undoConversationCreation() {
        guard conversationState.accountID == AccountSyncService().conversationAccountID() else { return }
        do { try ConversationActionExecutor.undoCreation(state: &conversationState, note: conversationNote, context: modelContext) }
        catch { conversationError = error.localizedDescription }
    }


}

struct TodayDashboardView: View {
    let snapshot: TodayDashboardSnapshot
    @Binding var showsCompletedTasks: Bool
    @Binding var selectedDate: Date
    @Binding var quickAddTarget: QuickAddTarget?
    let moodleTaskIDs: Set<UUID>
    let onLoadDemo: () -> Void
    let onShowWorkspaceChooser: () -> Void
    let onOpenCourse: (Course, CourseWorkspaceTab) -> Void
    let onOpenStudy: () -> Void
    let onCompleteTask: (AcademicTask) -> Void
    let gamificationSummary: WeeklyGamificationSummary
    let quests: [DailyQuest]
    let completionMessage: String?
    let onStartQuest: (DailyQuest) -> Void
    let onCompleteQuest: (DailyQuest) -> Void
    let onReplaceQuest: (DailyQuest) -> Void
    let onPostponeQuest: (DailyQuest) -> Void
    let onReduceGoals: () -> Void
    let onWeeklyGoalChange: (Int) -> Void
    let onToggleGamificationHidden: () -> Void
    @Binding var conversationDraft: String
    let conversationState: TodayConversationState
    let isAnalyzingConversation: Bool
    let conversationError: String?
    let onAnalyzeConversation: () -> Void
    let onCancelConversation: () -> Void
    let onOpenConversation: () -> Void
    let onNewConversation: () -> Void
    let onOpenConversationProposal: (String) -> Void
    let onOpenTodo: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layoutMode = StudyDeskLayoutMode(contentWidth: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: layoutMode.cardSpacing) {
                    TodayMockupHeader(
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
                    } else {
                        TodayHomeGrid(
                            snapshot: snapshot,
                            selectedDate: $selectedDate,
                            quickAddTarget: $quickAddTarget,
                            conversationDraft: $conversationDraft,
                            conversationState: conversationState,
                            isAnalyzingConversation: isAnalyzingConversation,
                            conversationError: conversationError,
                            onAnalyzeConversation: onAnalyzeConversation,
                            onCancelConversation: onCancelConversation,
                            onOpenConversation: onOpenConversation,
                            onNewConversation: onNewConversation,
                            onOpenConversationProposal: onOpenConversationProposal,
                            onOpenTodo: onOpenTodo,
                            quests: quests,
                            summary: gamificationSummary,
                            completionMessage: completionMessage,
                            onStartQuest: onStartQuest,
                            onCompleteQuest: onCompleteQuest,
                            onReplaceQuest: onReplaceQuest,
                            onPostponeQuest: onPostponeQuest,
                            onWeeklyGoalChange: onWeeklyGoalChange,
                            onOpenCourse: onOpenCourse,
                            onOpenStudy: onOpenStudy,
                            moodleTaskIDs: moodleTaskIDs
                        )
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
                        quickAddTarget: $quickAddTarget,
                        moodleTaskIDs: moodleTaskIDs
                    )
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(layoutMode == .tabletExpanded ? 1.4 : 1.2)

                VStack(spacing: StudyDeskTheme.spacing) {
                    NextClassCard(session: snapshot.nextSession, layoutMode: layoutMode, onOpenCourse: onOpenCourse)
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
                NextClassCard(session: snapshot.nextSession, layoutMode: layoutMode, onOpenCourse: onOpenCourse)
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
                            quickAddTarget: $quickAddTarget,
                            moodleTaskIDs: moodleTaskIDs
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
                NextClassCard(session: snapshot.nextSession, layoutMode: layoutMode, onOpenCourse: onOpenCourse)
                ScheduleTimeline(items: snapshot.timelineItems, quickAddTarget: $quickAddTarget)
                PriorityTaskList(
                    tasks: snapshot.priorityTasks,
                    showsCompletedTasks: $showsCompletedTasks,
                    quickAddTarget: $quickAddTarget,
                    moodleTaskIDs: moodleTaskIDs
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

struct TodayMockupHeader: View {
    let firstName: String
    @Binding var selectedDate: Date
    let layoutMode: StudyDeskLayoutMode

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What’s up, \(firstName)?")
                    .font(.system(size: layoutMode == .compact ? 26 : 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudyDeskTheme.textPrimary)
                    .lineLimit(2)
                Text(UniDateFormatters.fullDate.string(from: selectedDate))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(StudyDeskTheme.textSecondary)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: .selectAppSection, object: AppSection.planner)
                } label: {
                    Image(systemName: "bell")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(StudyDeskTheme.surfacePrimary, in: Circle())
                        .overlay(Circle().stroke(StudyDeskTheme.borderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open planner notifications")

                Text(String(firstName.prefix(1)).uppercased())
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [StudyDeskTheme.accentPrimary, .purple.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .accessibilityLabel("Profile for \(firstName)")
            }
        }
    }
}

struct TodayHomeGrid: View {
    let snapshot: TodayDashboardSnapshot
    @Binding var selectedDate: Date
    @Binding var quickAddTarget: QuickAddTarget?
    @Binding var conversationDraft: String
    let conversationState: TodayConversationState
    let isAnalyzingConversation: Bool
    let conversationError: String?
    let onAnalyzeConversation: () -> Void
    let onCancelConversation: () -> Void
    let onOpenConversation: () -> Void
    let onNewConversation: () -> Void
    let onOpenConversationProposal: (String) -> Void
    let onOpenTodo: () -> Void
    let quests: [DailyQuest]
    let summary: WeeklyGamificationSummary
    let completionMessage: String?
    let onStartQuest: (DailyQuest) -> Void
    let onCompleteQuest: (DailyQuest) -> Void
    let onReplaceQuest: (DailyQuest) -> Void
    let onPostponeQuest: (DailyQuest) -> Void
    let onWeeklyGoalChange: (Int) -> Void
    let onOpenCourse: (Course, CourseWorkspaceTab) -> Void
    let onOpenStudy: () -> Void
    let moodleTaskIDs: Set<UUID>

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                mainColumn
                    .frame(maxWidth: .infinity)
                sideColumn
                    .frame(width: 320)
            }
            VStack(alignment: .leading, spacing: 18) {
                mainColumn
                sideColumn
            }
        }
        CompactWeekOverviewStrip(
            overview: snapshot.weeklyOverview,
            selectedDate: $selectedDate,
            onOpenCourse: onOpenCourse,
            onOpenStudy: onOpenStudy,
            moodleTaskIDs: moodleTaskIDs
        )
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            AgentConversationCard(
                draft: $conversationDraft,
                state: conversationState,
                isSending: isAnalyzingConversation,
                errorMessage: conversationError,
                onSend: onAnalyzeConversation,
                onCancel: onCancelConversation,
                onOpenConversation: onOpenConversation,
                onNewConversation: onNewConversation,
                onOpenProposal: onOpenConversationProposal
            )
            FocusMissionPanel(
                quests: quests,
                completionMessage: completionMessage,
                onStartQuest: onStartQuest,
                onCompleteQuest: onCompleteQuest,
                onReplaceQuest: onReplaceQuest,
                onPostponeQuest: onPostponeQuest,
                onAddTask: { quickAddTarget = .task(nil, nil, nil) },
                onOpenTodo: onOpenTodo
            )
        }
    }

    private var sideColumn: some View {
        VStack(spacing: 16) {
            WeeklyActivityPanel(summary: summary, onWeeklyGoalChange: onWeeklyGoalChange)
            UpcomingDeadlinesPanel(
                overview: snapshot.weeklyOverview,
                assignmentDue: snapshot.assignmentDue,
                upcomingExam: snapshot.upcomingExam,
                onOpenCourse: onOpenCourse
            )
        }
    }
}

struct AgentConversationCard: View {
    @Binding var draft: String
    let state: TodayConversationState
    let isSending: Bool
    let errorMessage: String?
    let onSend: () -> Void
    let onCancel: () -> Void
    let onOpenConversation: () -> Void
    let onNewConversation: () -> Void
    let onOpenProposal: (String) -> Void

    private var previewMessages: [TodayConversationMessage] {
        if state.messages.isEmpty {
            return [TodayConversationMessage(role: .agent, text: "Tell me what’s on your mind. We’ll work out the next step together.")]
        }
        return Array(state.messages.suffix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("UniSaver agent", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StudyDeskTheme.accentPrimary)
                Spacer()
                Button("Open conversation", action: onOpenConversation)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(StudyDeskTheme.accentPrimary)
                Menu {
                    Button("Start new conversation", action: onNewConversation)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .controlSize(.small)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(previewMessages) { message in
                        ConversationBubble(message: message, isPreview: true, onOpenProposal: onOpenProposal)
                    }
                    if isSending {
                        Label("Thinking…", systemImage: "ellipsis")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 190)

            if let errorMessage {
                HStack {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                    Button("Retry", action: onSend)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            MessageComposer(draft: $draft, isSending: isSending, onSend: onSend, onCancel: onCancel)
        }
        .padding(18)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
        .shadow(color: StudyDeskTheme.shadow.opacity(0.65), radius: 18, y: 8)
    }
}

struct MessageComposer: View {
    @Binding var draft: String
    let isSending: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(systemName: "paperclip")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
                .help("Attachments are available in import flows; this composer handles text.")
            TextEditor(text: $draft)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 38, maxHeight: 84)
                .overlay(alignment: .topLeading) {
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Talk to your agent…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            if !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Turn into tasks") {
                    let input = ConversationPlanningRequest.classify(draft, hasPlan: false)
                    if !input.permitsPlan { draft = ConversationPlanningRequest.taskCommand(for: draft) }
                    onSend()
                }.controlSize(.small)
            }
            if isSending {
                Button(action: onCancel) {
                    Image(systemName: "stop.fill")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Stop")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            LinearGradient(colors: [StudyDeskTheme.accentPrimary, .purple.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send message")
            }
        }
        .padding(10)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudyDeskTheme.accentPrimary.opacity(0.20), lineWidth: 1)
        }
    }
}

struct ConversationBubble: View {
    let message: TodayConversationMessage
    var isPreview = false
    let onOpenProposal: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role != .student {
                agentAvatar
            } else {
                Spacer(minLength: isPreview ? 70 : 120)
            }
            VStack(alignment: message.role == .student ? .trailing : .leading, spacing: 7) {
                if message.role != .student {
                    Text("UniSaver agent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                }
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(message.isError ? .red : StudyDeskTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textSelection(.enabled)
                if let proposalID = message.proposalID {
                    Button {
                        onOpenProposal(proposalID)
                    } label: {
                        Label("See suggested changes", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if message.role == .student {
                Text("A")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(StudyDeskTheme.accentPrimary.opacity(0.75), in: Circle())
            } else {
                Spacer(minLength: isPreview ? 40 : 100)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var agentAvatar: some View {
        Image(systemName: message.role == .system ? "info.circle" : "sparkles")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(colors: [StudyDeskTheme.accentPrimary.opacity(0.72), .purple.opacity(0.64)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
    }

    private var bubbleBackground: some ShapeStyle {
        if message.role == .student {
            return AnyShapeStyle(StudyDeskTheme.accentPrimary.opacity(0.12))
        }
        if message.role == .system {
            return AnyShapeStyle(.orange.opacity(0.12))
        }
        return AnyShapeStyle(StudyDeskTheme.surfaceTinted)
    }
}

struct FocusMissionPanel: View {
    let quests: [DailyQuest]
    let completionMessage: String?
    let onStartQuest: (DailyQuest) -> Void
    let onCompleteQuest: (DailyQuest) -> Void
    let onReplaceQuest: (DailyQuest) -> Void
    let onPostponeQuest: (DailyQuest) -> Void
    let onAddTask: () -> Void
    let onOpenTodo: () -> Void

    private var primaryQuest: DailyQuest? { quests.first }
    private var supportingQuests: [DailyQuest] { Array(quests.dropFirst().prefix(2)) }

    var body: some View {
        VStack(spacing: 0) {
            if let quest = primaryQuest {
                ZStack(alignment: .trailing) {
                    missionGradient
                    OrbitDecoration()
                        .frame(width: 300, height: 190)
                        .padding(.trailing, 18)
                        .opacity(0.72)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Focus Mission", systemImage: "target")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(StudyDeskTheme.accentPrimary)
                            Spacer()
                            Button("Open To-do", action: onOpenTodo)
                                .font(.caption.weight(.medium))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your next small win")
                                .font(.subheadline)
                            Text(quest.title)
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 14) {
                            if let minutes = quest.estimatedMinutes, minutes > 0 {
                                Label("\(minutes) min", systemImage: "clock")
                            }
                            Label(quest.courseTitle, systemImage: "book")
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        Button {
                            onStartQuest(quest)
                        } label: {
                            Label("Start task", systemImage: "play.fill")
                                .frame(minWidth: 150)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudyDeskTheme.accentPrimary)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 230)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Focus Mission", systemImage: "target")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(StudyDeskTheme.accentPrimary)
                        Spacer()
                        Button("Open To-do", action: onOpenTodo)
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Text("Choose your first small step.")
                        .font(.title3.weight(.semibold))
                    Text("Add a task or tell your agent what changed. UniSaver will not invent work to fill this space.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Add task", action: onAddTask)
                        .buttonStyle(.borderedProminent)
                        .tint(StudyDeskTheme.accentPrimary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(missionGradient)
            }

            if let completionMessage {
                Label(completionMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyDeskTheme.surfacePrimary)
            }

            ForEach(supportingQuests) { quest in
                SupportingMissionRow(
                    quest: quest,
                    onStart: { onStartQuest(quest) },
                    onComplete: { onCompleteQuest(quest) },
                    onReplace: { onReplaceQuest(quest) },
                    onPostpone: { onPostponeQuest(quest) }
                )
                if quest.id != supportingQuests.last?.id {
                    Divider().padding(.leading, 74)
                }
            }
        }
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
        .shadow(color: StudyDeskTheme.shadow.opacity(0.55), radius: 18, y: 8)
    }

    private var missionGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.86, green: 0.93, blue: 1.0), Color(red: 0.91, green: 0.87, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct SupportingMissionRow: View {
    let quest: DailyQuest
    let onStart: () -> Void
    let onComplete: () -> Void
    let onReplace: () -> Void
    let onPostpone: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(quest.title)")
            Image(systemName: quest.kind == .practice ? "rectangle.stack" : "doc.text")
                .foregroundStyle(StudyDeskTheme.accentPrimary)
                .frame(width: 36, height: 36)
                .background(StudyDeskTheme.accentPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(quest.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(quest.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let minutes = quest.estimatedMinutes, minutes > 0 {
                Label("\(minutes) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(action: onStart) {
                Image(systemName: "chevron.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(quest.title)")
            Menu {
                Button("Choose another task", action: onReplace)
                Button("Postpone today", action: onPostpone)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(StudyDeskTheme.surfacePrimary)
    }
}

struct OrbitDecoration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Ellipse()
                    .stroke(.white.opacity(0.42), lineWidth: 1)
                    .frame(width: 210 + CGFloat(index * 38), height: 72 + CGFloat(index * 22))
                    .rotationEffect(.degrees(Double(index) * 24 - 14))
            }
            Circle()
                .fill(RadialGradient(colors: [.white, StudyDeskTheme.accentPrimary.opacity(0.52)], center: .topLeading, startRadius: 2, endRadius: 56))
                .frame(width: 108, height: 108)
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill([Color.cyan, StudyDeskTheme.accentPrimary, .purple, .blue, .mint][index].opacity(0.55))
                    .frame(width: index == 0 ? 22 : 16, height: index == 0 ? 22 : 16)
                    .offset(x: [-118, -56, 88, 134, -96][index], y: [-18, 42, -50, 48, 74][index])
            }
        }
        .accessibilityHidden(true)
    }
}

struct WeeklyActivityPanel: View {
    let summary: WeeklyGamificationSummary
    let onWeeklyGoalChange: (Int) -> Void
    @State private var isEditingGoal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Your week")
                    .font(.headline)
                Spacer()
                Button("Edit goal") { isEditingGoal = true }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ZStack {
                Circle()
                    .stroke(StudyDeskTheme.surfaceTinted, lineWidth: 16)
                Circle()
                    .trim(from: 0, to: min(max(Double(summary.activeDays) / Double(max(summary.activeDayGoal, 1)), 0), 1))
                    .stroke(StudyDeskTheme.accentPrimary, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("\(summary.activeDays) / \(summary.activeDayGoal)")
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                    Text("active days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 36, height: 36)
                    .background(.yellow.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(summary.totalXP) XP")
                        .font(.headline)
                    Text(encouragement)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(18)
        .deskCard()
        .confirmationDialog("Weekly active-day goal", isPresented: $isEditingGoal) {
            ForEach(1...7, id: \.self) { value in
                Button("\(value) day\(value == 1 ? "" : "s") per week") {
                    onWeeklyGoalChange(value)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var encouragement: String {
        let remaining = max(summary.activeDayGoal - summary.activeDays, 0)
        if summary.activeDays == 0 { return "Start with one useful activity." }
        if remaining == 0 { return "Your weekly goal is complete." }
        return "\(remaining) more active day\(remaining == 1 ? "" : "s") to complete your goal."
    }
}

struct UpcomingDeadlinesPanel: View {
    let overview: WeeklyOverview
    let assignmentDue: AcademicTask?
    let upcomingExam: Exam?
    let onOpenCourse: (Course, CourseWorkspaceTab) -> Void

    private var deadlineItems: [DeadlineItem] {
        var items = overview.overdueTasks.map { DeadlineItem(task: $0, isOverdue: true) }
        items += overview.upcomingTasks.map { DeadlineItem(task: $0, isOverdue: false) }
        if let assignmentDue, !items.contains(where: { $0.id == assignmentDue.id.uuidString }) {
            items.append(DeadlineItem(task: assignmentDue, isOverdue: false))
        }
        if let upcomingExam {
            items.append(DeadlineItem(exam: upcomingExam))
        }
        return Array(items.sorted { $0.date < $1.date }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Upcoming deadlines")
                    .font(.headline)
                Spacer()
                Button("View all") {
                    NotificationCenter.default.post(name: .openPlannerTasks, object: PlannerTaskFilter.all)
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(StudyDeskTheme.accentPrimary)
            }
            if deadlineItems.isEmpty {
                Text("No confirmed deadlines this week.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 12) {
                    ForEach(deadlineItems) { item in
                        Button {
                            if let course = item.course {
                                onOpenCourse(course, .overview)
                            } else {
                                NotificationCenter.default.post(name: .openPlannerTasks, object: PlannerTaskFilter.all)
                            }
                        } label: {
                            DeadlineRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .deskCard()
    }
}

struct DeadlineItem: Identifiable {
    var id: String
    var title: String
    var courseName: String
    var date: Date
    var tint: Color
    var systemImage: String
    var isTentative: Bool
    var course: Course?

    init(task: AcademicTask, isOverdue: Bool) {
        id = task.id.uuidString
        title = task.title
        courseName = task.course?.name ?? "General"
        date = task.dueDate
        tint = isOverdue ? .red : StudyDeskTheme.accentPrimary
        systemImage = isOverdue ? "exclamationmark.triangle" : "doc.text"
        isTentative = task.taskDescription.localizedCaseInsensitiveContains("Needs confirmation")
        course = task.course
    }

    init(exam: Exam) {
        id = exam.id.uuidString
        title = exam.title
        courseName = exam.course?.name ?? "Exam"
        date = exam.date
        tint = .purple
        systemImage = "doc.text.magnifyingglass"
        isTentative = false
        course = exam.course
    }
}

struct DeadlineRow: View {
    let item: DeadlineItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.tint)
                .frame(width: 34, height: 34)
                .background(item.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if item.isTentative {
                        Text("Needs confirmation")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                }
                Text(item.courseName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(TodayDateDisplay.deadline(item.date))
                    .font(.caption.weight(.medium))
            }
        }
    }
}

enum TodayDateDisplay {
    static func deadline(_ date: Date) -> String {
        if date == .distantFuture { return "No deadline supplied" }
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        if (components.hour ?? 0) == 0, (components.minute ?? 0) == 0, (components.second ?? 0) == 0 {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct CompactWeekOverviewStrip: View {
    let overview: WeeklyOverview
    @Binding var selectedDate: Date
    let onOpenCourse: (Course, CourseWorkspaceTab) -> Void
    let onOpenStudy: () -> Void
    let moodleTaskIDs: Set<UUID>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("This week")
                    .font(.headline)
                Text("\(UniDateFormatters.dayMonth.string(from: overview.weekInterval.start)) - \(UniDateFormatters.dayMonth.string(from: overview.weekInterval.end.addingTimeInterval(-1)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 150, alignment: .leading)
            ForEach(overview.days) { day in
                Button {
                    selectedDate = day.date
                } label: {
                    VStack(spacing: 5) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(.medium))
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.callout.weight(.semibold))
                        HStack(spacing: 4) {
                            if !day.sessions.isEmpty {
                                Circle().fill(.gray.opacity(0.55)).frame(width: 6, height: 6)
                            }
                            if !day.tasks.isEmpty {
                                Circle().fill(StudyDeskTheme.accentPrimary).frame(width: 6, height: 6)
                            }
                            if !day.flashcards.isEmpty {
                                Circle().fill(.green).frame(width: 6, height: 6)
                            }
                        }
                        .frame(height: 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Calendar.current.isDate(day.date, inSameDayAs: selectedDate) ? StudyDeskTheme.accentPrimary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(day.date.formatted(date: .complete, time: .omitted))")
            }
            Button {
                NotificationCenter.default.post(name: .selectAppSection, object: AppSection.planner)
            } label: {
                Image(systemName: "arrow.right")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open full planner")
        }
        .padding(16)
        .deskCard()
    }
}

struct TodoWorkspaceSheet: View {
    enum Scope: String, CaseIterable, Identifiable {
        case today = "Today"
        case upcoming = "Upcoming"
        case all = "All"
        case completed = "Completed"

        var id: String { rawValue }
    }

    enum Grouping: String, CaseIterable, Identifiable {
        case course = "By class"
        case status = "By status"
        case assignment = "By assignment"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let tasks: [AcademicTask]
    let onStartTask: (AcademicTask) -> Void
    let onUpdateTask: (AcademicTask, AcademicTaskStatus) -> Void
    let onDeleteTask: (AcademicTask) -> Void
    @State private var scope: Scope = .today
    @State private var grouping: Grouping = .course
    @State private var searchText = ""
    @State private var taskToDelete: AcademicTask?

    private var filteredTasks: [AcademicTask] {
        let calendar = Calendar.current
        let today = calendar.dateInterval(of: .day, for: .now) ?? DateInterval(start: .now, duration: 86_400)
        let nextWeek = DateInterval(start: today.start, duration: 7 * 86_400)
        return tasks.filter { task in
            let matchesScope: Bool
            switch scope {
            case .today:
                matchesScope = task.status != .completed && today.contains(task.dueDate)
            case .upcoming:
                matchesScope = task.status != .completed && nextWeek.contains(task.dueDate)
            case .all:
                matchesScope = task.status != .completed && task.status != .cancelled
            case .completed:
                matchesScope = task.status == .completed
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = query.isEmpty || task.title.lowercased().contains(query) || (task.course?.name.lowercased().contains(query) ?? false)
            return matchesScope && matchesSearch
        }
        .sorted { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status.rawValue < rhs.status.rawValue }
            if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
            return lhs.title < rhs.title
        }
    }

    private var groupedTasks: [(String, [AcademicTask])] {
        let groups = Dictionary(grouping: filteredTasks) { task in
            switch grouping {
            case .course:
                task.course?.name ?? "General"
            case .status:
                task.status.title
            case .assignment:
                assignmentName(for: task)
            }
        }
        return groups.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To-do")
                        .font(.title3.weight(.semibold))
                    Text("Review, start, complete or reopen your academic work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(18)
            .background(StudyDeskTheme.surfacePrimary)
            .overlay(alignment: .bottom) { Divider() }

            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Picker("View", selection: $scope) {
                            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(minWidth: 280)
                        Picker("Grouping", selection: $grouping) {
                            ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(minWidth: 170)
                        TextField("Search tasks", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("View", selection: $scope) {
                            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        HStack {
                            Picker("Grouping", selection: $grouping) {
                                ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            TextField("Search tasks", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if groupedTasks.isEmpty {
                            EmptyStateView(title: "No tasks here", message: "Create or approve work from Today, Planner or a class page.", systemImage: "checklist")
                                .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            ForEach(groupedTasks, id: \.0) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.0)
                                        .font(.headline)
                                    ForEach(group.1) { task in
                                        TodoTaskRow(
                                            task: task,
                                            onStart: { onStartTask(task) },
                                            onComplete: { onUpdateTask(task, .completed) },
                                            onReopen: { onUpdateTask(task, .inProgress) },
                                            onDelete: { taskToDelete = task }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 620)
        .background(StudyDeskTheme.backgroundPrimary)
        .confirmationDialog("Delete task?", isPresented: Binding(
            get: { taskToDelete != nil },
            set: { if !$0 { taskToDelete = nil } }
        )) {
            Button("Delete task", role: .destructive) {
                if let taskToDelete {
                    onDeleteTask(taskToDelete)
                }
                taskToDelete = nil
            }
            Button("Cancel", role: .cancel) { taskToDelete = nil }
        } message: {
            Text("This removes the task record. It does not delete course files or notes.")
        }
    }

    private func assignmentName(for task: AcademicTask) -> String {
        if task.title.localizedCaseInsensitiveContains("HW") { return "Homework" }
        if task.title.localizedCaseInsensitiveContains("test") { return "Exam prep" }
        if task.title.localizedCaseInsensitiveContains("case") { return "Case work" }
        return task.course?.name ?? "General work"
    }
}

struct TodoTaskRow: View {
    let task: AcademicTask
    let onStart: () -> Void
    let onComplete: () -> Void
    let onReopen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: task.status == .completed ? onReopen : onComplete) {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(task.course?.name ?? "General")
                    Text(TaskStructureService.progressLabel(for: task))
                    Text(TodayDateDisplay.deadline(task.dueDate))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Start", action: onStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(task.status == .completed)
            Menu {
                Button(task.status == .completed ? "Reopen" : "Mark done", action: task.status == .completed ? onReopen : onComplete)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .controlSize(.small)
        }
        .padding(12)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }
}

struct TaskWorkSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allNotes: [StudyNote]
    @Query private var workspaceResources: [AcademicResource]
    let task: AcademicTask
    let ledger: TaskExecutionLedger
    let onSaveLedger: (TaskExecutionLedger) throws -> Void
    let onToggleSubtask: (TaskSubtaskItem, Bool) throws -> Void
    let onAddSuggestedSteps: () throws -> Void
    let onUpdateTaskStatus: (AcademicTaskStatus) throws -> Void
    let onClose: () -> Void

    @State private var workingLedger: TaskExecutionLedger
    @State private var timerMode: TaskTimerMode = .elapsed
    @State private var countdownMinutes = 25
    @State private var reviewingSavedSteps = false
    @State private var stepFocusRequest = 0
    @State private var showsStepProposal = false
    @State private var showsReview = false
    @State private var reviewContext = SessionReviewContext()
    @State private var workspace: TaskWorkspaceDraft
    @State private var saveError: String?
    @State private var loaded = false
    @State private var didSaveReview = false
    @State private var isSavingReview = false
    @State private var showsAgent = false
    @State private var showsSteps = false
    @State private var selectedResourceID: UUID?

    init(
        task: AcademicTask,
        ledger: TaskExecutionLedger,
        onSaveLedger: @escaping (TaskExecutionLedger) throws -> Void,
        onToggleSubtask: @escaping (TaskSubtaskItem, Bool) throws -> Void,
        onAddSuggestedSteps: @escaping () throws -> Void,
        onUpdateTaskStatus: @escaping (AcademicTaskStatus) throws -> Void,
        onClose: @escaping () -> Void
    ) {
        self.task = task
        self.ledger = ledger
        self.onSaveLedger = onSaveLedger
        self.onToggleSubtask = onToggleSubtask
        self.onAddSuggestedSteps = onAddSuggestedSteps
        self.onUpdateTaskStatus = onUpdateTaskStatus
        self.onClose = onClose
        _workingLedger = State(initialValue: ledger)
        _workspace = State(initialValue: TaskWorkspaceDraft(taskID: task.id))
    }

    private var subtasks: [TaskSubtaskItem] {
        TaskStructureService.subtasks(from: task)
    }

    private var activeTimer: ActiveTaskTimer? {
        workingLedger.activeTimer?.taskID == task.id ? workingLedger.activeTimer : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    if proxy.size.width >= 1040 {
                        ScrollView { subtasksCard }.frame(width: 250)
                        Divider()
                    }
                    TaskStudyToolsView(task: task, assignment: TaskWorkspaceService.assignment(for: task, notes: allNotes), draft: Binding(
                        get: { workspace },
                        set: { value in workspace = value; if loaded { _ = persistWorkspace(value) } }
                    ), showsAgent: $showsAgent, saveStatus: saveError == nil ? "Saved" : "Couldn’t save", selectedResourceID: $selectedResourceID)
                }
            }
            if let saveError {
                HStack {
                    Text("Couldn’t save: \(saveError)").foregroundStyle(.orange)
                    Button("Retry save") { _ = persistWorkspace() }
                }.font(.caption).padding(8)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StudyDeskTheme.backgroundPrimary)
        .interactiveDismissDisabled()
        .onAppear {
            if !loaded {
                workspace = TaskWorkspaceService.draft(for: task, ledger: workingLedger, notes: allNotes)
                loaded = true
                _ = persistWorkspace()
            }
            if task.status == .todo {
                do { try onUpdateTaskStatus(.inProgress) }
                catch { saveError = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showsSteps) {
            ScrollView { subtasksCard }.frame(idealWidth: 280, minHeight: 400)
        }
        .sheet(isPresented: $showsStepProposal) {
            TaskStepProposalSheet(task: task, onOpenFirstStep: {
                showsStepProposal = false
                stepFocusRequest += 1
                workspace.activeStepID = subtasks.first(where: { !$0.isCompleted })?.id
                _ = persistWorkspace()
            }, existingReceipt: reviewingSavedSteps ? (try? TaskStructureService.approvalReceipts(in: task))?.last : nil)
        }
        .sheet(isPresented: $showsReview) {
            SessionReviewSheet(
                task: task,
                context: reviewContext,
                subtasks: subtasks,
                onReturnToWork: { showsReview = false },
                onSave: saveSessionReview
            )
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Back", systemImage: "chevron.left") {
                    guard persistWorkspace() else { return }; onClose()
                }.help("Return to the previous page; keep this session and notes")
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.headline).lineLimit(2)
                    Text([task.course?.name, TodayDateDisplay.deadline(task.dueDate)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("Steps", systemImage: "checklist") { showsSteps = true }
                Spacer(minLength: 0)
                timerCard
                Button("Agent", systemImage: "sparkles") { showsAgent = true }
            }.controlSize(.small)
        }.padding(12).background(StudyDeskTheme.surfacePrimary)
            .overlay(alignment: .bottom) { Divider() }
    }

    private var subtasksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Steps")
                    .font(.headline)
                Spacer()
                Button("Break into steps") { reviewingSavedSteps = false; showsStepProposal = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if let receipts = try? TaskStructureService.approvalReceipts(in: task), !receipts.isEmpty {
                Button("Review saved steps") { reviewingSavedSteps = true; showsStepProposal = true }
                    .controlSize(.small)

            }
            if subtasks.isEmpty {
                Text("No checklist yet. Paste your assignment instructions to review proposed steps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if let next = subtasks.first(where: { $0.id == workspace.activeStepID }) ?? subtasks.first(where: { !$0.isCompleted }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current step: \(next.title)").font(.headline)
                        if let detail = TaskStructureService.approvedDetail(for: next, in: task) {
                            Text(detail.completionCriterion ?? "").textSelection(.enabled)
                            Text(detail.evidence.title).font(.caption).foregroundStyle(.secondary)
                            if let excerpt = detail.sourceExcerpt {
                                Text("Source: \(excerpt)").font(.caption).textSelection(.enabled)
                            }
                        }

                    }.accessibilityIdentifier("firstIncompleteStep")
                }
                Text("\(subtasks.filter(\.isCompleted).count) of \(subtasks.count) steps completed").font(.caption)
                VStack(spacing: 8) {
                    ForEach(subtasks) { item in
                        Toggle(isOn: Binding(
                            get: { item.isCompleted },
                            set: { value in
                                do { try onToggleSubtask(item, value) }
                                catch { saveError = error.localizedDescription }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Button(item.title) { workspace.activeStepID = item.id; _ = persistWorkspace() }
                                    .buttonStyle(.plain)
                                if item.id == (workspace.activeStepID ?? subtasks.first(where: { !$0.isCompleted })?.id) {
                                    Label("Active step", systemImage: "arrow.right.circle.fill").font(.caption.bold())
                                }
                            }
                        }
                    }
                }
            }
            if !workspace.resourceIDs.isEmpty {
                Divider()
                Text("Resources").font(.subheadline.bold())
                ForEach(workspaceResources.filter { workspace.resourceIDs.contains($0.id) }) { resource in
                    Button(resource.title, systemImage: "doc") { selectedResourceID = resource.id; showsSteps = false }
                        .lineLimit(2).font(.caption)
                }
            }
        }
        .padding()
    }

    private var timerCard: some View {
        Group {
            if let activeTimer {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    HStack {
                        Text(timerDisplay(timer: activeTimer, now: timeline.date)).monospacedDigit().font(.headline)
                            .accessibilityLabel("Timer")
                        Button(activeTimer.isRunning ? "Pause" : "Resume") { togglePause(now: timeline.date) }
                    }
                }
            } else {
                Menu("Start timer") {
                    Button("Elapsed") { timerMode = .elapsed; startTimer() }
                    Button("25 minute countdown") { timerMode = .countdown; countdownMinutes = 25; startTimer() }
                }.help("Optional timer; task completion is chosen in the session review")
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("I’m blocked") { openBlockedReview() }
                .buttonStyle(.bordered)
            Button("Continue later") { guard persistWorkspace() else { return }; onClose() }
                .buttonStyle(.bordered)
            Spacer()
            Button("Finish session") { openReview(finishTask: false) }
                .buttonStyle(.borderedProminent)
                .tint(StudyDeskTheme.accentPrimary)
        }
        .controlSize(.small)
        .padding(12)
        .background(StudyDeskTheme.surfacePrimary)
        .overlay(alignment: .top) { Divider() }
    }

    private func startTimer() {
        if let other = workingLedger.activeTimer, other.taskID != task.id {
            reviewContext.warning = "Another task timer is active. End it before starting this one."
            showsReview = true
            return
        }
        workingLedger.activeTimer = ActiveTaskTimer(
            taskID: task.id,
            mode: timerMode,
            startedAt: .now,
            accumulatedSeconds: 0,
            pauseStartedAt: nil,
            targetSeconds: timerMode == .countdown ? TimeInterval(countdownMinutes * 60) : nil
        )
        _ = persistWorkspace()
    }

    private func togglePause(now: Date = .now) {
        guard var timer = workingLedger.activeTimer, timer.taskID == task.id else { return }
        if timer.pauseStartedAt != nil {
            timer.startedAt = now
            timer.pauseStartedAt = nil
        } else {
            timer.accumulatedSeconds = timer.elapsedSeconds(now: now)
            timer.pauseStartedAt = now
        }
        workingLedger.activeTimer = timer
        _ = persistWorkspace()
    }

    private func openReview(finishTask: Bool, now: Date = .now) {
        let timer = activeTimer
        reviewContext = SessionReviewContext(
            recordedSeconds: timer?.elapsedSeconds(now: now),
            finishTask: finishTask,
            note: workspace.notes,
            remainingWork: workspace.remainingWork
        )
        if timer?.mode == .countdown, timer?.remainingSeconds(now: now) == 0 {
            reviewContext.warning = "The countdown reached zero. Review what happened; UniSaver will not finish the task automatically."
        }
        showsReview = true
    }

    private func openBlockedReview() {
        reviewContext = SessionReviewContext(
            recordedSeconds: activeTimer?.elapsedSeconds(),
            finishTask: false,
            blocker: .dontUnderstand,
            note: workspace.notes,
            remainingWork: workspace.remainingWork
        )
        showsReview = true
    }

    private func saveSessionReview(_ context: SessionReviewContext) throws {
        guard !didSaveReview, !isSavingReview else { return }
        isSavingReview = true
        defer { isSavingReview = false }
        let previousLedger = workingLedger
        let previousStatus = task.status
        let record = TaskExecutionRecord(
            id: workspace.sessionID,
            taskID: task.id,
            courseID: task.course?.id,
            startedAt: workspace.startedAt,
            endedAt: .now,
            recordedSeconds: context.recordedSeconds,
            completedSubtaskTitles: subtasks.filter(\.isCompleted).map(\.title),
            finishedTask: context.finishTask,
            proofLevel: context.proofLevel,
            blocker: context.blocker,
            note: context.note,
            attachments: context.attachments,
            remainingWork: context.remainingWork,
            initialEstimatedSeconds: workspace.initialEstimatedSeconds,
            helpRequests: workspace.helpRequests,
            planCorrections: workspace.planCorrections
        )
        TaskWorkspaceService.append(record, into: &workingLedger)
        if workingLedger.activeTimer?.taskID == task.id {
            workingLedger.activeTimer = nil
        }
        task.status = context.finishTask ? .completed : .inProgress
        var savedDraft = workspace
        savedDraft.notes = context.note
        savedDraft.remainingWork = context.remainingWork
        // The next opening starts a fresh session, but keeps notes, sources and conversation.
        savedDraft.sessionID = UUID()
        savedDraft.startedAt = .now
        savedDraft.helpRequests = 0
        savedDraft.planCorrections = 0
        TaskWorkspaceService.upsert(savedDraft, into: &workingLedger)
        do {
            try onSaveLedger(workingLedger)
        } catch {
            workingLedger = previousLedger
            task.status = previousStatus
            saveError = error.localizedDescription
            throw error
        }
        try onUpdateTaskStatus(task.status)
        didSaveReview = true
        showsReview = false
        onClose()
    }

    @discardableResult private func persistWorkspace(_ updatedDraft: TaskWorkspaceDraft? = nil) -> Bool {
        var copy = updatedDraft ?? workspace
        copy.lastSavedAt = .now
        TaskWorkspaceService.upsert(copy, into: &workingLedger)
        do {
            try onSaveLedger(workingLedger)
            saveError = nil
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    private func timerDisplay(timer: ActiveTaskTimer, now: Date) -> String {
        let seconds = timer.mode == .countdown ? (timer.remainingSeconds(now: now) ?? 0) : timer.elapsedSeconds(now: now)
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}

struct SessionReviewContext {
    var recordedSeconds: TimeInterval?
    var finishTask = false
    var proofLevel: TaskCompletionProofLevel = .selfReported
    var blocker: TaskBlockerReason?
    var note = ""
    var remainingWork = ""
    var link = ""
    var attachments: [WorkEvidenceAttachment] = []
    var warning: String?
}

struct SessionReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: AcademicTask
    @State var context: SessionReviewContext
    let subtasks: [TaskSubtaskItem]
    let onReturnToWork: () -> Void
    let onSave: (SessionReviewContext) throws -> Void
    @State private var isImportingEvidence = false
    @State private var evidenceError: String?
    @State private var linkDraft = ""
    @State private var attachmentNoteDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("What did you complete?")
                    .font(.title3.weight(.semibold))
                Text(task.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudyDeskTheme.surfacePrimary)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let warning = context.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .padding()
                            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if !subtasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current checklist")
                                .font(.headline)
                            ForEach(subtasks) { item in
                                Label(item.title, systemImage: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                            }
                            if context.finishTask && subtasks.contains(where: { !$0.isCompleted }) {
                                Text("Some steps remain unchecked. Save and finish only if they are no longer required or you handled them outside UniSaver.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    Toggle("Task entirely finished", isOn: $context.finishTask)
                    HStack {
                        Text("Recorded time")
                        Spacer()
                        Stepper(timeLabel, value: Binding(
                            get: { Int((context.recordedSeconds ?? 0) / 60) },
                            set: { context.recordedSeconds = TimeInterval(max(0, $0) * 60) }
                        ), in: 0...720, step: 5)
                    }
                    supportingWorkSection
                    Picker("Blocked by", selection: $context.blocker) {
                        Text("Not blocked").tag(TaskBlockerReason?.none)
                        ForEach(TaskBlockerReason.allCases) { reason in
                            Text(reason.title).tag(Optional(reason))
                        }
                    }
                    TextField("Session note", text: $context.note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                    TextField("Remaining work", text: $context.remainingWork, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }
                .padding(22)
            }
            HStack {
                Button("Return to work") {
                    onReturnToWork()
                    dismiss()
                }
                Spacer()
                Button("Save progress") {
                    context.finishTask = false
                    do { try onSave(context); dismiss() }
                    catch { evidenceError = "Save failed: " + error.localizedDescription }
                }
                .buttonStyle(.bordered)
                Button("Save and finish task") {
                    context.finishTask = true
                    do { try onSave(context); dismiss() }
                    catch { evidenceError = "Save failed: " + error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(StudyDeskTheme.surfacePrimary)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(StudyDeskTheme.backgroundPrimary)
        .fileImporter(
            isPresented: $isImportingEvidence,
            allowedContentTypes: [.image, .pdf, .text, .plainText, .rtf, .data],
            allowsMultipleSelection: true,
            onCompletion: importEvidence
        )
    }

    private var supportingWorkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add supporting work — optional")
                    .font(.headline)
                Text("A screenshot, file or link can document your work. It does not prove quality or submission unless an integration confirms it directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Add screenshot or photo", systemImage: "photo") {
                    isImportingEvidence = true
                }
                .buttonStyle(.bordered)
                Button("Attach assignment", systemImage: "paperclip") {
                    isImportingEvidence = true
                }
                .buttonStyle(.bordered)
                Button("Add note", systemImage: "note.text") {
                    addNoteEvidence()
                }
                .buttonStyle(.bordered)
                .disabled(attachmentNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                TextField("Add link", text: $linkDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Add link") {
                    addLinkEvidence()
                }
                .buttonStyle(.bordered)
                .disabled(URL(string: linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            }
            TextField("Attachment note", text: $attachmentNoteDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            if let evidenceError {
                Label(evidenceError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if context.attachments.isEmpty {
                Text("No supporting work attached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(context.attachments) { attachment in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: attachment))
                                .foregroundStyle(StudyDeskTheme.accentPrimary)
                                .frame(width: 30, height: 30)
                                .background(StudyDeskTheme.accentPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.displayName)
                                    .font(.callout.weight(.medium))
                                Text("\(attachment.uploadState.rawValue) · \(attachment.mimeType ?? attachment.kind.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") {
                                context.attachments.removeAll { $0.id == attachment.id }
                                updateProofLevel()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding()
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func importEvidence(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            do {
                for url in urls {
                    let stored = try AcademicFileStore().importFile(from: url)
                    context.attachments.append(WorkEvidenceAttachment(
                        kind: stored.resourceKind == .image ? .screenshot : .file,
                        displayName: stored.originalFileName,
                        mimeType: stored.mimeType,
                        storedRelativePath: stored.storedRelativePath,
                        note: attachmentNoteDraft,
                        fileSize: stored.fileSize,
                        contentHash: stored.contentHash,
                        uploadState: .localOnly
                    ))
                }
                attachmentNoteDraft = ""
                evidenceError = nil
                updateProofLevel()
            } catch {
                evidenceError = error.localizedDescription
            }
        case .failure(let error):
            evidenceError = error.localizedDescription
        }
    }

    private func addLinkEvidence() {
        let value = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else {
            evidenceError = "Enter a valid http or https link."
            return
        }
        context.attachments.append(WorkEvidenceAttachment(
            kind: .link,
            displayName: url.host() ?? value,
            mimeType: "text/uri-list",
            urlString: value,
            note: attachmentNoteDraft,
            uploadState: .localOnly
        ))
        linkDraft = ""
        attachmentNoteDraft = ""
        evidenceError = nil
        updateProofLevel()
    }

    private func addNoteEvidence() {
        let value = attachmentNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        context.attachments.append(WorkEvidenceAttachment(
            kind: .note,
            displayName: "Supporting note",
            mimeType: "text/plain",
            note: value,
            uploadState: .localOnly
        ))
        attachmentNoteDraft = ""
        evidenceError = nil
        updateProofLevel()
    }

    private func updateProofLevel() {
        context.proofLevel = context.attachments.isEmpty ? .selfReported : .supportingAttachment
    }

    private func icon(for attachment: WorkEvidenceAttachment) -> String {
        switch attachment.kind {
        case .file: "doc"
        case .screenshot: "photo"
        case .link: "link"
        case .note: "note.text"
        }
    }

    private var timeLabel: String {
        guard let seconds = context.recordedSeconds, seconds > 0 else {
            return "No time recorded"
        }
        return "\(Int(seconds / 60)) min"
    }
}

struct TodayConversationDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: String
    let state: TodayConversationState
    let isSending: Bool
    let errorMessage: String?
    let onSend: () -> Void
    let onCancel: () -> Void
    let onNewConversation: () -> Void
    let onOpenProposal: (String) -> Void
    var onUndoCreation: (() -> Void)? = nil
    var sharedResources: [AcademicResource] = []
    var sharedResourceIDs: [UUID] = []
    var onSelectResource: ((UUID, Bool) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UniSaver agent")
                        .font(.title3.weight(.semibold))
                    Text("Chat history stays local unless you send a request through your configured AI provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onSelectResource {
                    Menu("Shared documents (\(sharedResourceIDs.count)/4)") {
                        Text("Only selected documents are sent. PDF, TXT, MD and CSV are supported.")
                        ForEach(sharedResources) { resource in
                            Toggle(resource.title, isOn: Binding(get: { sharedResourceIDs.contains(resource.id) },
                                set: { onSelectResource(resource.id, $0) }))
                                .disabled(!sharedResourceIDs.contains(resource.id) && sharedResourceIDs.count >= 4)
                        }
                    }
                    .disabled(isSending)
                }
                if let onUndoCreation { Button("Undo task creation", action: onUndoCreation).buttonStyle(.bordered).disabled(isSending) }
                Button("New conversation", action: onNewConversation)
                    .buttonStyle(.bordered)
                Button("Close") { dismiss() }
            }
            .padding(18)
            .background(StudyDeskTheme.surfacePrimary)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if state.messages.isEmpty {
                        ConversationBubble(
                            message: TodayConversationMessage(role: .agent, text: "Tell me what’s on your mind. We’ll work out the next step together."),
                            onOpenProposal: onOpenProposal
                        )
                    } else {
                        ForEach(state.messages) { message in
                            ConversationBubble(message: message, onOpenProposal: onOpenProposal)
                        }
                    }
                    if isSending {
                        Label("Thinking…", systemImage: "ellipsis")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(22)
                .frame(maxWidth: 820, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 8) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                MessageComposer(draft: $draft, isSending: isSending, onSend: onSend, onCancel: onCancel)
            }
            .padding(18)
            .background(StudyDeskTheme.surfacePrimary)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(minWidth: 720, minHeight: 680)
        .background(StudyDeskTheme.backgroundPrimary)
    }
}

struct ConversationIntakeCard: View {
    let firstName: String?
    @Binding var draft: String
    let isAnalyzing: Bool
    let errorMessage: String?
    let onAnalyze: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(firstName.map { "What’s up, \($0)?" } ?? "What’s up?")
                        .font(.headline)
                    Text("Paste a class update, add an assignment, or tell me what changed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            TextEditor(text: $draft)
                .font(.callout)
                .frame(minHeight: 92, maxHeight: 150)
                .padding(8)
                .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
                }
                .accessibilityLabel("What changed message")

            HStack {
                ForEach(["Plan my week", "Something changed", "I’m behind", "Add an assignment"], id: \.self) { suggestion in
                    Button(suggestion) {
                        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft = suggestion
                        } else {
                            draft += "\n\(suggestion)"
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .lineLimit(1)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .disabled(!isAnalyzing)
                Spacer()
                Button("Review proposal", action: onAnalyze)
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .deskCard()
    }
}

struct ConversationProposalReviewSheet: View {
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var reviewNotes: [StudyNote]
    @Query(sort: \AcademicTask.title) private var reviewTasks: [AcademicTask]
    let proposal: ConversationAnalysisProposal
    let courses: [Course]
    let onCancel: () -> Void
    let onApply: (ConversationAnalysisProposal) -> String
    var onEditProposal: (ConversationAnalysisProposal) -> Void = { _ in }
    @State private var applied = false
    @State private var isApplying = false
    @State private var openPlan: AcademicTask?
    @State private var resultingIDs: [UUID] = []
    @State private var actions: [ConversationActionDraft]
    @State private var resultMessage: String?

    init(
        proposal: ConversationAnalysisProposal,
        courses: [Course],
        onCancel: @escaping () -> Void,
        onApply: @escaping (ConversationAnalysisProposal) -> String,
        onEditProposal: @escaping (ConversationAnalysisProposal) -> Void = { _ in }
    ) {
        self.proposal = proposal
        self.courses = courses
        self.onCancel = onCancel
        self.onApply = onApply
        self.onEditProposal = onEditProposal
        _actions = State(initialValue: proposal.actions)
    }

    var body: some View {
        if let bank = proposal.actions.first(where: { $0.kind == .importQuestionBank }) {
            let course = courses.first { $0.id == bank.selectedCourseID }
            let chapter = course?.chapters.first { $0.id == bank.selectedChapterID }
            QuizFormView(initialCourse: course, initialChapter: chapter, initialBankText: bank.sourceText,
                         initialTitle: bank.title, onImportApproved: { questions, title, courseID, chapterID, approvals in
                var edited = proposal
                edited.actions[0].title = title
                edited.actions[0].selectedCourseID = courseID
                edited.actions[0].selectedChapterID = chapterID
                edited.actions[0].approvedAnswerChangeKeys = Array(approvals)
                do {
                    edited.actions[0].questionBankDraftJSON = String(decoding: try JSONEncoder().encode(questions), as: UTF8.self)
                    onEditProposal(edited)
                    return onApply(edited)
                } catch { return "Could not save changes: " + error.localizedDescription }
            })
        } else { taskReview }
    }

    private var taskReview: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !proposal.warnings.isEmpty {
                        warningCard
                    }
                    actionGroups
                    sourceCard
                    if let resultMessage {
                        Label(resultMessage, systemImage: applied ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(applied ? .green : .orange)
                    }
                }
                .padding(22)
                .frame(maxWidth: 920, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            footer
        }
        .frame(minWidth: 760, minHeight: 660)
        .background(StudyDeskTheme.backgroundPrimary)
        .onAppear {
            let state = TodayConversationStore.decode(TodayConversationStore.conversationNote(in: reviewNotes, context: modelContext))
            applied = (state.appliedProposalIDs ?? []).contains(proposal.id)
            resultingIDs = state.pendingProposals[proposal.id]?.executionTaskIDs ?? []
            if applied { resultMessage = "This proposal was already saved. It cannot be applied again." }
        }
        .onChange(of: actions) { _, _ in
            guard !applied else { return }
            var edited = proposal
            edited.actions = actions
            onEditProposal(edited)
        }
        .onChange(of: openPlan?.id) { _, _ in
            if let task = openPlan {
                onCancel()
                dismiss()
                navigation.focusTask = task
                openPlan = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(proposal.summary)
                    .font(.title3.weight(.semibold))
                Text("Review every action before UniSaver updates Tasks or Planner.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") {
                onCancel()
                dismiss()
            }
        }
        .padding(20)
        .background(StudyDeskTheme.surfacePrimary)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Needs confirmation")
                .font(.headline)
            ForEach(proposal.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 12))
    }

    private var actionGroups: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($actions) { $action in
                VStack(alignment: .leading, spacing: 8) {
                    ConversationActionEditor(action: $action, courses: courses)
                    HStack {
                        Button("Move parent up") { move(action.id, by: -1) }.disabled(actions.first?.id == action.id)
                        Button("Move parent down") { move(action.id, by: 1) }.disabled(actions.last?.id == action.id)
                        Spacer()
                        Button("Remove parent", role: .destructive) { actions.removeAll { $0.id == action.id } }
                    }.controlSize(.small)
                }
            }
        }.disabled(applied || isApplying)
    }

    private func move(_ id: String, by offset: Int) {
        guard let index = actions.firstIndex(where: { $0.id == id }), actions.indices.contains(index + offset) else { return }
        actions.swapAt(index, index + offset)
    }

    private var sourceCard: some View {
        DisclosureGroup("Source message") {
            Text(proposal.originalMessage)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .padding()
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            Spacer()
            Text(applied ? "Saved plan ready" : "\(actions.filter(\.canApply).count) selected changes ready")
                .font(.caption)
                .foregroundStyle(.secondary)
            if applied {
                Menu("Open saved plan / first action") {
                    ForEach(resultingIDs.compactMap { id in reviewTasks.first { $0.id == id } }) { task in
                        Button(task.title) { openPlan = task }
                    }
                }.disabled(resultingIDs.isEmpty)
            } else {
            Button("Apply selected changes") {
                guard !applied, !isApplying else { return }
                isApplying = true
                defer { isApplying = false }
                var updated = proposal
                updated.actions = actions
                resultMessage = onApply(updated)
                let state = TodayConversationStore.decode(TodayConversationStore.conversationNote(in: reviewNotes, context: modelContext))
                applied = (state.appliedProposalIDs ?? []).contains(proposal.id)
                resultingIDs = state.pendingProposals[proposal.id]?.executionTaskIDs ?? state.lastExecutionTaskIDs ?? []
            }
            .buttonStyle(.borderedProminent)
            .disabled(applied || isApplying || actions.filter(\.canApply).isEmpty || actions.contains { $0.isSelected && !$0.canApply })
            }
        }
        .padding(16)
        .background(StudyDeskTheme.surfacePrimary)
        .overlay(alignment: .top) { Divider() }
    }
}

struct ConversationActionEditor: View {
    @Binding var action: ConversationActionDraft
    let courses: [Course]
    @Query(sort: \AcademicTask.title) private var availableTasks: [AcademicTask]
    @State private var showsSteps = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Toggle("", isOn: $action.isSelected)
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Parent title", text: Binding(get: { action.title }, set: { action.title = $0; if action.isStructuredPlan == true { action.evidence = .suggested } }))
                        .font(.headline)
                    Text(action.evidence.title)
                        .font(.caption)
                        .foregroundStyle(action.evidence == .explicit ? .green : .orange)
                }
                Spacer()
            }

            if action.isStructuredPlan == true {
                if let outcome = action.planOutcome { Text("Outcome: " + outcome).font(.callout) }
                TextField("Completion criterion", text: Binding(get: { action.completionCriterion ?? "" },
                    set: { action.completionCriterion = $0; action.evidence = .suggested }), axis: .vertical)
                Picker("Existing task / project", selection: Binding<UUID?>(get: { action.existingTaskID }, set: { id in
                    action.existingTaskID = id
                    if let task = availableTasks.first(where: { $0.id == id }) {
                        action.kind = action.replacesSubtasks == true ? .updateTask : .addSubtasks
                        action.existingTaskTitle = task.title
                        action.title = task.title
                        action.selectedCourseID = task.course?.id
                        action.planSnapshot = TaskStepReviewSnapshot(task)
                    } else {
                        action.kind = .createTask; action.replacesSubtasks = false
                        action.planSnapshot = nil; action.existingTaskTitle = nil
                    }
                    action.associationNeedsReview = false
                })) {
                    Text("Create a new parent task").tag(UUID?.none)
                    ForEach(availableTasks) { task in
                        let courseName = task.course?.name ?? "Unassigned"
                        let shortID = String(task.id.uuidString.prefix(6))
                        Text("\(task.title) · \(courseName) · \(shortID)")
                            .tag(Optional(task.id))
                    }
                }
                if action.associationNeedsReview == true {
                    Text("Association is ambiguous. Choose an existing task or course, or confirm Unassigned.").foregroundStyle(.orange)
                    Button("Confirm selected association / Unassigned") { action.associationNeedsReview = false }
                }
                if let constraints = action.planConstraints, !constraints.isEmpty {
                    Text("Scope constraints / exclusions").font(.subheadline.bold())
                    ForEach(constraints, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                }
                if let missing = action.planMissingDetails, !missing.isEmpty {
                    Text("Missing details: " + missing.joined(separator: "; ")).font(.caption).foregroundStyle(.orange)
                }
                if let dependencies = action.dependencies, !dependencies.isEmpty {
                    Text("Suggested dependencies: " + dependencies.joined(separator: "; ")).font(.caption)
                }
                if action.replacesSubtasks == true, let snapshot = action.planSnapshot {
                    DisclosureGroup("Before — existing checklist will be replaced after approval") {
                        Text(TaskStructureService.visibleDescription(snapshot.description)).font(.caption).textSelection(.enabled)
                    }
                }
            }
            HStack {
                Picker("Class", selection: $action.selectedCourseID) {
                    Text("Unassigned").tag(UUID?.none)
                    ForEach(courses.filter { !$0.isArchived }) { course in
                        Text(course.name + " · " + course.code).tag(Optional(course.id))
                    }
                }
                if let dueDateBinding = dueDateBinding {
                    DatePicker("Date", selection: dueDateBinding, displayedComponents: .date)
                } else {
                    Text(action.existingTaskID == nil ? "No deadline supplied" : "Keep existing deadline")
                        .foregroundStyle(.secondary)
                    if action.isStructuredPlan == true {
                        Button("Set a date") { action.dueDate = .now }.controlSize(.small)
                    }
                }
                if action.isStructuredPlan != true {
                Stepper("\(action.estimatedMinutes ?? 0) min", value: Binding(
                    get: { action.estimatedMinutes ?? 0 },
                    set: { action.estimatedMinutes = max(0, $0) }
                ), in: 0...600, step: 15)
                }
            }
            .onChange(of: action.selectedCourseID) { _, _ in action.associationNeedsReview = false }

            if let before = action.beforeValue, let after = action.afterValue {
                HStack(alignment: .top) {
                    valueColumn("Before", before)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    valueColumn("After", after)
                }
            }

            if !action.courseCandidates.isEmpty {
                Text("Matches: \(action.courseCandidates.map { "\($0.title) (\($0.reason))" }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !action.subtasks.isEmpty {
                DisclosureGroup("Steps / subtasks", isExpanded: $showsSteps) {
                    ConversationStepsEditor(steps: $action.subtasks, allowsSelection: true, allowsCompletion: action.isStructuredPlan == true)
                    .padding(.top, 8)
                }
            }

            if !action.sessions.isEmpty {
                DisclosureGroup("Work sessions") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($action.sessions) { $session in
                            HStack {
                                Toggle("", isOn: $session.isSelected)
                                    .labelsHidden()
                                VStack(alignment: .leading) {
                                    TextField("Session", text: $session.title)
                                    Text("\(session.startDate.formatted(date: .abbreviated, time: .shortened)) - \(session.endDate.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }

            if !action.missingInformation.isEmpty {
                ForEach(action.missingInformation, id: \.self) { missing in
                    Label(missing, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            DisclosureGroup("Source") {
                Text(action.sourceText)
                    .font(.caption)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var dueDateBinding: Binding<Date>? {
        guard action.dueDate != nil else { return nil }
        return Binding(
            get: { action.dueDate ?? .now },
            set: { action.dueDate = $0 }
        )
    }

    private func valueColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct WeeklyOverviewSection: View {
    let overview: WeeklyOverview
    @Binding var selectedDate: Date
    let layoutMode: StudyDeskLayoutMode
    let onOpenCourse: (Course, CourseWorkspaceTab) -> Void
    let onOpenStudy: () -> Void
    let onCompleteTask: (AcademicTask) -> Void
    let moodleTaskIDs: Set<UUID>

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: layoutMode == .compact ? 150 : 175), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly Overview")
                        .font(.headline)
                    Text("\(UniDateFormatters.dayMonth.string(from: overview.weekInterval.start)) - \(UniDateFormatters.dayMonth.string(from: overview.weekInterval.end.addingTimeInterval(-1)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Previous", systemImage: "chevron.left") { shiftWeek(-1) }
                        .labelStyle(.iconOnly)
                    Button("This Week") { selectedDate = .now }
                    Button("Next", systemImage: "chevron.right") { shiftWeek(1) }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            }

            if !overview.hasEvents {
                EmptyStateView(
                    title: "No scheduled study this week",
                    message: "Add sessions, tasks, or due flashcards and they will appear here.",
                    systemImage: "calendar.badge.clock"
                )
                .frame(minHeight: 160)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(overview.days) { day in
                        WeeklyDayCard(day: day, onOpenCourse: onOpenCourse, onOpenStudy: onOpenStudy, onCompleteTask: onCompleteTask, moodleTaskIDs: moodleTaskIDs)
                    }
                }
            }

            WeeklyActionSummary(overview: overview, onOpenCourse: onOpenCourse, onOpenStudy: onOpenStudy, onCompleteTask: onCompleteTask, moodleTaskIDs: moodleTaskIDs)
        }
        .padding()
        .deskCard()
    }

    private func shiftWeek(_ value: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: value * 7, to: selectedDate) ?? selectedDate
    }
}

struct TodayQuestsSection: View {
    let quests: [DailyQuest]
    let summary: WeeklyGamificationSummary
    let completionMessage: String?
    let onStartQuest: (DailyQuest) -> Void
    let onCompleteQuest: (DailyQuest) -> Void
    let onReplaceQuest: (DailyQuest) -> Void
    let onPostponeQuest: (DailyQuest) -> Void
    let onReduceGoals: () -> Void
    let onWeeklyGoalChange: (Int) -> Void
    let onToggleHidden: () -> Void
    @State private var isEditingGoal = false
    @State private var draftGoal = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today’s quests")
                        .font(.headline)
                    Text(summary.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let scopeNote = summary.scopeNote {
                        Text(scopeNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(summary.totalXP) XP")
                        .font(.subheadline.weight(.semibold))
                    Button("\(summary.activeDays) of \(summary.activeDayGoal) active days") {
                        draftGoal = summary.activeDayGoal
                        isEditingGoal = true
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(StudyDeskTheme.accentPrimary)
                }
            }

            if let completionMessage {
                Label(completionMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .accessibilityLabel(completionMessage)
            }

            if summary.isHidden {
                Text("Gamification is hidden. Your academic tasks, planner and study tools still work normally.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else if quests.isEmpty {
                Text("No meaningful quest is available from your current tasks or practice data. UniSaver will not create fake work to fill the list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(quests.prefix(3)) { quest in
                        DailyQuestCard(
                            quest: quest,
                            onStart: { onStartQuest(quest) },
                            onComplete: { onCompleteQuest(quest) },
                            onReplace: { onReplaceQuest(quest) },
                            onPostpone: { onPostponeQuest(quest) }
                        )
                    }
                }
            }

            HStack {
                Button("Reduce today’s goals") {
                    onReduceGoals()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Lowers the weekly active-day goal and delays comeback prompts. It does not award XP.")
                Button(summary.isHidden ? "Show quests" : "Hide quests") {
                    onToggleHidden()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                Text("XP tracks participation only, not grades or mastery.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .deskCard()
        .confirmationDialog("Weekly active-day goal", isPresented: $isEditingGoal) {
            ForEach(1...7, id: \.self) { value in
                Button("\(value) day\(value == 1 ? "" : "s") per week") {
                    onWeeklyGoalChange(value)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Changing the goal does not award XP and does not alter your academic tasks.")
        }
    }
}

struct DailyQuestCard: View {
    let quest: DailyQuest
    let onStart: () -> Void
    let onComplete: () -> Void
    let onReplace: () -> Void
    let onPostpone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: quest.isComeback ? "sparkle.magnifyingglass" : iconName)
                    .font(.title3)
                    .foregroundStyle(StudyDeskTheme.accentPrimary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(quest.isComeback ? "Welcome back. Start small." : quest.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if quest.isComeback {
                        Text(quest.title)
                            .font(.callout)
                    }
                    Text(quest.courseTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if let estimatedMinutes = quest.estimatedMinutes, estimatedMinutes > 0 {
                    Label("\(estimatedMinutes) min", systemImage: "timer")
                }
                Label(quest.reason, systemImage: "target")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Done", action: onComplete)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Menu {
                    Button("Choose another task", action: onReplace)
                    Button("Postpone today", action: onPostpone)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .controlSize(.small)
                .accessibilityLabel("Quest options")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var iconName: String {
        switch quest.kind {
        case .task: "checklist"
        case .studyBlock: "calendar.badge.clock"
        case .practice: "rectangle.stack"
        case .comeback: "arrow.uturn.backward.circle"
        }
    }
}

struct WeeklyDayCard: View {
    let day: WeeklyDashboardDay
    let onOpenCourse: (Course, CourseWorkspaceTab) -> Void
    let onOpenStudy: () -> Void
    let onCompleteTask: (AcademicTask) -> Void
    let moodleTaskIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.caption.weight(.bold))
                .foregroundStyle(Calendar.current.isDateInToday(day.date) ? StudyDeskTheme.accentPrimary : StudyDeskTheme.textPrimary)

            if day.sessions.isEmpty && day.tasks.isEmpty && day.flashcards.isEmpty {
                Text("Clear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 54, alignment: .topLeading)
            } else {
                ForEach(day.sessions.prefix(3)) { session in
                    Button {
                        if let course = session.course { onOpenCourse(course, .sessions) }
                    } label: {
                        Label("\(UniDateFormatters.time.string(from: session.startTime)) \(session.course?.name ?? session.title)", systemImage: "books.vertical")
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(StudyDeskTheme.textPrimary)
                    if let room = session.room, !room.isEmpty {
                        Text(room)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(day.tasks.prefix(2)) { task in
                    Button {
                        onCompleteTask(task)
                    } label: {
                        HStack(spacing: 4) {
                            Label(task.title, systemImage: task.status == .completed ? "checkmark.circle.fill" : "circle")
                                .lineLimit(1)
                            if moodleTaskIDs.contains(task.id) {
                                Image(systemName: "graduationcap")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                if !day.flashcards.isEmpty {
                    Button {
                        onOpenStudy()
                    } label: {
                        Label("\(day.flashcards.count) flashcards", systemImage: "rectangle.stack")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 134, alignment: .topLeading)
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }
}

struct WeeklyActionSummary: View {
    let overview: WeeklyOverview
    let onOpenCourse: (Course, CourseWorkspaceTab) -> Void
    let onOpenStudy: () -> Void
    let onCompleteTask: (AcademicTask) -> Void
    let moodleTaskIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let next = overview.nextSession {
                HStack {
                    Label("Next class", systemImage: "clock.badge")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                    Text("\(next.course?.name ?? next.title) · \(UniDateFormatters.interval(next.startTime, next.endTime))")
                        .font(.caption)
                    Spacer()
                    Button("Open") {
                        if let course = next.course { onOpenCourse(course, .sessions) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                WeeklyTaskGroup(title: "Overdue", tasks: overview.overdueTasks, tint: .red, onCompleteTask: onCompleteTask, moodleTaskIDs: moodleTaskIDs)
                WeeklyTaskGroup(title: "Due this week", tasks: overview.upcomingTasks, tint: .orange, onCompleteTask: onCompleteTask, moodleTaskIDs: moodleTaskIDs)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reviews")
                        .font(.caption.weight(.semibold))
                    if overview.dueFlashcards.isEmpty {
                        Text("No due flashcards")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("\(overview.dueFlashcards.count) flashcards due", action: onOpenStudy)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct WeeklyTaskGroup: View {
    let title: String
    let tasks: [AcademicTask]
    let tint: Color
    let onCompleteTask: (AcademicTask) -> Void
    let moodleTaskIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            if tasks.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks.prefix(3)) { task in
                    Button {
                        onCompleteTask(task)
                    } label: {
                        HStack(spacing: 4) {
                            Label(task.title, systemImage: "circle")
                                .lineLimit(1)
                            if moodleTaskIDs.contains(task.id) {
                                Image(systemName: "graduationcap")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: "bell")
                .frame(width: 32, height: 32)
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
                Button("View full day") {
                    NotificationCenter.default.post(name: .openPlannerTasks, object: PlannerTaskFilter.all)
                }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .help("Open Planner")
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
    let onOpenCourse: (Course, CourseWorkspaceTab) -> Void

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
                        Button("View Details") {
                            if let course = session.course {
                                onOpenCourse(course, .sessions)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudyDeskTheme.accentPrimary)
                        .disabled(session.course == nil)

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
    let moodleTaskIDs: Set<UUID>

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
                Button("View all") {
                    NotificationCenter.default.post(name: .openPlannerTasks, object: PlannerTaskFilter.priority)
                }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("priorityTasksViewAllButton")
                    .help("Open priority tasks in Planner.")
            }

            if tasks.isEmpty {
                Text("No priority tasks.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks.prefix(5)) { task in
                        PriorityTaskRow(task: task, isMoodleImported: moodleTaskIDs.contains(task.id))
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
    var isMoodleImported = false

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
                    Text("due \(TaskStructureService.deadlineLabel(for: task))")
                    if isMoodleImported {
                        Text("·")
                        Label("Moodle", systemImage: "graduationcap")
                            .labelStyle(.titleAndIcon)
                    }
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
        return TaskStructureService.deadlineLabel(for: task)
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
    @Query(sort: \AcademicResource.lastOpenedAt, order: .reverse) private var resources: [AcademicResource]

    private var matchedResource: AcademicResource? {
        guard let reading else { return nil }
        return resources.first {
            $0.resourceKind == .pdf &&
            $0.title == reading.resourceTitle &&
            $0.course?.id == reading.course?.id
        }
    }

    var body: some View {
        SummaryCard(title: "Continue Reading", systemImage: "book") {
            if let reading {
                if let matchedResource {
                    NavigationLink {
                        ResourceDetailView(resource: matchedResource)
                    } label: {
                        readingContent(reading)
                    }
                    .buttonStyle(.plain)
                } else {
                    readingContent(reading)
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

    private func readingContent(_ reading: ReadingProgress) -> some View {
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
