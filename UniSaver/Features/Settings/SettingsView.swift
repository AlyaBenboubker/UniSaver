import EventKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [AppWorkspace]
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \AcademicTask.dueDate) private var tasks: [AcademicTask]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @AppStorage("moodleInstitutionURL") private var moodleInstitutionURL = ""
    @State private var pendingAction: SettingsWorkspaceAction?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var moodleToken = ""
    @State private var moodleStatusMessage: String?
    @State private var moodleErrorMessage: String?
    @State private var isSyncingMoodle = false
    @State private var moodleMetadata = MoodleSyncMetadata.empty
    @State private var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    @State private var calendarMessage: String?
    @State private var remindersMessage: String?
    @State private var accountEmail = ""
    @State private var accountPassword = ""
    @State private var isCreatingAccount = false
    @State private var passwordResetMessage: String?
    @State private var accountStatus: UniSaverAccountStatus = .signedOut
    @State private var isCheckingAccount = false
    @State private var accountSyncState: UniSaverSyncState = .needsAttention
    @State private var accountSyncMessage: String?
    @State private var isSyncingAccount = false
    @State private var aiAPIKeys: [AIRevisionProviderID: String] = [:]
    @State private var aiStatusMessages: [AIRevisionProviderID: String] = [:]
    @State private var aiErrorMessages: [AIRevisionProviderID: String] = [:]
    @State private var testingAIProviders: Set<AIRevisionProviderID> = []
    @State private var expandedAIProvider: AIRevisionProviderID?
    @State private var availableCalendars: [AppleEventKitSource] = []
    @State private var availableReminderLists: [AppleEventKitSource] = []
    @AppStorage("appleCalendarSelectedIDs") private var selectedCalendarIDs = ""
    @AppStorage("appleReminderSelectedIDs") private var selectedReminderListIDs = ""
    @AppStorage(AIRevisionSettings.fundingModeKey) private var aiFundingModeRaw = AIRevisionFundingMode.personalKey.rawValue
    @AppStorage(AIRevisionSettings.activeProviderKey) private var aiActiveProviderRaw = AIRevisionProviderID.openAI.rawValue
    @AppStorage("aiRevisionModel.openAI") private var openAIModel = AIRevisionProviderID.openAI.defaultModel
    @AppStorage("aiRevisionModel.claude") private var claudeModel = AIRevisionProviderID.claude.defaultModel
    @AppStorage("aiRevisionModel.gemini") private var geminiModel = AIRevisionProviderID.gemini.defaultModel
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    private let moodleKeychain = MoodleKeychainStore()
    private let moodleMetadataStore = MoodleSyncMetadataStore()
    private let aiKeychain = AIKeychainStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title.weight(.bold))
                    Text("Workspace, connections, privacy, data and development controls.")
                        .foregroundStyle(.secondary)
                }

                settingsSection("Workspace", systemImage: "rectangle.grid.2x2") {
                    HStack {
                        metric("Workspace", workspaces.first?.isDemoWorkspace == true ? "Demo" : workspaces.isEmpty ? "Empty" : "Ready")
                        metric("Courses", "\(courses.count)")
                    }
                    Text("Un workspace vide est un état normal : crée un premier cours, importe une ressource non classée ou importe un calendrier depuis Planner.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                settingsSection("Language", systemImage: "globe") {
                    Picker("Interface language", selection: $appLanguageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("English and French are available for the main shell and the Planner event workflow in this build. Spanish, German and Arabic stay hidden until those paths are fully translated and verified.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                settingsSection("Connexions", systemImage: "link") {
                    accountSettingsCard
                    aiSettingsCard
                    moodleSettingsCard
                    appleConnectionCard(
                        title: "Apple Calendar",
                        systemImage: "calendar",
                        status: appleConnectionStatus(permission: calendarStatus, selectedIDs: selectedCalendarIDSet, readableIDs: Set(availableCalendars.map(\.id))),
                        detail: "Lecture seule dans UniSaver. Les événements externes ne sont pas copiés automatiquement dans SwiftData.",
                        message: calendarMessage,
                        sources: availableCalendars,
                        selectedIDs: selectedCalendarIDSet,
                        connectTitle: "Connecter Calendar",
                        refreshAction: loadCalendarSources,
                        connectAction: requestCalendarAccess,
                        selectionAction: toggleCalendarSelection,
                        disconnectAction: {
                            selectedCalendarIDs = ""
                            availableCalendars = []
                            calendarMessage = "Calendar déconnecté dans UniSaver. Les événements Apple et les données UniSaver sont conservés."
                            refreshEventKitStatuses()
                        }
                    )
                    appleConnectionCard(
                        title: "Apple Reminders",
                        systemImage: "list.bullet.rectangle",
                        status: appleConnectionStatus(permission: remindersStatus, selectedIDs: selectedReminderListIDSet, readableIDs: Set(availableReminderLists.map(\.id))),
                        detail: "Lecture seule prévue. Les rappels Apple restent distincts des AcademicTask UniSaver.",
                        message: remindersMessage,
                        sources: availableReminderLists,
                        selectedIDs: selectedReminderListIDSet,
                        connectTitle: "Connecter Reminders",
                        refreshAction: loadReminderSources,
                        connectAction: requestRemindersAccess,
                        selectionAction: toggleReminderSelection,
                        disconnectAction: {
                            selectedReminderListIDs = ""
                            availableReminderLists = []
                            remindersMessage = "Reminders déconnecté dans UniSaver. Les rappels Apple et les tâches UniSaver sont conservés."
                            refreshEventKitStatuses()
                        }
                    )
                }

                settingsSection("Confidentialité et autorisations", systemImage: "hand.raised") {
                    metric("Calendar permission", eventKitStatusText(calendarStatus))
                    metric("Reminders permission", eventKitStatusText(remindersStatus))
                    Text("Le bundle construit doit contenir NSCalendarsFullAccessUsageDescription et NSRemindersFullAccessUsageDescription avec des valeurs non vides avant qu’un vrai accès EventKit puisse être validé.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                settingsSection("Données et sauvegarde", systemImage: "externaldrive") {
                    Text("Les imports Moodle, Calendar et Reminders sont conçus pour ne jamais supprimer tes données UniSaver personnelles lors d’une déconnexion.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                settingsSection("Développement", systemImage: "hammer") {
                    HStack {
                        Button("Load Demo Workspace", systemImage: "sparkles") {
                            if hasWorkspaceData {
                                pendingAction = .loadDemoWorkspace
                            } else {
                                perform(.loadDemoWorkspace)
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Reset Demo Data", systemImage: "arrow.clockwise") {
                            pendingAction = .resetDemoData
                        }
                        .buttonStyle(.bordered)

                        Button("Start Empty Workspace", systemImage: "plus") {
                            pendingAction = .startEmptyWorkspace
                        }
                        .buttonStyle(.bordered)

                        Button("Reset Workspace Choice", systemImage: "trash") {
                            DemoWorkspaceService.resetWorkspaceChoice(in: modelContext)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(StudyDeskTheme.backgroundPrimary)
        .navigationTitle("Settings")
        .confirmationDialog(
            pendingAction?.title ?? "Confirm workspace action",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            )
        ) {
            if let pendingAction {
                Button(pendingAction.confirmTitle, role: .destructive) {
                    perform(pendingAction)
                }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction?.message ?? "")
        }
        .task {
            await restoreAccountSession()
            moodleMetadata = moodleMetadataStore.load()
            if (try? moodleKeychain.token()) != nil {
                moodleStatusMessage = "Authorized token stored in Keychain."
            }
            refreshAIStatus()
            refreshEventKitStatuses()
            loadCalendarSources()
            loadReminderSources()
        }
    }

    private var hasWorkspaceData: Bool {
        !workspaces.isEmpty || !courses.isEmpty
    }

    private var selectedCalendarIDSet: Set<String> {
        Set(selectedCalendarIDs.split(separator: ",").map(String.init))
    }

    private var selectedReminderListIDSet: Set<String> {
        Set(selectedReminderListIDs.split(separator: ",").map(String.init))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func settingsSection<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding()
        .deskCard()
    }

    private var accountSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(StudyDeskTheme.accentPrimary)
                    .frame(width: 34, height: 34)
                    .background(StudyDeskTheme.accentPrimary.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("UniSaver account")
                        .font(.headline)
                    Text("Sign in with your email or Google account to sync your study data securely with Firebase.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            switch accountStatus {
            case .signedIn(let account):
                HStack {
                    metric("Account", account.firstName)
                    metric("Email", account.email)
                    metric("Sync", accountSyncState.rawValue)
                }

                if let accountSyncMessage {
                    Label(accountSyncMessage, systemImage: accountSyncState == .synced ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(accountSyncState == .synced ? .green : .orange)
                }

                HStack {
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await syncAccountData() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSyncingAccount)

                    Button("Sign out") {
                        Task { await signOutAccount() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSyncingAccount)

                    if isSyncingAccount {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            case .restoring:
                Label("Restoring session…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            case .signedOut:
                accountSignInForm
            case .unavailable(let message):
                Label(message, systemImage: "server.rack")
                    .font(.callout)
                    .foregroundStyle(.orange)
                accountSignInForm
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                accountSignInForm
            }
        }
        .padding()
        .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var accountSignInForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Email", text: $accountEmail)
                .textContentType(.emailAddress)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $accountPassword)
                .textContentType(isCreatingAccount ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)
            Toggle("Create a new account", isOn: $isCreatingAccount)
            HStack {
                Button(isCreatingAccount ? "Create account" : "Sign in") {
                    Task {
                        isCheckingAccount = true
                        defer { isCheckingAccount = false }
                        accountStatus = await AccountSyncService().signInWithEmail(
                            accountEmail, password: accountPassword, createAccount: isCreatingAccount
                        )
                        accountSyncState = syncState(for: accountStatus)
                        if case .signedIn = accountStatus { accountPassword = "" }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || accountPassword.isEmpty)
                Button("Continue with Google") {
                    Task { await signInWithGoogle() }
                }
                .buttonStyle(.bordered)
                if isCheckingAccount { ProgressView().controlSize(.small) }
            }
            Button("Reset password") {
                Task {
                    isCheckingAccount = true
                    defer { isCheckingAccount = false }
                    do {
                        try await AccountSyncService().resetPassword(email: accountEmail)
                        passwordResetMessage = "Password reset requested. Check your email for instructions."
                    } catch {
                        passwordResetMessage = error.localizedDescription
                    }
                }
            }
            .disabled(accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let passwordResetMessage {
                Text(passwordResetMessage).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
        .disabled(isCheckingAccount)
    }

    @MainActor
    private func restoreAccountSession() async {
        isCheckingAccount = true
        accountStatus = .restoring
        accountStatus = await AccountSyncService().restoreSession()
        accountSyncState = syncState(for: accountStatus)
        isCheckingAccount = false
    }

    @MainActor
    private func signInWithGoogle() async {
        isCheckingAccount = true
        accountStatus = await AccountSyncService().signInWithGoogle()
        accountSyncState = syncState(for: accountStatus)
        isCheckingAccount = false
    }

    @MainActor
    private func signOutAccount() async {
        isCheckingAccount = true
        accountStatus = await AccountSyncService().signOut()
        accountSyncState = .needsAttention
        accountSyncMessage = nil
        isCheckingAccount = false
    }

    @MainActor
    private func syncAccountData() async {
        isSyncingAccount = true
        accountSyncState = .syncing
        accountSyncMessage = "Syncing courses, tasks, completed work sessions and supporting files…"
        do {
            let ledgerNote = TaskExecutionLedgerStore.ledgerNote(in: notes, context: modelContext)
            let ledger = TaskExecutionLedgerStore.decode(ledgerNote)
            let summary = try await AccountSyncService().syncFirstSlice(
                courses: courses,
                tasks: tasks,
                taskLedger: ledger
            )
            accountSyncState = summary.state
            accountSyncMessage = summary.message
        } catch {
            accountSyncState = .needsAttention
            accountSyncMessage = error.localizedDescription
        }
        isSyncingAccount = false
    }

    private func syncState(for status: UniSaverAccountStatus) -> UniSaverSyncState {
        switch status {
        case .signedIn:
            .needsAttention
        case .restoring:
            .syncing
        case .signedOut:
            .needsAttention
        case .unavailable:
            .needsAttention
        case .error:
            .needsAttention
        }
    }

    private func perform(_ action: SettingsWorkspaceAction) {
        statusMessage = nil
        errorMessage = nil
        do {
            switch action {
            case .loadDemoWorkspace:
                try DemoWorkspaceService.resetWorkspaceThrowing(in: modelContext)
                DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                statusMessage = "Demo workspace loaded."
            case .resetDemoData:
                try DemoWorkspaceService.resetWorkspaceThrowing(in: modelContext)
                DemoWorkspaceService.loadDemoWorkspace(in: modelContext)
                statusMessage = "Demo data reset."
            case .startEmptyWorkspace:
                try DemoWorkspaceService.resetWorkspaceThrowing(in: modelContext)
                DemoWorkspaceService.startEmptyWorkspace(in: modelContext)
                statusMessage = "Empty workspace started."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingAction = nil
    }

    private var moodleSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Moodle", systemImage: "graduationcap")
                    .font(.headline)
                Spacer()
                if isSyncingMoodle {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Read-only connector. UniSaver does not ask for your university password and does not read tokens from the official Moodle app.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("https://moodle.example.edu", text: $moodleInstitutionURL)
                .textFieldStyle(.roundedBorder)

            SecureField("Authorized read-only web service token", text: $moodleToken)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save Token", systemImage: "key") {
                    saveMoodleToken()
                }
                .disabled(moodleToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Actualiser", systemImage: "arrow.clockwise") {
                    syncMoodle()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSyncingMoodle)

                Button("Disconnect", systemImage: "xmark.circle") {
                    disconnectMoodle()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                metric("Connection", moodleConnectionLabel)
                metric("Last sync", moodleMetadata.lastSyncAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
            }

            if !moodleMetadata.accessibleFunctions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Available Moodle API")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(moodleMetadata.accessibleFunctions.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            if let moodleStatusMessage {
                Text(moodleStatusMessage)
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            if let moodleErrorMessage {
                Text(moodleErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var aiSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            aiAssistantHeader
            aiFundingModeChooser

            if aiFundingMode == .included {
                includedAIStatusCard
            }

            if aiFundingMode == .personalKey && connectedAIProviderCount == 0 {
                aiSetupGuide
            }

            if aiFundingMode == .personalKey {
                ForEach(AIRevisionProviderID.allCases) { provider in
                    aiProviderCard(provider)
                }
            }

            aiDataUseCard

            HStack(spacing: 12) {
                metric(aiText("Historique local", "Local history"), "\(AIRevisionHistoryStore.load().count) \(aiText("sessions", "sessions"))")
                Button(aiText("Effacer l’historique IA", "Erase AI history"), systemImage: "trash") {
                    AIRevisionHistoryStore.erase()
                    for provider in AIRevisionProviderID.allCases {
                        aiStatusMessages[provider] = aiText(
                            "Historique IA local effacé. Les clés et les données de cours sont conservées.",
                            "Local AI history erased. Keys and course data were kept."
                        )
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var aiFundingModeChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(aiText("Mode de financement", "Funding mode"))
                .font(.headline)
            Picker(aiText("Mode IA", "AI mode"), selection: $aiFundingModeRaw) {
                Text(aiText("IA incluse avec UniSaver", "Included with UniSaver")).tag(AIRevisionFundingMode.included.rawValue)
                Text(aiText("Utiliser ma propre clé", "Use my own key")).tag(AIRevisionFundingMode.personalKey.rawValue)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                fundingModeSummary(
                    mode: .included,
                    title: aiText("IA incluse", "Included AI"),
                    detail: aiText("Passerait par le serveur UniSaver avec abonnement et allocation.", "Would use the UniSaver server with subscription and quota."),
                    systemImage: "cloud.fill"
                )
                fundingModeSummary(
                    mode: .personalKey,
                    title: aiText("Ma propre clé", "My own key"),
                    detail: aiText("Utilise tes clés OpenAI, Claude ou Gemini stockées dans le Keychain.", "Uses your OpenAI, Claude or Gemini keys stored in Keychain."),
                    systemImage: "key.fill"
                )
            }
        }
        .padding(14)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var includedAIStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                providerBadge(.openAI)
                    .opacity(0.55)
                VStack(alignment: .leading, spacing: 6) {
                    Text(aiText("IA incluse avec UniSaver", "Included with UniSaver"))
                        .font(.headline)
                    statusPill(.notConnected)
                    Text(aiText(
                        "Bientôt disponible : aucun backend UniSaver de compte, abonnement, quota ou facturation StoreKit n’est configuré dans ce projet. Aucune clé UniSaver n’est embarquée dans l’app.",
                        "Coming soon: this project has no UniSaver account backend, subscription entitlement, quota service or StoreKit purchase flow configured. No UniSaver-owned key is embedded in the app."
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                trustStep(title: aiText("Compte UniSaver", "UniSaver account"), isComplete: false, systemImage: "person.crop.circle")
                trustStep(title: aiText("Abonnement actif", "Active subscription"), isComplete: false, systemImage: "creditcard")
                trustStep(title: aiText("Allocation disponible", "Quota available"), isComplete: false, systemImage: "gauge.with.dots.needle.bottom.50percent")
            }

            Text(aiText(
                "Quand ce mode sera activé, le serveur UniSaver détiendra les clés fournisseurs, appliquera les plafonds d’usage et renverra les états : abonnement expiré, quota atteint, réseau indisponible ou requête interrompue.",
                "When this mode is enabled, the UniSaver server will hold provider keys, enforce usage limits and return states for expired subscription, quota reached, network unavailable or interrupted request."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.purple.opacity(0.12), StudyDeskTheme.surfacePrimary], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private func aiProviderCard(_ provider: AIRevisionProviderID) -> some View {
        let isExpanded = expandedAIProvider == provider
        let phase = aiConnectionPhase(for: provider)

        return VStack(alignment: .leading, spacing: isExpanded ? 14 : 10) {
            HStack(alignment: .top, spacing: 12) {
                providerBadge(provider)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(provider.displayName)
                            .font(.headline)
                        if aiActiveProviderRaw == provider.rawValue {
                            Text(aiText("Actif", "Active"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(providerDescription(provider))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    statusPill(phase)
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if phase.isReady {
                        Button(aiActiveProviderRaw == provider.rawValue ? aiText("Utilisé", "In use") : aiText("Utiliser", "Use")) {
                            aiActiveProviderRaw = provider.rawValue
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(aiActiveProviderRaw == provider.rawValue)
                    }
                    Button(isExpanded ? aiText("Réduire", "Collapse") : aiText("Configurer", "Configure"), systemImage: isExpanded ? "chevron.up" : "slider.horizontal.3") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandedAIProvider = isExpanded ? nil : provider
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()

                    HStack(alignment: .firstTextBaseline) {
                        Label(aiText("Domaine contacté", "Contacted domain"), systemImage: "lock.shield")
                            .font(.caption.weight(.semibold))
                        Text(provider.officialDomain)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Picker(aiText("Modèle", "Model"), selection: modelBinding(for: provider)) {
                        ForEach(provider.models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)

                    Link(aiText("Créer une clé API officielle", "Create an official API key"), destination: provider.keyURL)
                        .font(.callout)

                    SecureField(aiText("Nouvelle clé API \(provider.displayName)", "New \(provider.displayName) API key"), text: apiKeyBinding(for: provider))
                        .textFieldStyle(.roundedBorder)

                    aiTrustSteps(for: provider)

                    HStack(spacing: 10) {
                        Button(aiText("Enregistrer", "Save"), systemImage: "key") {
                            saveAIKey(for: provider)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((aiAPIKeys[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(testingAIProviders.contains(provider) ? aiText("Test...", "Testing...") : aiText("Tester", "Test"), systemImage: "bolt.horizontal") {
                            testAIConnection(for: provider)
                        }
                        .buttonStyle(.bordered)
                        .disabled(testingAIProviders.contains(provider) || !aiHasStoredKey(provider))

                        if aiHasStoredKey(provider) {
                            Button(aiText("Déconnecter", "Disconnect"), systemImage: "xmark.circle") {
                                disconnectAI(for: provider)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if testingAIProviders.contains(provider) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(aiText("Vérification de la clé et génération de test en cours.", "Checking the key and running a test generation."))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let message = aiStatusMessages[provider] {
                        aiMessage(message, systemImage: "checkmark.circle.fill", color: .green)
                    }
                    if let message = aiErrorMessages[provider] {
                        aiMessage(message, systemImage: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                .padding(14)
                .background(StudyDeskTheme.surfacePrimary.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(providerGradient(provider), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(aiActiveProviderRaw == provider.rawValue ? providerAccent(provider).opacity(0.55) : StudyDeskTheme.borderSubtle, lineWidth: aiActiveProviderRaw == provider.rawValue ? 1.5 : 1)
        }
    }

    private var aiAssistantHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.pink.opacity(0.22), Color.blue.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(StudyDeskTheme.accentPrimary)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 5) {
                    Text(aiText("Ton assistant de révision", "Your revision assistant"))
                        .font(.title3.weight(.bold))
                    Text(aiText(
                        "Choisis le fournisseur actif. Pour chaque séance, l’étudiant sélectionne les notes et documents envoyés.",
                        "Choose the active provider. For each session, the student selects the notes and documents that are sent."
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(aiText("Mode actif", "Active mode"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(aiFundingMode == .included ? aiText("IA incluse", "Included AI") : activeAIProvider.displayName)
                        .font(.headline)
                    Button(aiText("Changer", "Change"), systemImage: "arrow.left.arrow.right") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if aiFundingMode == .personalKey {
                                expandedAIProvider = activeAIProvider
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [StudyDeskTheme.surfacePrimary, StudyDeskTheme.surfaceTinted],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var aiSetupGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(aiText("Démarrage guidé", "Guided setup"), systemImage: "wand.and.stars")
                .font(.headline)
            HStack(alignment: .top, spacing: 12) {
                setupStep(number: "1", text: aiText("Choisis OpenAI, Claude ou Gemini.", "Choose OpenAI, Claude or Gemini."))
                setupStep(number: "2", text: aiText("Ajoute une clé API officielle puis lance un test.", "Add an official API key, then run a test."))
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.24), lineWidth: 1)
        }
    }

    private var aiDataUseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(aiText("Comment tes données sont utilisées", "How your data is used"), systemImage: "hand.raised")
                .font(.headline)
            Text(aiText(
                "Seules les sources cochées dans une session partent vers le mode actif. En mode UniSaver, aucune clé personnelle n’est lue. En mode clé personnelle, aucune allocation UniSaver n’est consommée.",
                "Only sources checked in a session are sent through the active mode. UniSaver mode never reads personal keys. Personal-key mode never consumes UniSaver allocation."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                trustLegend(title: aiText("Clé enregistrée", "Key saved"), systemImage: "key.fill", color: .blue)
                trustLegend(title: aiText("Connexion testée", "Connection tested"), systemImage: "network", color: .teal)
                trustLegend(title: aiText("Génération vérifiée", "Generation verified"), systemImage: "checkmark.seal.fill", color: .green)
            }
        }
        .padding(14)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var activeAIProvider: AIRevisionProviderID {
        AIRevisionProviderID(rawValue: aiActiveProviderRaw) ?? .openAI
    }

    private var aiFundingMode: AIRevisionFundingMode {
        AIRevisionFundingMode(rawValue: aiFundingModeRaw) ?? .personalKey
    }

    private var connectedAIProviderCount: Int {
        AIRevisionProviderID.allCases.filter { aiHasStoredKey($0) }.count
    }

    private func fundingModeSummary(mode: AIRevisionFundingMode, title: String, detail: String, systemImage: String) -> some View {
        let isSelected = aiFundingMode == mode
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isSelected ? StudyDeskTheme.accentPrimary : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isSelected ? StudyDeskTheme.accentPrimary : Color.secondary).opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func setupStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.orange.opacity(0.20), in: Circle())
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerBadge(_ provider: AIRevisionProviderID) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(providerAccent(provider).opacity(0.14))
            Image(systemName: providerSymbol(provider))
                .font(.title3.weight(.semibold))
                .foregroundStyle(providerAccent(provider))
        }
        .frame(width: 42, height: 42)
        .accessibilityLabel(Text(provider.displayName))
    }

    private func statusPill(_ phase: AIConnectionPhase) -> some View {
        HStack(spacing: 6) {
            Image(systemName: phase.systemImage)
            Text(phase.title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(phase.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(phase.color.opacity(0.12), in: Capsule())
        .accessibilityLabel(Text(phase.title))
    }

    private func aiMessage(_ message: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func aiTrustSteps(for provider: AIRevisionProviderID) -> some View {
        HStack(spacing: 10) {
            trustStep(title: aiText("Clé enregistrée", "Key saved"), isComplete: aiHasStoredKey(provider), systemImage: "key.fill")
            trustStep(title: aiText("Connexion testée", "Connection tested"), isComplete: aiIsTested(provider), systemImage: "network")
            trustStep(title: aiText("Génération vérifiée", "Generation verified"), isComplete: aiIsTested(provider), systemImage: "checkmark.seal.fill")
        }
    }

    private func trustLegend(title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func trustStep(title: String, isComplete: Bool, systemImage: String) -> some View {
        Label(title, systemImage: isComplete ? systemImage : "circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isComplete ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((isComplete ? Color.green : Color.secondary).opacity(0.10), in: Capsule())
    }

    private func providerDescription(_ provider: AIRevisionProviderID) -> String {
        switch (provider, appLanguage) {
        case (.openAI, .french):
            return "Modèles généralistes rapides pour explications, quiz et brouillons."
        case (.claude, .french):
            return "Très à l’aise avec les longues consignes et les réponses structurées."
        case (.gemini, .french):
            return "Option Google pour révision rapide et génération de questions."
        case (.openAI, _):
            return "Fast general models for explanations, quizzes and drafts."
        case (.claude, _):
            return "Strong with long prompts and structured feedback."
        case (.gemini, _):
            return "Google option for quick revision and question drafts."
        }
    }

    private func providerSymbol(_ provider: AIRevisionProviderID) -> String {
        switch provider {
        case .openAI: return "circle.hexagongrid"
        case .claude: return "text.bubble"
        case .gemini: return "sparkle.magnifyingglass"
        }
    }

    private func providerAccent(_ provider: AIRevisionProviderID) -> Color {
        switch provider {
        case .openAI: return CourseColor.mint.color
        case .claude: return CourseColor.amber.color
        case .gemini: return CourseColor.sky.color
        }
    }

    private func providerGradient(_ provider: AIRevisionProviderID) -> LinearGradient {
        let accent = providerAccent(provider)
        return LinearGradient(
            colors: [accent.opacity(0.13), StudyDeskTheme.surfacePrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func aiConnectionPhase(for provider: AIRevisionProviderID) -> AIConnectionPhase {
        if testingAIProviders.contains(provider) {
            return .testing
        }
        if aiErrorMessages[provider] != nil {
            return .error
        }
        if aiIsTested(provider) {
            return .ready
        }
        if aiHasStoredKey(provider) {
            return .keySaved
        }
        return .notConnected
    }

    private func aiHasStoredKey(_ provider: AIRevisionProviderID) -> Bool {
        (try? aiKeychain.apiKey(for: provider)) != nil
    }

    private func aiIsTested(_ provider: AIRevisionProviderID) -> Bool {
        UserDefaults.standard.bool(forKey: AIRevisionSettings.testedKey(for: provider))
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private func aiText(_ french: String, _ english: String) -> String {
        appLanguage == .french ? french : english
    }

    private var aiSettings: AIRevisionSettings {
        AIRevisionSettings(
            fundingMode: AIRevisionFundingMode(rawValue: aiFundingModeRaw) ?? .personalKey,
            activeProvider: AIRevisionProviderID(rawValue: aiActiveProviderRaw) ?? .openAI,
            modelsByProvider: [
                .openAI: openAIModel,
                .claude: claudeModel,
                .gemini: geminiModel
            ]
        )
    }

    private func appleConnectionCard(
        title: String,
        systemImage: String,
        status: String,
        detail: String,
        message: String?,
        sources: [AppleEventKitSource],
        selectedIDs: Set<String>,
        connectTitle: String,
        refreshAction: @escaping () -> Void,
        connectAction: @escaping () -> Void,
        selectionAction: @escaping (String) -> Void,
        disconnectAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Text(status)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(StudyDeskTheme.surfaceTinted, in: Capsule())
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(connectTitle, systemImage: "link") {
                    connectAction()
                }
                Button("Actualiser", systemImage: "arrow.clockwise") {
                    refreshAction()
                }
                Button("Déconnecter", systemImage: "xmark.circle") {
                    disconnectAction()
                }
            }
            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources à afficher")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(sources) { source in
                        Toggle(isOn: Binding(
                            get: { selectedIDs.contains(source.id) },
                            set: { _ in selectionAction(source.id) }
                        )) {
                            HStack {
                                Text(source.title)
                                Spacer()
                                Text(source.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(StudyDeskTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var moodleConnectionLabel: String {
        if moodleMetadata.institutionURL != nil {
            return moodleMetadata.siteName ?? "Connected"
        }
        return "Not connected"
    }

    private func saveMoodleToken() {
        moodleStatusMessage = nil
        moodleErrorMessage = nil
        do {
            try moodleKeychain.saveToken(moodleToken.trimmingCharacters(in: .whitespacesAndNewlines))
            moodleToken = ""
            moodleStatusMessage = "Token saved in Keychain."
        } catch {
            moodleErrorMessage = error.localizedDescription
        }
    }

    private func refreshAIStatus() {
        aiStatusMessages = [:]
        aiErrorMessages = [:]
        for provider in AIRevisionProviderID.allCases {
            switch AIRevisionAssistantClient(settings: aiSettings, keychain: aiKeychain).status(for: provider) {
            case .notConfigured:
                aiStatusMessages[provider] = nil
            case .ready:
                aiStatusMessages[provider] = aiText(
                    "Prêt. Les générations utiliseront \(provider.officialDomain) si ce fournisseur est actif.",
                    "Ready. Generations will use \(provider.officialDomain) when this provider is active."
                )
            case .error(let message):
                aiErrorMessages[provider] = message
            }
        }
    }

    private func saveAIKey(for provider: AIRevisionProviderID) {
        aiStatusMessages[provider] = nil
        aiErrorMessages[provider] = nil
        do {
            try aiKeychain.saveAPIKey((aiAPIKeys[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
            UserDefaults.standard.set(false, forKey: AIRevisionSettings.testedKey(for: provider))
            aiAPIKeys[provider] = ""
            aiStatusMessages[provider] = aiText(
                "Clé \(provider.displayName) enregistrée dans le Keychain. Lance un test avant utilisation.",
                "\(provider.displayName) key saved in Keychain. Run a test before using it."
            )
        } catch {
            aiErrorMessages[provider] = error.localizedDescription
        }
    }

    private func testAIConnection(for provider: AIRevisionProviderID) {
        aiStatusMessages[provider] = nil
        aiErrorMessages[provider] = nil
        testingAIProviders.insert(provider)
        let client = AIRevisionAssistantClient(settings: aiSettings, keychain: aiKeychain)
        Task {
            do {
                let answer = try await client.testConnection(for: provider)
                aiStatusMessages[provider] = aiText(
                    "Connexion et génération testées sur \(provider.officialDomain) : \(answer)",
                    "Connection and generation tested on \(provider.officialDomain): \(answer)"
                )
            } catch {
                UserDefaults.standard.set(false, forKey: AIRevisionSettings.testedKey(for: provider))
                aiErrorMessages[provider] = error.localizedDescription
            }
            testingAIProviders.remove(provider)
        }
    }

    private func disconnectAI(for provider: AIRevisionProviderID) {
        aiStatusMessages[provider] = nil
        aiErrorMessages[provider] = nil
        do {
            try aiKeychain.deleteAPIKey(for: provider)
            UserDefaults.standard.set(false, forKey: AIRevisionSettings.testedKey(for: provider))
            aiAPIKeys[provider] = ""
            aiStatusMessages[provider] = aiText(
                "\(provider.displayName) déconnecté. Aucune donnée de cours n’a été supprimée.",
                "\(provider.displayName) disconnected. No course data was deleted."
            )
        } catch {
            aiErrorMessages[provider] = error.localizedDescription
        }
    }

    private func aiConnectionLabel(for provider: AIRevisionProviderID) -> String {
        if testingAIProviders.contains(provider) {
            return "Test en cours"
        }
        switch AIRevisionAssistantClient(settings: aiSettings, keychain: aiKeychain).status(for: provider) {
        case .notConfigured:
            if (try? aiKeychain.apiKey(for: provider)) != nil {
                return "Clé enregistrée"
            }
            return "Non connecté"
        case .ready:
            return "Prêt"
        case .error:
            return "Erreur"
        }
    }

    private func apiKeyBinding(for provider: AIRevisionProviderID) -> Binding<String> {
        Binding {
            aiAPIKeys[provider] ?? ""
        } set: { newValue in
            aiAPIKeys[provider] = newValue
        }
    }

    private func modelBinding(for provider: AIRevisionProviderID) -> Binding<String> {
        Binding {
            switch provider {
            case .openAI: return openAIModel
            case .claude: return claudeModel
            case .gemini: return geminiModel
            }
        } set: { newValue in
            switch provider {
            case .openAI: openAIModel = newValue
            case .claude: claudeModel = newValue
            case .gemini: geminiModel = newValue
            }
            UserDefaults.standard.set(false, forKey: AIRevisionSettings.testedKey(for: provider))
        }
    }

    private func syncMoodle() {
        moodleStatusMessage = nil
        moodleErrorMessage = nil
        guard let url = URL(string: moodleInstitutionURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https" else {
            moodleErrorMessage = MoodleClientError.invalidHTTPSURL.localizedDescription
            return
        }
        isSyncingMoodle = true
        Task {
            do {
                let token = try moodleKeychain.token()
                let summary = try await MoodleSyncService.synchronize(
                    institutionURL: url,
                    token: token,
                    context: modelContext,
                    metadataStore: moodleMetadataStore
                )
                moodleMetadata = moodleMetadataStore.load()
                moodleStatusMessage = "Moodle updated: \(summary.importedCourseCount) courses imported, \(summary.updatedCourseCount) updated, \(summary.importedTaskCount) deadlines imported, \(summary.updatedTaskCount) updated."
            } catch {
                moodleErrorMessage = error.localizedDescription
            }
            isSyncingMoodle = false
        }
    }

    private func disconnectMoodle() {
        moodleStatusMessage = nil
        moodleErrorMessage = nil
        do {
            try moodleKeychain.deleteToken()
            try moodleMetadataStore.clearConnectionStateKeepingImportedData()
            moodleMetadata = moodleMetadataStore.load()
            moodleToken = ""
            moodleStatusMessage = "Disconnected. Imported Moodle courses and deadlines are kept; UniSaver-created data is untouched."
        } catch {
            moodleErrorMessage = error.localizedDescription
        }
    }

    private func refreshEventKitStatuses() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    private func requestCalendarAccess() {
        calendarMessage = nil
        guard hasNonEmptyInfoPlistValue("NSCalendarsFullAccessUsageDescription") else {
            calendarMessage = "NSCalendarsFullAccessUsageDescription manque dans l’Info.plist construit. Configure la target avant de demander l’accès Calendar."
            return
        }
        Task {
            do {
                let granted = try await EKEventStore().requestFullAccessToEvents()
                await MainActor.run {
                    refreshEventKitStatuses()
                    if granted {
                        loadCalendarSources()
                    } else {
                        calendarMessage = "Accès Calendar refusé. UniSaver continue de fonctionner hors connexion."
                    }
                }
            } catch {
                await MainActor.run {
                    refreshEventKitStatuses()
                    calendarMessage = error.localizedDescription
                }
            }
        }
    }

    private func requestRemindersAccess() {
        remindersMessage = nil
        guard hasNonEmptyInfoPlistValue("NSRemindersFullAccessUsageDescription") else {
            remindersMessage = "NSRemindersFullAccessUsageDescription manque dans l’Info.plist construit. Configure la target avant de demander l’accès Reminders."
            return
        }
        Task {
            do {
                let granted = try await EKEventStore().requestFullAccessToReminders()
                await MainActor.run {
                    refreshEventKitStatuses()
                    if granted {
                        loadReminderSources()
                    } else {
                        remindersMessage = "Accès Reminders refusé. Aucune donnée n’a été modifiée."
                    }
                }
            } catch {
                await MainActor.run {
                    refreshEventKitStatuses()
                    remindersMessage = error.localizedDescription
                }
            }
        }
    }

    private func eventKitStatusText(_ status: EKAuthorizationStatus) -> String {
        if #available(macOS 14.0, *) {
            switch status {
            case .notDetermined:
                return "À demander"
            case .restricted:
                return "Restreint"
            case .denied:
                return "Refusé"
            case .fullAccess:
                return "Full access"
            case .writeOnly:
                return "Écriture seule"
            @unknown default:
                return "Inconnu"
            }
        }
        switch status {
        case .notDetermined:
            return "À demander"
        case .restricted:
            return "Restreint"
        case .denied:
            return "Refusé"
        case .authorized:
            return "Autorisé"
        case .fullAccess:
            return "Full access"
        case .writeOnly:
            return "Écriture seule"
        @unknown default:
            return "Inconnu"
        }
    }

    private func appleConnectionStatus(permission: EKAuthorizationStatus, selectedIDs: Set<String>, readableIDs: Set<String>) -> String {
        guard hasReadableEventKitAccess(permission) else {
            return eventKitStatusText(permission)
        }
        if readableIDs.isEmpty {
            return "Autorisé, aucune source lisible"
        }
        if selectedIDs.isEmpty {
            return "Autorisé, rien sélectionné"
        }
        if selectedIDs.isDisjoint(with: readableIDs) {
            return "Sélection indisponible"
        }
        return "Connecté"
    }

    private func hasReadableEventKitAccess(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        switch status {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    private func loadCalendarSources() {
        refreshEventKitStatuses()
        guard hasReadableEventKitAccess(calendarStatus) else {
            availableCalendars = []
            return
        }
        let calendars = EKEventStore().calendars(for: .event)
        availableCalendars = calendars
            .map { AppleEventKitSource(id: $0.calendarIdentifier, title: $0.title, detail: $0.source.title) }
            .sorted { $0.title < $1.title }
        calendarMessage = availableCalendars.isEmpty ? "Accès accordé, mais aucun calendrier lisible." : "\(availableCalendars.count) calendrier(s) lisible(s). Sélectionne ceux à afficher dans Planner."
    }

    private func loadReminderSources() {
        refreshEventKitStatuses()
        guard hasReadableEventKitAccess(remindersStatus) else {
            availableReminderLists = []
            return
        }
        let lists = EKEventStore().calendars(for: .reminder)
        availableReminderLists = lists
            .map { AppleEventKitSource(id: $0.calendarIdentifier, title: $0.title, detail: $0.source.title) }
            .sorted { $0.title < $1.title }
        remindersMessage = availableReminderLists.isEmpty ? "Accès accordé, mais aucune liste lisible." : "\(availableReminderLists.count) liste(s) lisible(s). Sélectionne celles à afficher dans Planner."
    }

    private func toggleCalendarSelection(_ id: String) {
        selectedCalendarIDs = toggled(id: id, in: selectedCalendarIDSet)
        loadCalendarSources()
    }

    private func toggleReminderSelection(_ id: String) {
        selectedReminderListIDs = toggled(id: id, in: selectedReminderListIDSet)
        loadReminderSources()
    }

    private func toggled(id: String, in set: Set<String>) -> String {
        var updated = set
        if updated.contains(id) {
            updated.remove(id)
        } else {
            updated.insert(id)
        }
        return updated.sorted().joined(separator: ",")
    }

    private func hasNonEmptyInfoPlistValue(_ key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AppleEventKitSource: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
}

private enum AIConnectionPhase {
    case notConnected
    case keySaved
    case testing
    case ready
    case error

    var title: String {
        let isFrench = AppLanguage.current == .french
        switch self {
        case .notConnected:
            return isFrench ? "Non connecté" : "Not connected"
        case .keySaved:
            return isFrench ? "Clé enregistrée · test requis" : "Key saved · test required"
        case .testing:
            return isFrench ? "Test en cours" : "Testing"
        case .ready:
            return isFrench ? "Prêt" : "Ready"
        case .error:
            return isFrench ? "Erreur" : "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .notConnected: return "circle"
        case .keySaved: return "key.fill"
        case .testing: return "clock.arrow.circlepath"
        case .ready: return "checkmark.seal.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notConnected: return .secondary
        case .keySaved: return .blue
        case .testing: return .orange
        case .ready: return .green
        case .error: return .red
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

private enum SettingsWorkspaceAction: Identifiable {
    case loadDemoWorkspace
    case resetDemoData
    case startEmptyWorkspace

    var id: String {
        switch self {
        case .loadDemoWorkspace: "loadDemoWorkspace"
        case .resetDemoData: "resetDemoData"
        case .startEmptyWorkspace: "startEmptyWorkspace"
        }
    }

    var title: String {
        switch self {
        case .loadDemoWorkspace: "Replace workspace with demo data?"
        case .resetDemoData: "Reset demo data?"
        case .startEmptyWorkspace: "Start empty workspace?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .loadDemoWorkspace: "Replace with Demo"
        case .resetDemoData: "Reset Demo"
        case .startEmptyWorkspace: "Erase and Start Empty"
        }
    }

    var message: String {
        switch self {
        case .loadDemoWorkspace: "Loading the demo workspace replaces the current workspace data in this store."
        case .resetDemoData: "This removes the current workspace and loads fresh demo data."
        case .startEmptyWorkspace: "This removes the current workspace data and starts with a blank workspace."
        }
    }
}
