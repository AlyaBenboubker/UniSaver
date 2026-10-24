import Foundation

#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
#endif

enum UniSaverAccountStatus: Equatable {
    case signedOut
    case restoring
    case signedIn(UniSaverAccount)
    case unavailable(String)
    case error(String)
}

struct UniSaverAccount: Codable, Equatable, Identifiable {
    var id: String
    var stableUserID: String
    var firstName: String
    var email: String
    var avatarURL: URL?
}

enum UniSaverSyncState: String, Codable, CaseIterable, Identifiable {
    case synced = "Synced"
    case syncing = "Syncing"
    case offline = "Offline"
    case needsAttention = "Needs attention"

    var id: String { rawValue }
}

enum AccountSyncError: LocalizedError {
    case sdkUnavailable
    case missingFirebaseConfiguration
    case missingPresentingWindow
    case signedOut
    case invalidRecord(String)
    case syncOperation(String, String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            "FirebaseAuth, FirebaseFirestore, FirebaseStorage and GoogleSignIn are not linked. Add the official Swift packages and GoogleService-Info.plist to enable production sign-in."
        case .missingFirebaseConfiguration:
            "GoogleService-Info.plist is missing or Firebase could not be configured for this bundle."
        case .missingPresentingWindow:
            "UniSaver could not find an active window to present Google sign-in."
        case .signedOut:
            "Sign in before syncing account data."
        case .syncOperation(let operation, let detail):
            "Could not \(operation): \(detail)"
        case .invalidRecord(let detail):
            "A sync record could not be encoded: \(detail)"
        }
    }
}

enum AccountSyncCapability {
    static let backendChoice = "Firebase Authentication + Cloud Firestore + Cloud Storage"
    static let requiredPackages = "FirebaseCore, FirebaseAuth, FirebaseFirestore, FirebaseStorage and GoogleSignIn"
    static let configurationMessage = "Add Firebase and GoogleSignIn Swift packages, GoogleService-Info.plist, the reversed client ID URL scheme and Keychain Sharing to enable Google sign-in and private per-account sync."
}

struct AccountSyncSummary: Equatable {
    var state: UniSaverSyncState
    var uploadedCourses: Int
    var uploadedTasks: Int
    var uploadedWorkSessions: Int
    var uploadedAttachments: Int
    var downloadedCourses: Int
    var downloadedTasks: Int
    var downloadedWorkSessions: Int
    var conflicts: Int
    var message: String

    static let notConfigured = AccountSyncSummary(
        state: .needsAttention,
        uploadedCourses: 0,
        uploadedTasks: 0,
        uploadedWorkSessions: 0,
        uploadedAttachments: 0,
        downloadedCourses: 0,
        downloadedTasks: 0,
        downloadedWorkSessions: 0,
        conflicts: 0,
        message: AccountSyncCapability.configurationMessage
    )
}

struct AccountSyncService {
    private let fileStore = AcademicFileStore()

    /// Read-only identity boundary for local agent context. No credentials or tokens leave Auth.
    func conversationAccountID() -> String {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
        guard (try? configureFirebaseIfNeeded()) != nil else { return "local-signed-out" }
        return Auth.auth().currentUser?.uid ?? "local-signed-out"
        #else
        return "local-signed-out"
        #endif
    }

    @MainActor
    func observeConversationAccount() -> (() -> Void)? {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
        guard (try? configureFirebaseIfNeeded()) != nil else { return nil }
        let handle = Auth.auth().addStateDidChangeListener { _, user in
            let id = user?.uid ?? "local-signed-out"
            Task { @MainActor in
                NotificationCenter.default.post(name: .uniSaverConversationAccountChanged, object: id)
            }
        }
        return { Auth.auth().removeStateDidChangeListener(handle) }
        #else
        return nil
        #endif
    }

    func restoreSession() async -> UniSaverAccountStatus {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
        do {
            try configureFirebaseIfNeeded()
            guard let user = Auth.auth().currentUser else {
                return .signedOut
            }
            return .signedIn(account(from: user))
        } catch {
            return .unavailable(error.localizedDescription)
        }
        #else
        return .unavailable(AccountSyncCapability.configurationMessage)
        #endif
    }

    @MainActor
    func signInWithGoogle() async -> UniSaverAccountStatus {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
        do {
            try configureFirebaseIfNeeded()
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw AccountSyncError.missingFirebaseConfiguration
            }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

            #if os(macOS)
            guard let presentingWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first(where: { $0.isVisible }) else {
                throw AccountSyncError.missingPresentingWindow
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingWindow)
            #elseif canImport(UIKit)
            guard let rootViewController = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first?.rootViewController else {
                throw AccountSyncError.missingPresentingWindow
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            #else
            throw AccountSyncError.missingPresentingWindow
            #endif

            guard let idToken = result.user.idToken?.tokenString else {
                throw AccountSyncError.missingFirebaseConfiguration
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            return .signedIn(account(from: authResult.user))
        } catch {
            return .error(error.localizedDescription)
        }
        #else
        return .unavailable(AccountSyncCapability.configurationMessage)
        #endif
    }

    @MainActor
    func signInWithEmail(_ email: String, password: String, createAccount: Bool) async -> UniSaverAccountStatus {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
        do {
            try configureFirebaseIfNeeded()
            let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: AuthDataResult
            if createAccount {
                result = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
            } else {
                result = try await Auth.auth().signIn(withEmail: normalizedEmail, password: password)
            }
            return .signedIn(account(from: result.user))
        } catch {
            return .error(error.localizedDescription)
        }
        #else
        return .unavailable(AccountSyncCapability.configurationMessage)
        #endif
    }

    @MainActor
    func resetPassword(email: String) async throws {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
        try configureFirebaseIfNeeded()
        try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
        #else
        throw AccountSyncError.sdkUnavailable
        #endif
    }

    func signOut() async -> UniSaverAccountStatus {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
        do {
            try configureFirebaseIfNeeded()
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
            return .signedOut
        } catch {
            return .error(error.localizedDescription)
        }
        #else
        return .signedOut
        #endif
    }

    func syncFirstSlice(
        courses: [Course],
        tasks: [AcademicTask],
        taskLedger: TaskExecutionLedger
    ) async throws -> AccountSyncSummary {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
        try configureFirebaseIfNeeded()
        guard let user = Auth.auth().currentUser else {
            throw AccountSyncError.signedOut
        }

        let database = Firestore.firestore(database: "unisaver")
        let storage = Storage.storage()
        let root = database.collection("users").document(user.uid)
        let deviceID = AccountSyncDevice.identity

        try await syncOperation("save your account profile") {
            try await root.setData([
            "userId": user.uid,
            "email": user.email ?? "",
            "displayName": user.displayName ?? "",
            "lastSeenAt": FieldValue.serverTimestamp(),
            "schemaVersion": 1
            ], merge: true)
        }

        var uploadedCourses = 0
        var uploadedTasks = 0
        var uploadedSessions = 0
        var uploadedAttachments = 0

        for record in courses.map({ SyncedCourseRecord(course: $0, userID: user.uid, deviceID: deviceID) }) {
            try await setRecord(record, id: record.id, in: root.collection("courses"))
            uploadedCourses += 1
        }

        for record in tasks.map({ SyncedTaskRecord(task: $0, userID: user.uid, deviceID: deviceID) }) {
            try await setRecord(record, id: record.id, in: root.collection("tasks"))
            uploadedTasks += 1
        }

        for record in taskLedger.records {
            let syncedRecord = SyncedWorkSessionRecord(record: record, userID: user.uid, deviceID: deviceID)
            try await setRecord(syncedRecord, id: syncedRecord.id, in: root.collection("workSessions"))
            uploadedSessions += 1

            for attachment in record.attachments where attachment.storedRelativePath != nil {
                let metadata = try await uploadAttachment(
                    attachment,
                    sessionID: record.id.uuidString,
                    userID: user.uid,
                    storage: storage
                )
                try await setRecord(metadata, id: metadata.id, in: root.collection("evidenceAttachments"))
                uploadedAttachments += 1
            }
        }

        let remoteCourseCount = try await syncOperation("read synced courses") {
            try await root.collection("courses").getDocuments().documents.count
        }
        let remoteTaskCount = try await syncOperation("read synced tasks") {
            try await root.collection("tasks").getDocuments().documents.count
        }
        let remoteSessionCount = try await syncOperation("read synced work sessions") {
            try await root.collection("workSessions").getDocuments().documents.count
        }

        return AccountSyncSummary(
            state: .synced,
            uploadedCourses: uploadedCourses,
            uploadedTasks: uploadedTasks,
            uploadedWorkSessions: uploadedSessions,
            uploadedAttachments: uploadedAttachments,
            downloadedCourses: max(0, remoteCourseCount - uploadedCourses),
            downloadedTasks: max(0, remoteTaskCount - uploadedTasks),
            downloadedWorkSessions: max(0, remoteSessionCount - uploadedSessions),
            conflicts: 0,
            message: "Synced \(uploadedCourses) courses, \(uploadedTasks) tasks, \(uploadedSessions) completed work sessions and \(uploadedAttachments) supporting files for \(user.email ?? "this account")."
        )
        #else
        throw AccountSyncError.sdkUnavailable
        #endif
    }

    static func handleOpenURL(_ url: URL) -> Bool {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage) && canImport(GoogleSignIn)
    private func configureFirebaseIfNeeded() throws {
        guard FirebaseApp.app() == nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            throw AccountSyncError.missingFirebaseConfiguration
        }
        FirebaseApp.configure()
    }

    private func account(from user: User) -> UniSaverAccount {
        UniSaverAccount(
            id: user.uid,
            stableUserID: user.uid,
            firstName: user.displayName?.components(separatedBy: .whitespaces).first ?? "Student",
            email: user.email ?? "",
            avatarURL: user.photoURL
        )
    }

    private func ensureUserProfile(for user: User) async throws {
        try await Firestore.firestore(database: "unisaver")
            .collection("users")
            .document(user.uid)
            .setData([
                "userId": user.uid,
                "email": user.email ?? "",
                "displayName": user.displayName ?? "",
                "photoURL": user.photoURL?.absoluteString ?? "",
                "updatedAt": FieldValue.serverTimestamp(),
                "schemaVersion": 1
            ], merge: true)
    }

    private func syncOperation<T>(_ operation: String, action: () async throws -> T) async throws -> T {
        do {
            return try await action()
        } catch {
            throw AccountSyncError.syncOperation(operation, error.localizedDescription)
        }
    }

    private func setRecord<T: Encodable>(_ record: T, id: String, in collection: CollectionReference) async throws {
        let payload = try Self.firestorePayload(from: record)
        try await syncOperation("save \(collection.collectionID) records") {
            try await collection.document(id).setData(payload, merge: true)
        }
    }

    private func uploadAttachment(
        _ attachment: WorkEvidenceAttachment,
        sessionID: String,
        userID: String,
        storage: Storage
    ) async throws -> SyncedEvidenceAttachmentRecord {
        guard let relativePath = attachment.storedRelativePath else {
            throw AccountSyncError.invalidRecord("Attachment \(attachment.displayName) has no stored file path.")
        }
        let fileURL = try fileStore.url(for: relativePath)
        let remotePath = "users/\(userID)/evidence/\(sessionID)/\(attachment.id.uuidString)-\(fileURL.lastPathComponent)"
        let metadata = StorageMetadata()
        metadata.contentType = attachment.mimeType
        _ = try await syncOperation("upload a supporting file to Cloud Storage") {
            try await storage.reference(withPath: remotePath).putFileAsync(from: fileURL, metadata: metadata)
        }
        return SyncedEvidenceAttachmentRecord(
            attachment: attachment,
            sessionID: sessionID,
            userID: userID,
            deviceID: AccountSyncDevice.identity,
            storagePath: remotePath
        )
    }

    private static func firestorePayload<T: Encodable>(from record: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AccountSyncError.invalidRecord(String(describing: T.self))
        }
        return payload
    }
    #endif
}

private enum AccountSyncDevice {
    static var identity: String {
        let key = "universalSyncDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

private struct SyncedCourseRecord: Codable {
    var id: String
    var userID: String
    var deviceID: String
    var name: String
    var code: String
    var courseDescription: String
    var professorName: String
    var professorEmail: String?
    var defaultRoom: String?
    var colorIdentifier: String
    var symbolName: String?
    var credits: Double?
    var evaluationMethod: String?
    var startDate: Date?
    var endDate: Date?
    var status: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date
    var schemaVersion = 1

    init(course: Course, userID: String, deviceID: String) {
        id = course.id.uuidString
        self.userID = userID
        self.deviceID = deviceID
        name = course.name
        code = course.code
        courseDescription = course.courseDescription
        professorName = course.professorName
        professorEmail = course.professorEmail
        defaultRoom = course.defaultRoom
        colorIdentifier = course.colorIdentifier
        symbolName = course.symbolName
        credits = course.credits
        evaluationMethod = course.evaluationMethod
        startDate = course.startDate
        endDate = course.endDate
        status = course.status.rawValue
        isArchived = course.isArchived
        createdAt = course.createdAt
        updatedAt = course.updatedAt
        syncedAt = .now
    }
}

private struct SyncedTaskRecord: Codable {
    var id: String
    var userID: String
    var deviceID: String
    var title: String
    var taskDescription: String
    var dueDate: Date
    var priority: String
    var status: String
    var estimatedDuration: TimeInterval
    var courseID: String?
    var chapterID: String?
    var sessionID: String?
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date
    var schemaVersion = 1

    init(task: AcademicTask, userID: String, deviceID: String) {
        id = task.id.uuidString
        self.userID = userID
        self.deviceID = deviceID
        title = task.title
        taskDescription = task.taskDescription
        dueDate = task.dueDate
        priority = task.priority.rawValue
        status = task.status.rawValue
        estimatedDuration = task.estimatedDuration
        courseID = task.course?.id.uuidString
        chapterID = task.chapter?.id.uuidString
        sessionID = task.session?.id.uuidString
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        syncedAt = .now
    }
}

private struct SyncedWorkSessionRecord: Codable {
    var id: String
    var userID: String
    var deviceID: String
    var taskID: String
    var courseID: String?
    var startedAt: Date
    var endedAt: Date
    var recordedSeconds: TimeInterval?
    var completedSubtaskTitles: [String]
    var finishedTask: Bool
    var proofLevel: String
    var blocker: String?
    var note: String
    var attachmentIDs: [String]
    var syncedAt: Date
    var schemaVersion = 1

    init(record: TaskExecutionRecord, userID: String, deviceID: String) {
        id = record.id.uuidString
        self.userID = userID
        self.deviceID = deviceID
        taskID = record.taskID.uuidString
        courseID = record.courseID?.uuidString
        startedAt = record.startedAt
        endedAt = record.endedAt
        recordedSeconds = record.recordedSeconds
        completedSubtaskTitles = record.completedSubtaskTitles
        finishedTask = record.finishedTask
        proofLevel = record.proofLevel.rawValue
        blocker = record.blocker?.rawValue
        note = record.note
        attachmentIDs = record.attachments.map { $0.id.uuidString }
        syncedAt = .now
    }
}

private struct SyncedEvidenceAttachmentRecord: Codable {
    var id: String
    var userID: String
    var deviceID: String
    var sessionID: String
    var kind: String
    var displayName: String
    var mimeType: String?
    var urlString: String?
    var note: String
    var fileSize: Int64?
    var contentHash: String?
    var uploadState: String
    var storagePath: String?
    var createdAt: Date
    var syncedAt: Date
    var schemaVersion = 1

    init(
        attachment: WorkEvidenceAttachment,
        sessionID: String,
        userID: String,
        deviceID: String,
        storagePath: String?
    ) {
        id = attachment.id.uuidString
        self.userID = userID
        self.deviceID = deviceID
        self.sessionID = sessionID
        kind = attachment.kind.rawValue
        displayName = attachment.displayName
        mimeType = attachment.mimeType
        urlString = attachment.urlString
        note = attachment.note
        fileSize = attachment.fileSize
        contentHash = attachment.contentHash
        uploadState = storagePath == nil ? attachment.uploadState.rawValue : WorkEvidenceUploadState.uploaded.rawValue
        self.storagePath = storagePath
        createdAt = attachment.createdAt
        syncedAt = .now
    }
}

extension Notification.Name {
    static let uniSaverConversationAccountChanged = Notification.Name("UniSaverConversationAccountChanged")
}
