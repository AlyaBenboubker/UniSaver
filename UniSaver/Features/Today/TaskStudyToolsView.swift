import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TaskStudyToolsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    let task: AcademicTask
    let assignment: AssignmentPlanProject?
    @Binding var draft: TaskWorkspaceDraft
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @State private var openResource: AcademicResource?
    @State private var importing = false
    @State private var link = ""
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var requestID: UUID?
    @Binding var showsAgent: Bool
    var saveStatus: String
    @Binding var selectedResourceID: UUID?
    @State private var narrowTab = "Resource"
    @State private var showsLink = false
    @State private var showsInstructions = false
    @State private var instructions = ""
    @State private var readsInstructions = false
    @State private var usesColumns = false

    private var selectedResources: [AcademicResource] {
        resources.filter { draft.resourceIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !usesColumns {
                Picker("Workspace panel", selection: $narrowTab) {
                    Text("Resource").tag("Resource")
                    Text("Notes").tag("Notes")
                    Text("Agent").tag("Agent")
                }.pickerStyle(.segmented).padding(10)
            }
            HStack(spacing: 0) {
                if usesColumns || narrowTab == "Resource" {
                    VStack(alignment: .leading, spacing: 12) {
                        resourcePicker
                        resourcePreview.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if usesColumns { Divider() }
                ZStack(alignment: .topLeading) {
                    notesEditor
                        .opacity((usesColumns ? !showsAgent : narrowTab == "Notes") ? 1 : 0)
                        .allowsHitTesting(usesColumns ? !showsAgent : narrowTab == "Notes")
                        .accessibilityHidden(usesColumns ? showsAgent : narrowTab != "Notes")
                    if usesColumns ? showsAgent : narrowTab == "Agent" {
                        ScrollView { agentPanel.padding(14) }
                    }
                }
                .frame(width: usesColumns ? 360 : nil)
                .frame(maxWidth: usesColumns ? nil : .infinity, maxHeight: .infinity)
                .frame(width: !usesColumns && narrowTab == "Resource" ? 0 : nil)
                .clipped()
            }
            if let error { Text(error).foregroundStyle(.orange).font(.caption).padding(8) }
        }
        .onGeometryChange(for: Bool.self) { proxy in proxy.size.width >= 790 } action: { usesColumns = $0 }
        .onChange(of: selectedResourceID) { _, _ in readsInstructions = false; if !usesColumns { narrowTab = "Resource" } }
        .onChange(of: showsAgent) { _, value in if value { narrowTab = "Agent" } }
        .sheet(isPresented: $showsLink) {
            VStack(spacing: 16) {
                TextField("https://…", text: $link).textFieldStyle(.roundedBorder)
                Button("Add link") {
                    let clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let url = URL(string: clean), ["https", "http"].contains(url.scheme?.lowercased()), url.host != nil else {
                        error = "Enter an http or https link."; return
                    }
                    if !draft.links.contains(clean) { draft.links.append(clean) }
                    link = ""; showsLink = false
                }
                Button("Cancel") { showsLink = false }
            }.padding().frame(idealWidth: 360)
        }
        .sheet(isPresented: $showsInstructions) {
            VStack(spacing: 12) {
                Text("Paste instructions").font(.headline)
                TextEditor(text: $instructions).frame(minHeight: 200).accessibilityLabel("Assignment instructions")
                Button("Add instructions") {
                    draft.pastedInstructions = instructions
                    instructions = ""; showsInstructions = false; narrowTab = "Resource"; readsInstructions = true
                }.disabled(instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") { showsInstructions = false }
            }.padding().frame(idealWidth: 440)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .plainText, .image, .data]) { result in
            do {
                let url = try result.get()
                let resource: AcademicResource
                do {
                    resource = try ResourceImportService.submit(
                        draft: ResourceImportDraft(fileURL: url, title: url.deletingPathExtension().lastPathComponent,
                            resourceDescription: "Task work resource", course: task.course, chapter: task.chapter, session: nil, tags: []),
                        existingResources: resources, modelContext: modelContext, fileStore: AcademicFileStore())
                } catch ResourceImportSubmitError.duplicate(let id) {
                    guard let existing = resources.first(where: { $0.id == id }) else { throw AcademicFileStoreError.fileMissing }
                    resource = existing
                }
                if !draft.resourceIDs.contains(resource.id) { draft.resourceIDs.append(resource.id) }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
        .sheet(item: $openResource) { resource in
            VStack {
                HStack { Text(resource.title).font(.headline); Spacer(); Button("Close") { openResource = nil } }.padding()
                ResourceDetailView(resource: resource)
            }.frame(minWidth: 600, minHeight: 600)
        }
        .onDisappear { cancelRequest() }
    }

    private var resourcePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Resources").font(.headline)
                Spacer()
                Menu("Add resource") {
                    Menu("Attach existing resource") {
                        ForEach(resources.filter { $0.course?.id == task.course?.id && !draft.resourceIDs.contains($0.id) }) { resource in
                            Button(resource.title) { draft.resourceIDs.append(resource.id); selectedResourceID = resource.id }
                        }
                    }
                    Button("Import file") { importing = true }
                    Button("Add link") { showsLink = true }
                    Button("Paste instructions") { showsInstructions = true }
                }
            }
            if !selectedResources.isEmpty {
                Picker("Selected resource", selection: Binding(
                    get: { selectedResourceID ?? selectedResources.first?.id },
                    set: { selectedResourceID = $0; readsInstructions = false }
                )) {
                    ForEach(selectedResources) { Text($0.title).tag(Optional($0.id)) }
                }.labelsHidden()
            }
            if let pasted = draft.pastedInstructions, !pasted.isEmpty {
                Button(readsInstructions ? "Viewing pasted instructions" : "View pasted instructions") { readsInstructions = true }
                if readsInstructions, selectedResource != nil {
                    Button("View selected resource") { readsInstructions = false }
                }
            }
            if let resource = selectedResource {
                HStack {
                    Button("Open externally") {
                        do { openURL(try AcademicFileStore().url(for: resource.storedRelativePath)) }
                        catch { self.error = error.localizedDescription }
                    }
                    Spacer()
                    Menu("Resource actions") {
                        Button("Detach") { draft.resourceIDs.removeAll { $0 == resource.id }; selectedResourceID = nil }
                    }
                }.controlSize(.small)
            }
            if !draft.links.isEmpty {
                Menu("Links — open externally") {
                    ForEach(draft.links, id: \.self) { value in
                        if let url = URL(string: value) { Link(value, destination: url) }
                    }
                }
            }
            if let assignment {
                DisclosureGroup("Assignment instructions · original source") {
                    ScrollView {
                        Text(assignment.extractedText.isEmpty ? assignment.pastedInstructions : assignment.extractedText)
                            .textSelection(.enabled)
                    }.frame(maxHeight: 180)
                }.font(.caption)
            }
        }
    }

    private var selectedResource: AcademicResource? {
        selectedResources.first { $0.id == selectedResourceID } ?? selectedResources.first
    }

    @ViewBuilder private var resourcePreview: some View {
        if let pasted = draft.pastedInstructions, !pasted.isEmpty, readsInstructions || selectedResource == nil {
            ScrollView { Text(pasted).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        } else if let resource = selectedResource {
            ResourceDetailView(readerOnly: true, resource: resource).id(resource.id)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add your assignment or course material.").foregroundStyle(.secondary)
                if let assignment {
                    ScrollView {
                        Text(assignment.extractedText.isEmpty ? assignment.pastedInstructions : assignment.extractedText)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer()
            }
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Working notes").font(.headline)
                Spacer()
                Text(saveStatus).font(.caption).foregroundStyle(.secondary)
            }
            if usesColumns {
                Button("Agent", systemImage: "sparkles") { showsAgent = true }
            }
            TextEditor(text: $draft.notes).frame(maxHeight: .infinity)
                .accessibilityLabel("Working notes").accessibilityIdentifier("taskWorkingNotes")
            Text("\(draft.notes.count) characters").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("taskNotesCharacterCount")
            Toggle("Share notes with agent", isOn: $draft.shareNotes)
            TextField("Next action / remaining work", text: $draft.remainingWork, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }.padding(14)
    }

    private var agentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Working notes", systemImage: "note.text") { showsAgent = false; narrowTab = "Notes" }
            Text(AIRevisionAssistantClient().activeProviderSummary()).font(.caption).foregroundStyle(.secondary)
            Text("Attached: task, current checklist, reviewed brief, \(selectedResources.count) resources; notes \(draft.shareNotes ? "shared" : "not shared"). History: last 12 messages; long excerpts are limited.")
                .font(.caption).foregroundStyle(.secondary)
            if draft.resourceIDs.count > 4 { Text("AI uses the first 4 attached resources only.").font(.caption).foregroundStyle(.orange) }
            ForEach(draft.messages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.role == .student ? "You" : "UniSaver").font(.caption.bold())
                    Text(message.text).textSelection(.enabled)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyDeskTheme.surfaceTinted, in: RoundedRectangle(cornerRadius: 8))
            }
            ViewThatFits(in: .horizontal) {
                HStack { shortcuts }
                VStack(alignment: .leading) { shortcuts }
            }
            TextField("Ask a question or paste your attempt", text: $draft.questionDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...8)
            HStack {
                if requestID != nil { ProgressView().controlSize(.small); Button("Cancel", action: cancelRequest) }
                else { Button("Send", action: send).buttonStyle(.borderedProminent).disabled(draft.questionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    @ViewBuilder private var shortcuts: some View {
        Button("Explain this") { draft.questionDraft = "Explain the current step and distinguish teacher requirements from general advice." }
        Button("Give me a hint") { draft.questionDraft = "Give me just one next-step hint for the current step." }
        Button("Check my attempt") { draft.questionDraft = "Check this attempt. What is correct, where is the first problem, why, and what should I try next?\n" }
        Button("Practise a similar question") { draft.questionDraft = "Suggest one similar practice question as an unverified draft. Let me attempt it before correction." }
    }

    private func send() {
        let text = draft.questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, requestID == nil else { return }
        draft.messages.append(TodayConversationMessage(role: .student, text: text))
        draft.helpRequests += 1
        let id = UUID()
        requestID = id
        error = nil
        request = Task { @MainActor in
            do {
                let identity = await AccountSyncService().restoreSession()
                let accountID: String
                if case .signedIn(let account) = identity { accountID = account.stableUserID } else { accountID = "local-signed-out" }
                if let previous = draft.accountID, previous != accountID {
                    draft.messages = [TodayConversationMessage(role: .student, text: text)]
                    draft.resourceIDs = []; draft.shareNotes = false
                }
                draft.accountID = accountID
                let snapshot = draft
                let resourcesSnapshot = Array(selectedResources.prefix(4))
                let sources = try TaskWorkspaceService.sources(resources: resourcesSnapshot, query: text)
                let answer = try await AIRevisionAssistantClient().taskConversation(task: task,
                    context: TaskWorkspaceService.context(task: task, draft: snapshot, assignment: assignment),
                    messages: snapshot.messages, sources: sources)
                try Task.checkCancellation()
                let latest = await AccountSyncService().restoreSession()
                let latestID: String
                if case .signedIn(let account) = latest { latestID = account.stableUserID } else { latestID = "local-signed-out" }
                guard latestID == accountID else { requestID = nil; request = nil; return }
                guard requestID == id else { return }
                draft.messages.append(TodayConversationMessage(role: .agent, text: answer))
                if draft.questionDraft == text { draft.questionDraft = "" }
            } catch {
                guard requestID == id else { return }
                self.error = error is CancellationError ? "Request cancelled. Your draft is kept." : error.localizedDescription
            }
            if requestID == id { requestID = nil; request = nil }
        }
    }

    private func cancelRequest() {
        request?.cancel(); request = nil; requestID = nil
    }

    private var history: some View {
        TaskSessionHistoryView(taskID: task.id)
    }
}

struct TaskSessionHistoryView: View {
    let taskID: UUID
    @Environment(\.openURL) private var openURL
    @Query private var notes: [StudyNote]
    @State private var error: String?
    private var records: [TaskExecutionRecord] {
        notes.first(where: { $0.body.hasPrefix(TaskExecutionLedgerStore.marker) })
            .map { TaskExecutionLedgerStore.decode($0) }?.records.filter { $0.taskID == taskID }.sorted { $0.endedAt > $1.endedAt } ?? []
    }
    var body: some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved session reviews").font(.headline)
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(record.endedAt.formatted()) · \(record.finishedTask ? "Task finished" : "Session saved; task continues")").font(.subheadline.bold())
                        Text(record.note).textSelection(.enabled)
                        if let remaining = record.remainingWork, !remaining.isEmpty { Text("Next: \(remaining)") }
                        Text(record.completedSubtaskTitles.joined(separator: " · ")).font(.caption)
                        ForEach(record.attachments) { attachment in
                            if attachment.kind == .note { Text(attachment.note).textSelection(.enabled) }
                            else {
                                Button(attachment.displayName) {
                                    do {
                                        if let path = attachment.storedRelativePath { openURL(try AcademicFileStore().url(for: path)) }
                                        else if let value = attachment.urlString, let url = URL(string: value) { openURL(url) }
                                    } catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                    }.padding(10).deskCard()
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }
        }
    }
}
