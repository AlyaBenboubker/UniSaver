import Foundation

enum AcademicValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case invalidDateRange
    case invalidTimeRange
    case invalidDuration
    case semesterOutsideAcademicYear
    case chapterCourseMismatch
    case duplicateCourse

    var errorDescription: String? {
        switch self {
        case .emptyName: "A name is required."
        case .invalidDateRange: "The end date must be after the start date."
        case .invalidTimeRange: "The end time must be after the start time."
        case .invalidDuration: "The estimated duration must be positive."
        case .semesterOutsideAcademicYear: "Semester dates must fit inside the academic year."
        case .chapterCourseMismatch: "The chapter must belong to the selected course."
        case .duplicateCourse: "A course with this name or code already exists in the selected semester."
        }
    }
}

enum AcademicValidationService {
    static func validateAcademicYear(name: String, startDate: Date, endDate: Date) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AcademicValidationError.emptyName
        }
        guard endDate > startDate else {
            throw AcademicValidationError.invalidDateRange
        }
    }

    static func validateSemester(_ semester: Semester) throws {
        guard !semester.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AcademicValidationError.emptyName
        }
        guard semester.endDate > semester.startDate else {
            throw AcademicValidationError.invalidDateRange
        }
        if let year = semester.academicYear {
            guard semester.startDate >= year.startDate && semester.endDate <= year.endDate else {
                throw AcademicValidationError.semesterOutsideAcademicYear
            }
        }
    }

    static func validateSession(startTime: Date, endTime: Date, course: Course, chapter: Chapter?) throws {
        guard endTime > startTime else {
            throw AcademicValidationError.invalidTimeRange
        }
        if let chapter, chapter.course !== course {
            throw AcademicValidationError.chapterCourseMismatch
        }
    }

    static func validateTask(title: String, estimatedDuration: TimeInterval, course: Course?, chapter: Chapter?) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AcademicValidationError.emptyName
        }
        guard estimatedDuration > 0 else {
            throw AcademicValidationError.invalidDuration
        }
        if let course, let chapter, chapter.course !== course {
            throw AcademicValidationError.chapterCourseMismatch
        }
    }

    static func validateExam(title: String, startTime: Date?, endTime: Date?, course: Course, chapters: [Chapter]) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AcademicValidationError.emptyName
        }
        if let startTime, let endTime, endTime <= startTime {
            throw AcademicValidationError.invalidTimeRange
        }
        guard chapters.allSatisfy({ $0.course === course }) else {
            throw AcademicValidationError.chapterCourseMismatch
        }
    }

    static func validateStudyBlock(title: String, startDate: Date, endDate: Date) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AcademicValidationError.emptyName
        }
        guard endDate > startDate else {
            throw AcademicValidationError.invalidTimeRange
        }
    }

    static func structuralProgress(for sessions: [ClassSession]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let total = sessions.reduce(0) { $0 + $1.progressStatus.structuralProgress }
        return total / Double(sessions.count)
    }

    static func courseStructuralProgress(_ course: Course) -> Double {
        if course.sessions.isEmpty {
            return chapterProgress(course.chapters)
        }
        return structuralProgress(for: course.sessions)
    }

    static func chapterProgress(_ chapters: [Chapter]) -> Double {
        let visible = chapters.filter { !$0.isArchived }
        guard !visible.isEmpty else { return 0 }
        let total = visible.reduce(0.0) { partial, chapter in
            partial + chapter.status.progressWeight
        }
        return total / Double(visible.count)
    }

    static func shouldPreferArchive(course: Course) -> Bool {
        course.chapters.count + course.sessions.count > 1
    }

    static func shouldPreferArchive(chapter: Chapter) -> Bool {
        !chapter.sessions.isEmpty
    }
}

extension AcademicItemStatus {
    var progressWeight: Double {
        switch self {
        case .notStarted: 0
        case .inProgress: 0.35
        case .needsReview: 0.55
        case .completed: 0.8
        case .mastered: 1
        }
    }

    func advanced() -> AcademicItemStatus {
        switch self {
        case .notStarted: .inProgress
        case .inProgress, .needsReview: .completed
        case .completed: .mastered
        case .mastered: .mastered
        }
    }
}
