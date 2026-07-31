import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case classes
    case study
    case planner
    case progress
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .classes: "Classes"
        case .study: "Study"
        case .planner: "Planner"
        case .progress: "Progress"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.max"
        case .classes: "books.vertical"
        case .study: "rectangle.stack.badge.play"
        case .planner: "calendar"
        case .progress: "chart.line.uptrend.xyaxis"
        case .library: "folder"
        case .settings: "gearshape"
        }
    }
}
