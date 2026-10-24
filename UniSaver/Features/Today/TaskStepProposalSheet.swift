import SwiftData
import SwiftUI

/// Shared by the existing conversation review and task breakdown review.
struct ConversationStepsEditor: View {
    @Binding var steps: [ConversationSubtaskDraft]
    var allowsSelection = false
    var allowsCompletion = false

    var body: some View {
        ForEach($steps) { $step in
            VStack(alignment: .leading, spacing: 8) {
                if allowsSelection { Toggle("Include step", isOn: $step.isSelected) }
                TextField("Step title", text: Binding(get: { step.title }, set: { step.title = $0; step.evidence = .suggested }))
                TextField("Description / completion criterion", text: Binding(
                    get: { step.completionCriterion ?? "" }, set: { step.completionCriterion = $0; step.evidence = .suggested }), axis: .vertical)
                if let dependencies = step.dependencies, !dependencies.isEmpty {
                    Text("Suggested dependencies: " + dependencies.joined(separator: "; ")).font(.caption)
                }
                if allowsCompletion {
                    Toggle("Already completed — confirm in review", isOn: Binding(
                        get: { step.isCompleted == true }, set: { step.isCompleted = $0 }))
                }
                Text(step.evidence.title).font(.caption).foregroundStyle(.secondary)
                if let excerpt = step.sourceExcerpt {
                    Text("Source: \(excerpt)").font(.caption).textSelection(.enabled)
                }
                HStack {
                    Button("Move up") { move(step.id, by: -1) }
                        .disabled(steps.first?.id == step.id)
                    Button("Move down") { move(step.id, by: 1) }
                        .disabled(steps.last?.id == step.id)
                    Spacer()
                    Button("Remove", role: .destructive) { steps.removeAll { $0.id == step.id } }
                }.controlSize(.small)
            }.padding().deskCard()
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }), steps.indices.contains(index + offset) else { return }
        steps.swapAt(index, index + offset)
    }
}

struct TaskStepProposalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: AcademicTask
    var onOpenFirstStep: () -> Void = {}
    @State private var proposalID = UUID()
    @State private var snapshot: TaskStepReviewSnapshot?
    @State private var applied = false
    @State private var isSaving = false
    @State private var showsChecklist = false
    @State private var needsReview = false
    @State private var assignment = ""
    @State private var steps: [ConversationSubtaskDraft] = []
    @State private var request: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var status: String?
    @State private var error: String?

    init(task: AcademicTask, onOpenFirstStep: @escaping () -> Void = {}, existingReceipt: TaskStepApprovalReceipt? = nil) {
        self.task = task
        self.onOpenFirstStep = onOpenFirstStep
        _steps = State(initialValue: existingReceipt?.steps ?? [])
        _proposalID = State(initialValue: existingReceipt?.proposalID ?? UUID())
        _applied = State(initialValue: existingReceipt != nil)
        _status = State(initialValue: existingReceipt == nil ? nil : "Saved plan — already applied. It cannot be saved again.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Break into steps — \(task.title)").font(.title3.bold())
            Text(task.course?.name ?? "Unassigned subject").foregroundStyle(.secondary)
            Text(AIRevisionAssistantClient().activeProviderSummary()).font(.caption)
            if !applied || !assignment.isEmpty {
                Text("Paste assignment instructions")
                TextEditor(text: $assignment).frame(minHeight: 120, maxHeight: 200)
                    .accessibilityLabel("Assignment instructions")
                    .disabled(requestID != nil || applied || isSaving)
            }
            Text("Review suggested work and source evidence. Steps are saved only when you approve.")
                .font(.caption).foregroundStyle(.secondary)
            if requestID != nil {
                HStack { ProgressView(); Text("Generating steps…"); Button("Cancel request") { cancel() } }
            } else if !applied {
                Button(steps.isEmpty ? "Propose steps" : "Regenerate steps", action: generate)
                    .disabled(assignment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let status { Text(status).font(.caption) }
            DisclosureGroup("Current task checklist", isExpanded: $showsChecklist) {
                ForEach(TaskStructureService.subtasks(from: task)) { step in
                    Text("\(step.isCompleted ? "✓" : "○") \(step.title)").font(.caption)
                }
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if needsReview {
                Button("Refresh task context for review", action: refreshContext)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { ConversationStepsEditor(steps: $steps) }.disabled(applied || isSaving || requestID != nil)
            }
            HStack {
                Button(applied ? "Close" : "Cancel") { cancel(); dismiss() }
                Spacer()
                if applied {
                    Button("Open first incomplete step") { onOpenFirstStep(); dismiss() }
                        .disabled(!TaskStructureService.subtasks(from: task).contains { !$0.isCompleted })
                } else {
                    Button("Save approved steps", action: saveApproved)
                        .buttonStyle(.borderedProminent)
                        .disabled(steps.isEmpty || requestID != nil || isSaving || snapshot == nil || needsReview)
                }
            }
        }.padding(24).frame(minWidth: 620, minHeight: 650)
            .onDisappear { cancel() }
            .interactiveDismissDisabled(requestID != nil)
    }

    private func cancel() {
        requestID = nil
        request?.cancel()
        request = nil
        status = "Request cancelled. Your pasted text is preserved while this review is open."
    }

    private func saveApproved() {
        guard !isSaving, !applied, let snapshot else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try TaskStepApprovalService.apply(proposalID: proposalID, steps: steps, snapshot: snapshot,
                selectedTask: task, context: modelContext)
            applied = true
            error = nil
            status = "Approved steps saved under this task. Existing steps and notes were preserved."
        } catch TaskStepApprovalError.alreadyApplied {
            applied = true
            error = nil
            status = "This proposal was already saved. No duplicates were added."
        } catch TaskStepApprovalError.changedTask {
            needsReview = true
            error = TaskStepApprovalError.changedTask.localizedDescription
        } catch { self.error = error.localizedDescription }
    }

    private func refreshContext() {
        do {
            snapshot = try TaskStepApprovalService.refresh(task, context: modelContext)
            needsReview = false
            showsChecklist = true
            error = nil
            status = "Task context refreshed. Review your proposed steps against the current checklist before saving."
        } catch { self.error = error.localizedDescription }
    }

    private func generate() {
        let id = UUID()
        requestID = id
        error = nil
        status = nil
        let text = assignment
        let reviewSnapshot = TaskStepReviewSnapshot(task)
        let existing = TaskStructureService.subtasks(from: task)
        request = Task { @MainActor in
            defer { if requestID == id { requestID = nil; request = nil } }
            do {
                let provider = try AIRevisionAssistantClient().conversationProvider()
                let result = try await TaskStepProposalService.propose(title: task.title,
                    subject: task.course?.name ?? "Unassigned", existing: existing,
                    assignment: text, provider: provider)
                guard requestID == id, !Task.isCancelled else { return }
                steps = result
                snapshot = reviewSnapshot
                proposalID = UUID()
                needsReview = false
                status = "Review, edit, remove or reorder these temporary steps."
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
}
