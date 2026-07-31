import SwiftUI

enum CourseColor: String, CaseIterable, Identifiable {
    case blueViolet
    case teal
    case coral
    case green
    case amber
    case rose

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blueViolet: Color(red: 0.36, green: 0.32, blue: 0.88)
        case .teal: Color(red: 0.08, green: 0.58, blue: 0.62)
        case .coral: Color(red: 0.89, green: 0.33, blue: 0.28)
        case .green: Color(red: 0.20, green: 0.55, blue: 0.31)
        case .amber: Color(red: 0.78, green: 0.52, blue: 0.12)
        case .rose: Color(red: 0.78, green: 0.25, blue: 0.48)
        }
    }

    static func color(for identifier: String) -> Color {
        CourseColor(rawValue: identifier)?.color ?? CourseColor.blueViolet.color
    }
}

extension Color {
    static var studyDeskBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}

struct DeskCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    func deskCard() -> some View {
        modifier(DeskCardModifier())
    }
}
