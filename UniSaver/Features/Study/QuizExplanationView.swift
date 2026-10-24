import SwiftUI

struct QuizExplanationView: View {
    let explanation: String
    @State private var expanded = true
    var body: some View {
        if explanation.count > 320 {
            DisclosureGroup(studyText("Explanation"), isExpanded: $expanded) {
                Text(explanation).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        } else if !explanation.isEmpty {
            Text(explanation).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
