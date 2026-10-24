import SwiftData
import SwiftUI

/// Shared entry point for the existing work session from a class assignment.
struct TaskWorkSessionHostView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [StudyNote]
    let task: AcademicTask
    var onClose: (() -> Void)? = nil
    @State private var ledger: TaskExecutionLedger?
    @State private var error: String?

    var body: some View {
        Group {
            if let ledger {
                TaskWorkSessionSheet(task: task, ledger: ledger, onSaveLedger: save,
                    onToggleSubtask: { item, value in
                        let previous = task.taskDescription
                        TaskStructureService.setSubtask(item, completed: value, in: task)
                        do { try modelContext.save() } catch { task.taskDescription = previous; self.error = error.localizedDescription; throw error }
                    }, onAddSuggestedSteps: {
                        let previous = task.taskDescription
                        TaskStructureService.appendSuggestedSteps(to: task)
                        do { try modelContext.save() } catch { task.taskDescription = previous; self.error = error.localizedDescription; throw error }
                    }, onUpdateTaskStatus: updateStatus, onClose: { if let onClose { onClose() } else { dismiss() } })
            } else { ProgressView().onAppear { ledger = TaskExecutionLedgerStore.decode(TaskExecutionLedgerStore.ledgerNote(in: notes, context: modelContext)) } }
        }
        .overlay(alignment: .top) {
            if let error { Text(error).padding().background(.regularMaterial).foregroundStyle(.orange) }
        }
    }

    private func save(_ value: TaskExecutionLedger) throws {
        let note = TaskExecutionLedgerStore.ledgerNote(in: notes, context: modelContext)
        let previous = note.body
        TaskExecutionLedgerStore.save(value, into: note)
        do { try modelContext.save(); ledger = value }
        catch { note.body = previous; throw error }
    }

    private func updateStatus(_ status: AcademicTaskStatus) throws {
        let previousStatus = task.status
        task.status = status
        task.updatedAt = .now
        let note = GamificationLedgerStore.ledgerNote(in: notes, context: modelContext)
        let previousBody = note.body
        var value = GamificationLedgerStore.decode(note)
        if status == .completed {
            GamificationLedgerStore.award(activityType: .taskCompletion, sourceID: task.id.uuidString, courseID: task.course?.id, ledger: &value)
        } else {
            GamificationLedgerStore.annul(activityType: .taskCompletion, sourceID: task.id.uuidString, ledger: &value)
        }
        GamificationLedgerStore.save(value, into: note)
        do { try modelContext.save() } catch {
            task.status = previousStatus
            note.body = previousBody
            self.error = error.localizedDescription
            throw error
        }
    }
}
