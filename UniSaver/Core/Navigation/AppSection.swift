import Foundation
import Observation
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
        title(for: AppLanguage.current)
    }

    func title(for language: AppLanguage) -> String {
        switch language {
        case .system, .english:
            switch self {
            case .today: "Today"
            case .classes: "Classes"
            case .study: "Study"
            case .planner: "Planner"
            case .progress: "Progress"
            case .library: "Library"
            case .settings: "Settings"
            }
        case .french:
            switch self {
            case .today: "Aujourd’hui"
            case .classes: "Cours"
            case .study: "Étude"
            case .planner: "Planning"
            case .progress: "Progression"
            case .library: "Bibliothèque"
            case .settings: "Réglages"
            }
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case french

    static var storageKey: String { "appLanguage" }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue) ?? .system
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System Default"
        case .english: "English"
        case .french: "Français"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .current
        case .english: Locale(identifier: "en")
        case .french: Locale(identifier: "fr")
        }
    }

    var layoutDirection: LayoutDirection {
        switch self {
        case .system, .english, .french:
            return .leftToRight
        }
    }
}

extension AppSection {
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

@Observable
final class AppNavigationState {
    var selectedSection: AppSection = .today
    var openedCourseID: UUID?
    var requestedCourseTab: CourseWorkspaceTab?
    var plannerTaskFilter: PlannerTaskFilter = .open
    var libraryCourseID: UUID?
    @ObservationIgnored var noteNavigationGuard: ((AppSection) -> Bool)?

    func select(_ section: AppSection) {
        selectedSection = section
        if section != .classes {
            openedCourseID = nil
            requestedCourseTab = nil
        }
        if section != .library {
            libraryCourseID = nil
        }
    }

    func requestSelect(_ section: AppSection) {
        if let noteNavigationGuard, !noteNavigationGuard(section) {
            return
        }
        select(section)
    }

    func openCourse(_ course: Course, tab: CourseWorkspaceTab = .overview) {
        if let noteNavigationGuard, !noteNavigationGuard(.classes) {
            return
        }
        selectedSection = .classes
        openedCourseID = course.id
        requestedCourseTab = tab
    }

    func openPlanner(filter: PlannerTaskFilter) {
        if let noteNavigationGuard, !noteNavigationGuard(.planner) {
            return
        }
        plannerTaskFilter = filter
        select(.planner)
    }

    func openLibrary(course: Course? = nil) {
        if let noteNavigationGuard, !noteNavigationGuard(.library) {
            return
        }
        libraryCourseID = course?.id
        select(.library)
    }
}
