import AppKit
import SwiftUI
import Observation

// Shared state keeps the existing quiz and its separate focus window in sync.
@Observable @MainActor final class QuizPracticeSession: NSObject, NSWindowDelegate {
    var index = 0
    var answers: [String] = []
    var submitted: Set<Int> = []
    var marked: Set<Int> = []
    var hinted: Set<Int> = []
    var validationMessage: String?
    var result: (score: Double, maximum: Double)?
    weak var returnWindow: NSWindow?
    var isFocused = false
    @discardableResult func submitCurrent() -> Bool {
        guard answers.indices.contains(index), !answers[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !submitted.contains(index) else { return false }
        submitted.insert(index)
        return true
    }
    func windowWillClose(_ notification: Notification) {
        isFocused = false
        // Restore keyboard and accessibility focus to the original sheet's window.
        let parent = returnWindow
        Task { @MainActor in parent?.makeKeyAndOrderFront(nil) }
    }
}

struct QuizFocusWorkspace: View {
    let content: () -> AnyView
    var body: some View { content() }
}
