import Foundation
import SwiftData

struct MoodleSyncSummary: Equatable {
    var importedCourseCount: Int
    var importedTaskCount: Int
    var updatedCourseCount: Int
    var updatedTaskCount: Int
    var availableFunctions: [String]
    var lastSyncAt: Date
}

enum MoodleSyncService {
    static func synchronize(
        institutionURL: URL,
        token: String?,
        context: ModelContext,
        metadataStore: MoodleSyncMetadataStore? = nil
    ) async throws -> MoodleSyncSummary {
        let metadataStore = metadataStore ?? MoodleSyncMetadataStore()
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MoodleClientError.missingAuthorizedToken
        }

        let client = try MoodleClient(institutionURL: institutionURL, token: token)
        let siteInfo = try await client.siteInfo()
        let availableFunctions = siteInfo.availableFunctionNames
        guard availableFunctions.contains("core_enrol_get_users_courses") else {
            throw MoodleClientError.connectionUnavailable
        }

        let remoteCourses = try await client.enrolledCourses(for: siteInfo.userid, availableFunctions: availableFunctions)
        let remoteEvents: [MoodleEventDTO]
        if availableFunctions.contains("core_calendar_get_action_events_by_courses") {
            remoteEvents = try await client.actionEvents(courseIDs: remoteCourses.map(\.id), availableFunctions: availableFunctions)
        } else {
            remoteEvents = []
        }

        return try apply(
            remoteCourses: remoteCourses,
            remoteEvents: remoteEvents,
            siteName: siteInfo.sitename,
            userDisplayName: siteInfo.fullname,
            availableFunctions: Array(availableFunctions).sorted(),
            institutionURL: institutionURL,
            context: context,
            metadataStore: metadataStore
        )
    }

    static func apply(
        remoteCourses: [MoodleCourseDTO],
        remoteEvents: [MoodleEventDTO],
        siteName: String?,
        userDisplayName: String?,
        availableFunctions: [String],
        institutionURL: URL,
        context: ModelContext,
        metadataStore: MoodleSyncMetadataStore? = nil
    ) throws -> MoodleSyncSummary {
        let metadataStore = metadataStore ?? MoodleSyncMetadataStore()
        var metadata = metadataStore.load()
        metadata.institutionURL = institutionURL
        metadata.siteName = siteName
        metadata.userDisplayName = userDisplayName
        metadata.accessibleFunctions = availableFunctions
        let existingCourses = try context.fetch(FetchDescriptor<Course>())
        let existingTasks = try context.fetch(FetchDescriptor<AcademicTask>())
        let courseResult = upsertCourses(remoteCourses, existingCourses: existingCourses, institutionURL: institutionURL, metadata: &metadata, context: context)
        let taskResult = upsertTasks(remoteEvents, existingTasks: existingTasks, courses: courseResult.coursesByRemoteID, institutionURL: institutionURL, metadata: &metadata, context: context)

        let now = Date()
        metadata.lastSyncAt = now
        try context.save()
        try metadataStore.save(metadata)

        return MoodleSyncSummary(
            importedCourseCount: courseResult.imported,
            importedTaskCount: taskResult.imported,
            updatedCourseCount: courseResult.updated,
            updatedTaskCount: taskResult.updated,
            availableFunctions: metadata.accessibleFunctions,
            lastSyncAt: now
        )
    }

    private static func upsertCourses(
        _ remoteCourses: [MoodleCourseDTO],
        existingCourses: [Course],
        institutionURL: URL,
        metadata: inout MoodleSyncMetadata,
        context: ModelContext
    ) -> (imported: Int, updated: Int, coursesByRemoteID: [Int: Course]) {
        var imported = 0
        var updated = 0
        var coursesByRemoteID: [Int: Course] = [:]
        let existingByID = Dictionary(uniqueKeysWithValues: existingCourses.map { ($0.id, $0) })

        for remote in remoteCourses {
            let remoteID = String(remote.id)
            let localID = metadata.records.first { $0.kind == .course && $0.remoteID == remoteID }?.localID
            let course = localID.flatMap { existingByID[$0] } ?? Course(
                name: remote.fullname,
                code: remote.shortname ?? "Moodle",
                courseDescription: remote.summary ?? "",
                professorName: "Moodle",
                colorIdentifier: "blueViolet",
                symbolName: "graduationcap"
            )

            if localID == nil {
                imported += 1
                context.insert(course)
            } else {
                updated += 1
            }

            course.name = remote.fullname
            course.code = remote.shortname?.isEmpty == false ? remote.shortname! : "Moodle \(remote.id)"
            course.courseDescription = remote.summary ?? course.courseDescription
            course.professorName = "Moodle"
            course.symbolName = "graduationcap"
            course.updatedAt = .now
            coursesByRemoteID[remote.id] = course

            let sourceURL = remote.viewurl ?? institutionURL.appending(path: "course/view.php").appending(queryItems: [URLQueryItem(name: "id", value: remoteID)])
            metadataStoreUpsert(kind: .course, remoteID: remoteID, localID: course.id, sourceURL: sourceURL, title: remote.fullname, metadata: &metadata)
        }

        return (imported, updated, coursesByRemoteID)
    }

    private static func upsertTasks(
        _ events: [MoodleEventDTO],
        existingTasks: [AcademicTask],
        courses: [Int: Course],
        institutionURL: URL,
        metadata: inout MoodleSyncMetadata,
        context: ModelContext
    ) -> (imported: Int, updated: Int) {
        var imported = 0
        var updated = 0
        let existingByID = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.id, $0) })

        for event in events {
            guard let dueDate = event.timestart.map({ Date(timeIntervalSince1970: TimeInterval($0)) }) else {
                continue
            }
            let remoteID = String(event.id)
            let localID = metadata.records.first { $0.kind == .task && $0.remoteID == remoteID }?.localID
            let task = localID.flatMap { existingByID[$0] } ?? AcademicTask(
                title: event.name,
                taskDescription: event.description ?? "",
                dueDate: dueDate,
                priority: .medium,
                status: .todo,
                course: event.courseid.flatMap { courses[$0] }
            )

            if localID == nil {
                imported += 1
                context.insert(task)
            } else {
                updated += 1
            }

            task.title = event.name
            task.taskDescription = event.description ?? task.taskDescription
            task.dueDate = dueDate
            task.course = event.courseid.flatMap { courses[$0] } ?? task.course
            task.updatedAt = .now

            let sourceURL = event.url ?? institutionURL.appending(path: "calendar/view.php")
            metadataStoreUpsert(kind: .task, remoteID: remoteID, localID: task.id, sourceURL: sourceURL, title: event.name, metadata: &metadata)
        }

        return (imported, updated)
    }

    private static func metadataStoreUpsert(
        kind: MoodleRemoteItemKind,
        remoteID: String,
        localID: UUID,
        sourceURL: URL,
        title: String,
        metadata: inout MoodleSyncMetadata
    ) {
        let record = MoodleRemoteItemRecord(
            kind: kind,
            remoteID: remoteID,
            localID: localID,
            sourceURL: sourceURL,
            title: title,
            lastSeenAt: .now
        )
        if let index = metadata.records.firstIndex(where: { $0.kind == kind && $0.remoteID == remoteID }) {
            metadata.records[index] = record
        } else {
            metadata.records.append(record)
        }
    }
}

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url ?? self
    }
}
