import SwiftUI

enum CourseColor: String, CaseIterable, Identifiable {
    case blueViolet
    case teal
    case coral
    case green
    case amber
    case rose
    case indigo
    case sky
    case mint
    case lime
    case orange
    case red
    case pink
    case graphite

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blueViolet: Color(red: 0.36, green: 0.32, blue: 0.88)
        case .teal: Color(red: 0.08, green: 0.58, blue: 0.62)
        case .coral: Color(red: 0.89, green: 0.33, blue: 0.28)
        case .green: Color(red: 0.20, green: 0.55, blue: 0.31)
        case .amber: Color(red: 0.78, green: 0.52, blue: 0.12)
        case .rose: Color(red: 0.78, green: 0.25, blue: 0.48)
        case .indigo: Color(red: 0.26, green: 0.32, blue: 0.76)
        case .sky: Color(red: 0.10, green: 0.48, blue: 0.86)
        case .mint: Color(red: 0.12, green: 0.62, blue: 0.50)
        case .lime: Color(red: 0.42, green: 0.62, blue: 0.20)
        case .orange: Color(red: 0.90, green: 0.42, blue: 0.12)
        case .red: Color(red: 0.82, green: 0.20, blue: 0.22)
        case .pink: Color(red: 0.82, green: 0.24, blue: 0.58)
        case .graphite: Color(red: 0.36, green: 0.39, blue: 0.45)
        }
    }

    var title: String {
        switch self {
        case .blueViolet: "Blue violet"
        case .teal: "Teal"
        case .coral: "Coral"
        case .green: "Green"
        case .amber: "Amber"
        case .rose: "Rose"
        case .indigo: "Indigo"
        case .sky: "Sky"
        case .mint: "Mint"
        case .lime: "Lime"
        case .orange: "Orange"
        case .red: "Red"
        case .pink: "Pink"
        case .graphite: "Graphite"
        }
    }

    static func color(for identifier: String) -> Color {
        CourseColor(rawValue: identifier)?.color ?? CourseColor.blueViolet.color
    }
}

enum StudyDeskTheme {
    static let spacing: CGFloat = 16
    static let compactSpacing: CGFloat = 10
    static let cornerRadius: CGFloat = 10
    static let smallCornerRadius: CGFloat = 7
    static let dashboardMaxWidth: CGFloat = 1180
    static let shadow = Color.black.opacity(0.045)

    static var backgroundPrimary: Color { Color.studyDeskBackground }
    static var backgroundSecondary: Color { Color.studyDeskSecondaryBackground }
    static var surfacePrimary: Color { Color.studyDeskSurface }
    static var surfaceTinted: Color { Color.accentColor.opacity(0.08) }
    static var textPrimary: Color { .primary }
    static var textSecondary: Color { .secondary }
    static var borderSubtle: Color { Color.studyDeskBorder }
    static var accentPrimary: Color { CourseColor.blueViolet.color }
}

enum StudyDeskLayoutMode {
    case compact
    case medium
    case tabletExpanded
    case wide

    init(contentWidth: CGFloat) {
        if contentWidth >= 1050 {
            self = .wide
        } else if contentWidth >= 820 {
            self = .tabletExpanded
        } else if contentWidth >= 720 {
            self = .medium
        } else {
            self = .compact
        }
    }

    var outerPadding: CGFloat {
        switch self {
        case .wide: 16
        case .tabletExpanded: 16
        case .medium: 16
        case .compact: 14
        }
    }

    var cardSpacing: CGFloat {
        switch self {
        case .wide: 16
        case .tabletExpanded: 16
        case .medium: 14
        case .compact: 12
        }
    }

    var cardPadding: CGFloat {
        switch self {
        case .wide: 16
        case .tabletExpanded: 15
        case .medium: 15
        case .compact: 14
        }
    }
}

extension Color {
    static var studyDeskBackground: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.07, green: 0.075, blue: 0.09, alpha: 1)
                : NSColor(red: 0.965, green: 0.969, blue: 0.984, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.075, blue: 0.09, alpha: 1)
                : UIColor(red: 0.965, green: 0.969, blue: 0.984, alpha: 1)
        })
        #endif
    }

    static var studyDeskSecondaryBackground: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.095, green: 0.10, blue: 0.12, alpha: 1)
                : NSColor(red: 0.985, green: 0.985, blue: 0.99, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.095, green: 0.10, blue: 0.12, alpha: 1)
                : UIColor(red: 0.985, green: 0.985, blue: 0.99, alpha: 1)
        })
        #endif
    }

    static var studyDeskSurface: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.12, green: 0.125, blue: 0.145, alpha: 1)
                : NSColor.white
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.12, green: 0.125, blue: 0.145, alpha: 1)
                : UIColor.white
        })
        #endif
    }

    static var studyDeskBorder: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor(red: 0.898, green: 0.906, blue: 0.922, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.10)
                : UIColor(red: 0.898, green: 0.906, blue: 0.922, alpha: 1)
        })
        #endif
    }
}

struct DeskCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: StudyDeskTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StudyDeskTheme.cornerRadius, style: .continuous)
                    .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
            }
            .shadow(color: StudyDeskTheme.shadow, radius: 12, y: 5)
    }
}

extension View {
    func deskCard() -> some View {
        modifier(DeskCardModifier())
    }
}
