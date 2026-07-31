import SwiftUI

struct PlaceholderFeatureView: View {
    let section: AppSection

    var body: some View {
        EmptyStateView(
            title: "\(section.title) is planned",
            message: "This workspace is reserved for a future lot. The current build focuses on Today, Classes, chapters, sessions, and durable SwiftData persistence.",
            systemImage: section.symbolName
        )
        .navigationTitle(section.title)
        .background(Color.studyDeskBackground)
    }
}
