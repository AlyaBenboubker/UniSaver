import Foundation

enum MoodleRemoteItemKind: String, Codable {
    case course
    case task
}

struct MoodleRemoteItemRecord: Codable, Hashable {
    var kind: MoodleRemoteItemKind
    var remoteID: String
    var localID: UUID
    var sourceURL: URL
    var title: String
    var lastSeenAt: Date
}

struct MoodleSyncMetadata: Codable {
    var institutionURL: URL?
    var lastSyncAt: Date?
    var siteName: String?
    var userDisplayName: String?
    var accessibleFunctions: [String]
    var records: [MoodleRemoteItemRecord]

    static let empty = MoodleSyncMetadata(
        institutionURL: nil,
        lastSyncAt: nil,
        siteName: nil,
        userDisplayName: nil,
        accessibleFunctions: [],
        records: []
    )
}

struct MoodleSyncMetadataStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.fileURL = base.appending(path: "UniSaver/MoodleSyncMetadata.json")
        }
    }

    func load() -> MoodleSyncMetadata {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let metadata = try? JSONDecoder().decode(MoodleSyncMetadata.self, from: data) else {
            return .empty
        }
        return metadata
    }

    func save(_ metadata: MoodleSyncMetadata) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: fileURL, options: .atomic)
    }

    func clearConnectionStateKeepingImportedData() throws {
        var metadata = load()
        metadata.institutionURL = nil
        metadata.lastSyncAt = nil
        metadata.siteName = nil
        metadata.userDisplayName = nil
        metadata.accessibleFunctions = []
        try save(metadata)
    }

    func localID(kind: MoodleRemoteItemKind, remoteID: String) -> UUID? {
        load().records.first { $0.kind == kind && $0.remoteID == remoteID }?.localID
    }

    func upsertRecord(_ record: MoodleRemoteItemRecord, in metadata: inout MoodleSyncMetadata) {
        if let index = metadata.records.firstIndex(where: { $0.kind == record.kind && $0.remoteID == record.remoteID }) {
            metadata.records[index] = record
        } else {
            metadata.records.append(record)
        }
    }

    func remoteIDs(kind: MoodleRemoteItemKind) -> Set<UUID> {
        Set(load().records.filter { $0.kind == kind }.map(\.localID))
    }

    func sourceURL(for localID: UUID) -> URL? {
        load().records.first { $0.localID == localID }?.sourceURL
    }
}
