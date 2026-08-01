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

    @Test func dashboardSnapshotFiltersSelectedDateAndSortsTimeline() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let course = Course(name: "Microeconomics", code: "ECO")
        let later = session("Later", course: course, day: today, hour: 14)
        let earlier = session("Earlier", course: course, day: today, hour: 9)
        let tomorrowSession = session("Tomorrow", course: course, day: tomorrow, hour: 10)
        let blockStart = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today) ?? today
        let block = StudyBlock(title: "Practice", startDate: blockStart, endDate: blockStart.addingTimeInterval(3600), course: course)

        let snapshot = TodayDashboardService.makeSnapshot(
            selectedDate: today,
            workspace: nil,
            courses: [course],
            sessions: [later, tomorrowSession, earlier],
            tasks: [],
            exams: [],
            studyBlocks: [block],
            readingProgress: [],
            now: today
        )

        #expect(snapshot.sessions.map(\.title) == ["Earlier", "Later"])
        #expect(snapshot.timelineItems.map(\.subtitle) == ["Earlier", "Practice", "Later"])
        #expect(!snapshot.sessions.contains { $0.title == "Tomorrow" })
    }

    @Test func dashboardSelectsNextSessionFromNow() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let course = Course(name: "Math", code: "MAT")
        let past = session("Past", course: course, day: today, hour: 8)
        let next = session("Next", course: course, day: today, hour: 12)
        let later = session("Later", course: course, day: today, hour: 15)
        let now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today

        let snapshot = TodayDashboardService.makeSnapshot(selectedDate: today, workspace: nil, courses: [course], sessions: [later, past, next], tasks: [], exams: [], studyBlocks: [], readingProgress: [], now: now)

        #expect(snapshot.nextSession?.title == "Next")
    }

    @Test func dashboardFindsUpcomingExamAndDaysUntil() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let course = Course(name: "Microeconomics", code: "ECO")
        let examDate = calendar.date(byAdding: .day, value: 12, to: today) ?? today
        let exam = Exam(title: "Midterm", date: examDate, course: course)
        let snapshot = TodayDashboardService.makeSnapshot(selectedDate: today, workspace: nil, courses: [course], sessions: [], tasks: [], exams: [exam], studyBlocks: [], readingProgress: [], now: today)

        #expect(snapshot.upcomingExam?.title == "Midterm")
        #expect(TodayDashboardService.daysUntil(examDate, from: today) == 12)
    }

    @Test func dashboardSelectsNearestAssignmentDue() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let course = Course(name: "Math", code: "MAT")
        let soon = AcademicTask(title: "Soon", dueDate: calendar.date(byAdding: .day, value: 1, to: today) ?? today, priority: .medium, course: course)
        let urgentLater = AcademicTask(title: "Urgent later", dueDate: calendar.date(byAdding: .day, value: 2, to: today) ?? today, priority: .urgent, course: course)
        let snapshot = TodayDashboardService.makeSnapshot(selectedDate: today, workspace: nil, courses: [course], sessions: [], tasks: [urgentLater, soon], exams: [], studyBlocks: [], readingProgress: [], now: today)

        #expect(snapshot.assignmentDue?.title == "Soon")
    }

    @Test func priorityTasksSortByPriorityThenDueDate() {
        let now = Date()
        let low = AcademicTask(title: "Low", dueDate: now, priority: .low)
        let urgentLate = AcademicTask(title: "Urgent late", dueDate: now.addingTimeInterval(7200), priority: .urgent)
        let urgentSoon = AcademicTask(title: "Urgent soon", dueDate: now.addingTimeInterval(3600), priority: .urgent)
        let ordered = TodayDashboardService.priorityOrderedTasks([low, urgentLate, urgentSoon])

        #expect(ordered.map(\.title) == ["Urgent soon", "Urgent late", "Low"])
    }

    @Test func completingTaskChangesDashboardOrdering() {
        let now = Date()
        let task = AcademicTask(title: "Finish", dueDate: now, priority: .urgent)
        task.status = .completed
        let ordered = TodayDashboardService.priorityOrderedTasks([task])

        #expect(ordered.isEmpty)
    }

    @Test func dashboardCalculatesProgressPerCourse() {
        let now = Date()
        let course = Course(name: "Computing", code: "CS")
        course.sessions.append(ClassSession(number: 1, title: "Intro", date: now, startTime: now, endTime: now.addingTimeInterval(3600), progressStatus: .captured, course: course))
        course.sessions.append(ClassSession(number: 2, title: "Review", date: now, startTime: now, endTime: now.addingTimeInterval(3600), progressStatus: .mastered, course: course))
        let snapshot = TodayDashboardService.makeSnapshot(selectedDate: now, workspace: nil, courses: [course], sessions: course.sessions, tasks: [], exams: [], studyBlocks: [], readingProgress: [])

        #expect(snapshot.courseProgress.first?.progress == 0.6)
    }

    @Test func demoWorkspaceLoadIsIdempotentWithoutDuplicates() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        DemoWorkspaceService.loadDemoWorkspace(in: context)
        let firstCount = try context.fetch(FetchDescriptor<Course>()).count
        DemoWorkspaceService.loadDemoWorkspace(in: context)
        let secondCount = try context.fetch(FetchDescriptor<Course>()).count
        let workspaces = try context.fetch(FetchDescriptor<AppWorkspace>())

        #expect(firstCount == 5)
        #expect(firstCount == secondCount)
        #expect(workspaces.filter(\.isDemoWorkspace).count == 1)
    }

    @Test func demoWorkspaceCreatesExpectedAcademicDashboardData() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)

        DemoWorkspaceService.loadDemoWorkspace(in: context)

        let courses = try context.fetch(FetchDescriptor<Course>())
        let chapters = try context.fetch(FetchDescriptor<Chapter>())
        let sessions = try context.fetch(FetchDescriptor<ClassSession>())
        let tasks = try context.fetch(FetchDescriptor<AcademicTask>())
        let exams = try context.fetch(FetchDescriptor<Exam>())
        let blocks = try context.fetch(FetchDescriptor<StudyBlock>())
        let readings = try context.fetch(FetchDescriptor<ReadingProgress>())
        let workspace = try #require(try context.fetch(FetchDescriptor<AppWorkspace>()).first)

        let snapshot = TodayDashboardService.makeSnapshot(
            selectedDate: Date(),
            workspace: workspace,
            courses: courses,
            sessions: sessions,
            tasks: tasks,
            exams: exams,
            studyBlocks: blocks,
            readingProgress: readings
        )

        #expect(courses.map(\.name).sorted() == ["Computing Foundations", "German", "Mathematics", "Microeconomics", "Organizational Behavior"])
        #expect(!chapters.isEmpty)
        #expect(!sessions.isEmpty)
        #expect(!tasks.isEmpty)
        #expect(!exams.isEmpty)
        #expect(!blocks.isEmpty)
        #expect(!readings.isEmpty)
        #expect(!snapshot.timelineItems.isEmpty)
        #expect(snapshot.nextSession != nil)
        #expect(snapshot.upcomingExam != nil)
        #expect(snapshot.assignmentDue != nil)
        #expect(snapshot.flashcards.isConfigured)
    }

    @Test func dashboardPersistsNewTaskExamStudyBlockAndReadingProgress() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let now = Date()
        let course = Course(name: "German", code: "GER")
        context.insert(course)
        context.insert(AcademicTask(title: "Vocabulary", dueDate: now, priority: .high, course: course))
        context.insert(Exam(title: "Oral", date: now.addingTimeInterval(86_400), examType: .oral, course: course))
        context.insert(StudyBlock(title: "Listening", startDate: now, endDate: now.addingTimeInterval(3600), course: course))
        context.insert(ReadingProgress(resourceTitle: "Reader", currentPage: 10, totalPages: 40, course: course, coverColorIdentifier: "amber"))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<AcademicTask>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Exam>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<StudyBlock>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ReadingProgress>()).count == 1)
    }

    @Test func courseEditingArchivingAndDeletionPersist() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Business Law", code: "LAW101")
        context.insert(course)
        try context.save()

        course.professorName = "Prof. Lewis"
        course.isArchived = true
        course.updatedAt = .now
        try context.save()

        var saved = try #require(try context.fetch(FetchDescriptor<Course>()).first)
        #expect(saved.professorName == "Prof. Lewis")
        #expect(saved.isArchived)

        context.delete(saved)
        try context.save()
        saved = try context.fetch(FetchDescriptor<Course>()).first ?? Course(name: "Deleted", code: "NA")
        #expect(saved.name == "Deleted")
    }

    @Test func duplicateCourseInSameSemesterIsDetectedByNormalizedNameOrCode() {
        let now = Date()
        let semester = Semester(name: "S1", order: 1, startDate: now, endDate: now.addingTimeInterval(86_400))
        let existing = Course(name: "Business Law", code: "LAW101", semester: semester)
        let sameName = Course(name: " business law ", code: "LAW102", semester: semester)
        let sameCode = Course(name: "Legal Methods", code: "law101", semester: semester)

        #expect(hasDuplicate(candidate: sameName, in: semester, courses: [existing]))
        #expect(hasDuplicate(candidate: sameCode, in: semester, courses: [existing]))
    }

    @Test func chapterOrderCanBeReassignedWithoutChangingIdentity() {
        let course = Course(name: "Math", code: "MAT")
        let first = Chapter(number: 1, title: "Linear Algebra", order: 1, course: course)
        let second = Chapter(number: 2, title: "Optimization", order: 2, course: course)
        let ids = [first.id, second.id]

        let reordered = [second, first]
        for (index, chapter) in reordered.enumerated() {
            chapter.order = index + 1
            chapter.number = index + 1
        }

        #expect(reordered.map(\.id).sorted { $0.uuidString < $1.uuidString } == ids.sorted { $0.uuidString < $1.uuidString })
        #expect(second.order == 1)
        #expect(first.order == 2)
    }

    @Test func sessionCreatedFromChapterKeepsCourseChapterAndType() throws {
        let course = Course(name: "Computing Foundations", code: "CS100")
        let chapter = Chapter(number: 1, title: "Control Flow", order: 1, course: course)
        let start = Date()
        let session = ClassSession(number: 1, title: "Lab", date: start, startTime: start, endTime: start.addingTimeInterval(3600), sessionType: .lab, course: course, chapter: chapter)

        try AcademicValidationService.validateSession(startTime: session.startTime, endTime: session.endTime, course: course, chapter: chapter)
        #expect(session.course === course)
        #expect(session.chapter === chapter)
        #expect(session.sessionType == .lab)
    }

    @Test func courseNextSessionUsesNearestFutureSession() {
        let now = Date()
        let course = Course(name: "Microeconomics", code: "ECO")
        let later = ClassSession(number: 2, title: "Later", date: now, startTime: now.addingTimeInterval(7200), endTime: now.addingTimeInterval(9000), course: course)
        let next = ClassSession(number: 1, title: "Next", date: now, startTime: now.addingTimeInterval(1800), endTime: now.addingTimeInterval(3600), course: course)
        let past = ClassSession(number: 0, title: "Past", date: now, startTime: now.addingTimeInterval(-7200), endTime: now.addingTimeInterval(-3600), course: course)

        let resolved = [later, past, next].filter { $0.startTime >= now }.sorted { $0.startTime < $1.startTime }.first
        #expect(resolved?.title == "Next")
    }

    @Test func demoWorkspaceHasExpandedCourseStructure() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        DemoWorkspaceService.loadDemoWorkspace(in: context)

        let courses = try context.fetch(FetchDescriptor<Course>())
        let sessions = try context.fetch(FetchDescriptor<ClassSession>())

        #expect(courses.count == 5)
        #expect(courses.allSatisfy { $0.chapters.count >= 3 })
        #expect(sessions.contains { $0.sessionType == .lab })
        #expect(sessions.contains { $0.startTime < Date() })
        #expect(sessions.contains { $0.startTime > Date() })
    }

    @Test func courseStoresSelectedSymbolAndColor() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Law", code: "LAW", colorIdentifier: CourseColor.orange.rawValue, symbolName: "scalemass.fill")
        context.insert(course)
        try context.save()

        let saved = try #require(try context.fetch(FetchDescriptor<Course>()).first)
        #expect(saved.symbolName == "scalemass.fill")
        #expect(saved.colorIdentifier == CourseColor.orange.rawValue)
    }

    @Test func invalidCourseSymbolFallsBackToDefault() {
        #expect(CourseIconCatalog.sanitizedSymbolName(nil) == CourseIconCatalog.defaultSymbolName)
        #expect(CourseIconCatalog.sanitizedSymbolName("") == CourseIconCatalog.defaultSymbolName)
        #expect(CourseIconCatalog.sanitizedSymbolName("not.a.real.course.icon") == CourseIconCatalog.defaultSymbolName)
        #expect(CourseIconCatalog.sanitizedSymbolName("function") == "function")
    }

    @Test func editingCourseAppearanceDoesNotCreateSecondCourseAndPreservesRelations() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Math", code: "MAT", colorIdentifier: "teal", symbolName: "function")
        let chapter = Chapter(number: 1, title: "Algebra", order: 1, course: course)
        let session = ClassSession(number: 1, title: "Lecture", date: .now, startTime: .now, endTime: .now.addingTimeInterval(3600), course: course, chapter: chapter)
        context.insert(course)
        context.insert(chapter)
        context.insert(session)
        try context.save()

        course.name = "Mathematics I"
        course.colorIdentifier = CourseColor.rose.rawValue
        course.symbolName = "sum"
        try context.save()

        let saved = try context.fetch(FetchDescriptor<Course>())
        #expect(saved.count == 1)
        #expect(saved.first?.name == "Mathematics I")
        #expect(saved.first?.symbolName == "sum")
        #expect(saved.first?.colorIdentifier == CourseColor.rose.rawValue)
        #expect(saved.first?.chapters.count == 1)
        #expect(saved.first?.sessions.count == 1)
    }

    @Test func courseIconCatalogHasNoDuplicateSymbolsAndSupportsSearch() {
        let symbols = CourseIconCatalog.icons.map(\.symbolName)
        #expect(Set(symbols).count == symbols.count)
        #expect(CourseIconCatalog.icons.count >= 100)
        #expect(CourseIconCatalog.icons.contains { CourseIconCatalog.matches($0, query: "math") })
        #expect(CourseIconCatalog.icons.contains { CourseIconCatalog.matches($0, query: "law") })
        #expect(CourseIconCatalog.icons.contains { CourseIconCatalog.matches($0, query: "code") })
    }

    @Test func academicFileStoreCopiesAndDeletesOnlyTargetFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "UniSaverFileStore-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = FileManager.default.temporaryDirectory.appending(path: "source-\(UUID().uuidString).pdf")
        let unrelatedName = "keep-\(UUID().uuidString).pdf"
        let unrelated = root.appending(path: unrelatedName)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: source, options: .atomic)
        try Data("keep".utf8).write(to: unrelated, options: .atomic)

        let store = AcademicFileStore(rootDirectory: root)
        let stored = try store.importFile(from: source)
        #expect(stored.originalFileName == source.lastPathComponent)
        #expect(stored.resourceKind == .pdf)
        #expect(!stored.contentHash.isEmpty)
        #expect(try store.url(for: stored.storedRelativePath).lastPathComponent == stored.storedRelativePath)

        try store.delete(relativePath: stored.storedRelativePath)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: source)
    }

    @Test func noteRecordingKeepsAcademicContextAndPersists() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Microeconomics", code: "ECO")
        let chapter = Chapter(number: 1, title: "Elasticity", order: 1, course: course)
        let start = Date()
        let session = ClassSession(number: 1, title: "Lecture", date: start, startTime: start, endTime: start.addingTimeInterval(3600), course: course, chapter: chapter)
        let note = StudyNote(title: "Lecture notes", body: "Initial notes", course: course, chapter: chapter, session: session)
        let recording = CourseRecording(title: "Lecture recording", storedRelativePath: "recording.m4a", duration: 120, course: course, chapter: chapter, session: session, note: note)
        context.insert(course)
        context.insert(chapter)
        context.insert(session)
        context.insert(note)
        context.insert(recording)
        try context.save()

        let saved = try #require(try context.fetch(FetchDescriptor<CourseRecording>()).first)
        #expect(saved.note?.id == note.id)
        #expect(saved.course?.id == course.id)
        #expect(saved.chapter?.id == chapter.id)
        #expect(saved.session?.id == session.id)
    }

    @Test func demoWorkspaceCreatesContentWorkspaceData() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        DemoWorkspaceService.loadDemoWorkspace(in: context)

        let resources = try context.fetch(FetchDescriptor<AcademicResource>())
        let notes = try context.fetch(FetchDescriptor<StudyNote>())
        let recordings = try context.fetch(FetchDescriptor<CourseRecording>())

        #expect(resources.contains { $0.resourceKind == .pdf && !$0.storedRelativePath.isEmpty })
        #expect(notes.count >= 2)
        #expect(recordings.contains { $0.duration > 0 })
    }

    @Test func resourceImportValidationReturnsExplicitErrors() {
        let empty = ResourceImportValidation.validate(ResourceImportDraft(fileURL: nil, title: "", resourceDescription: "", course: nil, chapter: nil, session: nil, tags: []))
        #expect(empty.fileError == "Choose a file to import.")
        #expect(empty.titleError == "Enter a title.")
        #expect(empty.courseError == "Choose a course.")
        #expect([empty.fileError, empty.titleError, empty.courseError].compactMap { $0 }.allSatisfy { !$0.contains("%{PROPERTY}@") })

        let course = Course(name: "Law", code: "LAW")
        let otherCourse = Course(name: "Math", code: "MAT")
        let wrongChapter = Chapter(number: 1, title: "Algebra", order: 1, course: otherCourse)
        let validation = ResourceImportValidation.validate(ResourceImportDraft(fileURL: URL(filePath: "/tmp/file.pdf"), title: "Reader", resourceDescription: "", course: course, chapter: wrongChapter, session: nil, tags: []))
        #expect(validation.chapterError == "The selected chapter does not belong to this course.")
    }

    @Test func completeResourceImportDraftHasNoErrors() throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "complete-\(UUID().uuidString).pdf")
        try Data("pdf".utf8).write(to: source, options: .atomic)
        let course = Course(name: "Microeconomics", code: "ECO")
        let draft = ResourceImportDraft(fileURL: source, title: "Elasticity Reader", resourceDescription: "", course: course, chapter: nil, session: nil, tags: ["pdf"])

        #expect(ResourceImportValidation.validate(draft).isValid)
        try? FileManager.default.removeItem(at: source)
    }

    @MainActor
    @Test func resourceImportUsesDraftTitleAndTechnicalNameOnlyForStorage() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let root = FileManager.default.temporaryDirectory.appending(path: "UniSaverImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = FileManager.default.temporaryDirectory.appending(path: "codex agent-\(UUID().uuidString).pdf")
        try Data("same pdf".utf8).write(to: source, options: .atomic)
        let course = Course(name: "Microeconomics", code: "ECO")
        context.insert(course)
        try context.save()

        let draft = ResourceImportDraft(fileURL: source, title: "Price Elasticity Reader", resourceDescription: "", course: course, chapter: nil, session: nil, tags: [])
        let resource = try ResourceImportService.submit(draft: draft, existingResources: [], modelContext: context, fileStore: AcademicFileStore(rootDirectory: root))

        #expect(resource.title == "Price Elasticity Reader")
        #expect(resource.originalFileName == source.lastPathComponent)
        #expect(resource.storedRelativePath != resource.title)
        #expect(resource.storedRelativePath.contains(resource.id.uuidString) == false)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: source)
    }

    @MainActor
    @Test func repeatedResourceImportDetectsDuplicateUnlessUserAllowsCopy() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let root = FileManager.default.temporaryDirectory.appending(path: "UniSaverDuplicate-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = FileManager.default.temporaryDirectory.appending(path: "duplicate-\(UUID().uuidString).pdf")
        try Data("duplicate pdf".utf8).write(to: source, options: .atomic)
        let course = Course(name: "Microeconomics", code: "ECO")
        context.insert(course)
        try context.save()
        let store = AcademicFileStore(rootDirectory: root)
        let draft = ResourceImportDraft(fileURL: source, title: "Reader", resourceDescription: "", course: course, chapter: nil, session: nil, tags: [])

        _ = try ResourceImportService.submit(draft: draft, existingResources: [], modelContext: context, fileStore: store)
        let existing = try context.fetch(FetchDescriptor<AcademicResource>())
        #expect(existing.count == 1)

        do {
            _ = try ResourceImportService.submit(draft: draft, existingResources: existing, modelContext: context, fileStore: store)
            Issue.record("Expected duplicate detection")
        } catch ResourceImportSubmitError.duplicate {
            #expect(true)
        }
        #expect(try context.fetch(FetchDescriptor<AcademicResource>()).count == 1)

        _ = try ResourceImportService.submit(draft: draft, existingResources: existing, modelContext: context, fileStore: store, allowDuplicate: true)
        #expect(try context.fetch(FetchDescriptor<AcademicResource>()).count == 2)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: source)
    }

    @MainActor
    @Test func copyFailureCreatesNoResource() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Microeconomics", code: "ECO")
        context.insert(course)
        try context.save()

        let missingURL = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).pdf")
        let draft = ResourceImportDraft(fileURL: missingURL, title: "Reader", resourceDescription: "", course: course, chapter: nil, session: nil, tags: [])

        do {
            _ = try ResourceImportService.submit(draft: draft, existingResources: [], modelContext: context, fileStore: AcademicFileStore())
            Issue.record("Expected missing source to fail")
        } catch {
            #expect(try context.fetch(FetchDescriptor<AcademicResource>()).isEmpty)
        }
    }

    @Test func plannerPriorityFilterMatchesTodayPriorityTasks() {
        let now = Date()
        let course = Course(name: "Microeconomics", code: "ECO")
        let urgent = AcademicTask(title: "Submit sheet", dueDate: now, priority: .urgent, course: course)
        let high = AcademicTask(title: "Review notes", dueDate: now.addingTimeInterval(3600), priority: .high, course: course)
        let medium = AcademicTask(title: "Read chapter", dueDate: now.addingTimeInterval(7200), priority: .medium, course: course)
        let completedUrgent = AcademicTask(title: "Old task", dueDate: now, priority: .urgent, status: .completed, course: course)

        let result = PlannerTaskQuery.filteredTasks([medium, completedUrgent, urgent, high], filter: .priority, searchText: "", courseID: nil)

        #expect(result.map(\.title).contains("Submit sheet"))
        #expect(result.map(\.title).contains("Review notes"))
        #expect(!result.map(\.title).contains("Read chapter"))
        #expect(!result.map(\.title).contains("Old task"))
    }

    @Test func plannerSortingByPriorityUsesDueDateAsTieBreaker() {
        let now = Date()
        let laterUrgent = AcademicTask(title: "Later urgent", dueDate: now.addingTimeInterval(7200), priority: .urgent)
        let soonerUrgent = AcademicTask(title: "Sooner urgent", dueDate: now.addingTimeInterval(3600), priority: .urgent)
        let high = AcademicTask(title: "High", dueDate: now, priority: .high)

        let sorted = PlannerTaskQuery.sortedTasks([high, laterUrgent, soonerUrgent], sort: .priority)
        #expect(sorted.map(\.title) == ["Sooner urgent", "Later urgent", "High"])
    }

    @MainActor
    @Test func linkedNoteCreationIsIdempotentAndKeepsContext() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let course = Course(name: "Microeconomics", code: "ECO")
        let chapter = Chapter(number: 1, title: "Elasticity", order: 1, course: course)
        let start = Date()
        let session = ClassSession(number: 1, title: "Lecture", date: start, startTime: start, endTime: start.addingTimeInterval(3600), course: course, chapter: chapter)
        let resource = AcademicResource(title: "Reader", resourceKind: .pdf, originalFileName: "reader.pdf", storedRelativePath: "reader.pdf", course: course, chapter: chapter, session: session)
        context.insert(course)
        context.insert(chapter)
        context.insert(session)
        context.insert(resource)
        try context.save()

        let first = try LinkedNoteService.note(for: resource, existingNotes: [], in: context)
        let second = try LinkedNoteService.note(for: resource, existingNotes: try context.fetch(FetchDescriptor<StudyNote>()), in: context)

        #expect(first.id == second.id)
        #expect(try context.fetch(FetchDescriptor<StudyNote>()).count == 1)
        #expect(first.course?.id == course.id)
        #expect(first.chapter?.id == chapter.id)
        #expect(first.session?.id == session.id)
        #expect(first.resource?.id == resource.id)
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration("TestStore", schema: PersistenceController.schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: PersistenceController.schema, configurations: [configuration])
    }

    private func session(_ title: String, course: Course, day: Date, hour: Int) -> ClassSession {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return ClassSession(number: hour, title: title, date: day, startTime: start, endTime: start.addingTimeInterval(3600), course: course)
    }

    private func hasDuplicate(candidate: Course, in semester: Semester, courses: [Course]) -> Bool {
        let normalizedName = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let normalizedCode = candidate.code.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        return courses.contains { existing in
            guard existing.semester === semester else { return false }
            return existing.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == normalizedName
                || (!normalizedCode.isEmpty && existing.code.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == normalizedCode)
        }
    }
}
