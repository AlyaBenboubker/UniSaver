import SwiftData
import SwiftUI

/// Explicit DEBUG-only fixture entry point. Never seeds the production store.
struct WorkspaceAppRootView: View {
    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--exam-lab-validation") {
            ExamLabValidationView()
        } else if ProcessInfo.processInfo.arguments.contains("--p0-validation") {
            TaskWorkspaceValidationView()
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }
}

#if DEBUG
struct TaskWorkspaceValidationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [AcademicTask]
    @State private var workTask: AcademicTask?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 16) {
            Text("Isolated P0 validation — temporary store").font(.headline)
            if let task = tasks.first {
                Text(task.status.title)
                Button("Open validation task") { workTask = task }.accessibilityIdentifier("openValidationTask")
                TaskSessionHistoryView(taskID: task.id)
            }
            if let error { Text(error) }
        }.padding().frame(minWidth: 950, minHeight: 700)
            .overlay {
                if let task = workTask {
                    TaskWorkSessionHostView(task: task, onClose: { workTask = nil })
                        .background(StudyDeskTheme.backgroundPrimary)
                }
            }
            .onAppear {
                guard tasks.isEmpty else { return }
                do {
                    let course = Course(name: "Algebra validation", code: "P0")
                    let task = AcademicTask(title: "HW2 submission", taskDescription: "Finish when the two equations are solved and checked.\n- [ ] Solve 2x = 8\n- [ ] Check by substitution\n- [ ] Submit the PDF", dueDate: .distantFuture, course: course)
                    var project = AssignmentPlanProject(title: "HW2 submission", courseName: course.name)
                    project.extractedText = "HW2 submission\nSolve 2x = 8. Explain your steps. Submit a PDF. No deadline supplied."
                    project.milestones = [AssignmentMilestoneDraft(title: task.title, detail: task.taskDescription, estimatedMinutes: 15, priority: .medium, createdTaskID: task.id)]
                    let note = StudyNote(title: project.title, course: course)
                    AssignmentPlanStore.save(project, into: note)
                    modelContext.insert(course); modelContext.insert(task); modelContext.insert(note)
                    try modelContext.save()
                } catch { self.error = error.localizedDescription }
            }
    }
}
#endif
