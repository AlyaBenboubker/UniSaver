import Foundation
import SwiftData
import Testing
@testable import UniSaver

struct UniSaverTests {
    @Test func academicYearRequiresValidDateRange() throws {
        let start = Date()
        let end = start.addingTimeInterval(-3600)
        #expect(throws: AcademicValidationError.invalidDateRange) {
            try AcademicValidationService.validateAcademicYear(name: "2026", startDate: start, endDate: end)
        }
    }

    @Test func semesterDatesMustBeCoherentAndInsideYear() throws {
        let start = Date()
        let year = AcademicYear(name: "Year", startDate: start, endDate: start.addingTimeInterval(10_000))
        let semester = Semester(name: "S1", order: 1, startDate: start.addingTimeInterval(100), endDate: start.addingTimeInterval(9_000), academicYear: year)
        try AcademicValidationService.validateSemester(semester)

        semester.endDate = start.addingTimeInterval(20_000)
        #expect(throws: AcademicValidationError.semesterOutsideAcademicYear) {
            try AcademicValidationService.validateSemester(semester)
        }
    }

    @Test func sessionEndTimeMustBeAfterStartTime() throws {
        let course = Course(name: "Mathematics", code: "MAT")
        let start = Date()
        #expect(throws: AcademicValidationError.invalidTimeRange) {
            try AcademicValidationService.validateSession(startTime: start, endTime: start, course: course, chapter: nil)
        }
    }

    @Test func sessionChapterMustBelongToSameCourse() throws {
        let course = Course(name: "Microeconomics", code: "ECO")
        let otherCourse = Course(name: "German", code: "GER")
        let chapter = Chapter(number: 1, title: "A2", order: 1, course: otherCourse)
        let start = Date()
        let end = start.addingTimeInterval(3600)

        #expect(throws: AcademicValidationError.chapterCourseMismatch) {
            try AcademicValidationService.validateSession(startTime: start, endTime: end, course: course, chapter: chapter)
        }
    }

    @Test func progressCycleAndWeightsAreStable() {
        #expect(SessionProgressStatus.captured.structuralProgress == 0.2)
        #expect(SessionProgressStatus.organized.structuralProgress == 0.4)
        #expect(SessionProgressStatus.reviewed.structuralProgress == 0.6)
        #expect(SessionProgressStatus.practiced.structuralProgress == 0.8)
        #expect(SessionProgressStatus.mastered.structuralProgress == 1.0)
        #expect(SessionProgressStatus.captured.advanced() == .organized)
        #expect(SessionProgressStatus.practiced.advanced() == .mastered)
        #expect(SessionProgressStatus.mastered.advanced() == .mastered)
    }

    @Test func structuralProgressIsAverageOfSessions() {
        let now = Date()
        let course = Course(name: "Computing", code: "CS")
        let first = ClassSession(number: 1, title: "Intro", date: now, startTime: now, endTime: now.addingTimeInterval(3600), progressStatus: .captured, course: course)
        let second = ClassSession(number: 2, title: "Practice", date: now, startTime: now, endTime: now.addingTimeInterval(3600), progressStatus: .mastered, course: course)
        #expect(AcademicValidationService.structuralProgress(for: [first, second]) == 0.6)
    }

    @Test func createCourseChapterAndSessionPersistInSwiftData() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let start = Date()
        let year = AcademicYear(name: "Year", startDate: start, endDate: start.addingTimeInterval(10_000))
        let semester = Semester(name: "S1", order: 1, startDate: start, endDate: start.addingTimeInterval(5_000), academicYear: year)
        let course = Course(name: "Microeconomics", code: "ECO101", semester: semester)
        let chapter = Chapter(number: 1, title: "Supply and Demand", order: 1, course: course)
        let session = ClassSession(number: 1, title: "Demand", date: start, startTime: start, endTime: start.addingTimeInterval(3600), course: course, chapter: chapter)
        context.insert(year)
        context.insert(semester)
        context.insert(course)
        context.insert(chapter)
        context.insert(session)
        try context.save()

        let descriptor = FetchDescriptor<Course>()
        let saved = try context.fetch(descriptor)
        #expect(saved.count == 1)
        #expect(saved.first?.chapters.count == 1)
        #expect(saved.first?.sessions.count == 1)
    }

    @Test func sessionsSortChronologically() {
        let now = Date()
        let course = Course(name: "Math", code: "MAT")
        let later = ClassSession(number: 2, title: "Later", date: now, startTime: now.addingTimeInterval(7200), endTime: now.addingTimeInterval(9000), course: course)
        let earlier = ClassSession(number: 1, title: "Earlier", date: now, startTime: now, endTime: now.addingTimeInterval(3600), course: course)
        let sorted = [later, earlier].sorted { $0.startTime < $1.startTime }
        #expect(sorted.map(\.title) == ["Earlier", "Later"])
    }

    @Test func archiveIsPreferredWhenDeletionWouldRemoveAssociatedData() {
        let course = Course(name: "Math", code: "MAT")
        course.chapters.append(Chapter(number: 1, title: "Linear Algebra", order: 1, course: course))
        course.sessions.append(ClassSession(number: 1, title: "Matrices", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600), course: course))
        #expect(AcademicValidationService.shouldPreferArchive(course: course))
    }

    @Test func previewDataIsIsolatedInMemory() throws {
        let container = PersistenceController.previewContainer()
        let context = ModelContext(container)
        let courses = try context.fetch(FetchDescriptor<Course>())
        #expect(courses.contains { $0.name == "Microeconomics" })
        #expect(courses.contains { $0.name == "German" })
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration("TestStore", schema: PersistenceController.schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: PersistenceController.schema, configurations: [configuration])
    }
}
