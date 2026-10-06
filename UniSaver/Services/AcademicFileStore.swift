import AVFoundation
import Foundation
import CryptoKit
import UniformTypeIdentifiers

enum AcademicFileStoreError: LocalizedError, Equatable {
    case sourceUnavailable
    case copyFailed
    case fileMissing
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: "The selected file is not accessible."
        case .copyFailed: "The file could not be copied into UniSaver."
        case .fileMissing: "The stored file is missing."
        case .unsupportedFile: "This file type is not supported yet."
        }
    }
}

struct StoredAcademicFile: Equatable {
    let originalFileName: String
    let storedRelativePath: String
    let mimeType: String
    let fileExtension: String
    let fileSize: Int64
    let resourceKind: AcademicResourceKind
    let contentHash: String
}

struct PreparedAcademicRecording: Equatable {
    let url: URL
    let originalFileName: String
    let storedRelativePath: String
    let mimeType: String
    let fileExtension: String
}

struct SavedAcademicRecording: Equatable {
    let originalFileName: String
    let storedRelativePath: String
    let mimeType: String
    let fileExtension: String
    let fileSize: Int64
    let duration: TimeInterval
}

struct AcademicFileStore {
    private let fileManager: FileManager
    private let rootDirectory: URL

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.rootDirectory = base.appending(path: "UniSaver/Resources", directoryHint: .isDirectory)
        }
    }

    func importFile(from sourceURL: URL) throws -> StoredAcademicFile {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AcademicFileStoreError.sourceUnavailable
        }

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let originalName = sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension.localizedLowercase
        let kind = Self.resourceKind(for: fileExtension)
        let mimeType = Self.mimeType(for: fileExtension)
        let contentHash = try Self.sha256Hex(for: sourceURL)
        let storedName = "\(UUID().uuidString).\(fileExtension.isEmpty ? "resource" : fileExtension)"
        let destinationURL = rootDirectory.appending(path: storedName)

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            let size = try Self.byteSize(for: destinationURL, fileManager: fileManager)
            return StoredAcademicFile(
                originalFileName: originalName,
                storedRelativePath: storedName,
                mimeType: mimeType,
                fileExtension: fileExtension,
                fileSize: size,
                resourceKind: kind,
                contentHash: contentHash
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw AcademicFileStoreError.copyFailed
        }
    }

    func importRecording(from sourceURL: URL) throws -> SavedAcademicRecording {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AcademicFileStoreError.sourceUnavailable
        }

        let fileExtension = sourceURL.pathExtension.localizedLowercase
        guard ["m4a", "mp3", "wav", "aac", "caf"].contains(fileExtension) else {
            throw AcademicFileStoreError.unsupportedFile
        }

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let storedName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = rootDirectory.appending(path: storedName)
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            let size = try fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber
            let duration = (try? AVAudioPlayer(contentsOf: destinationURL).duration) ?? 0
            return SavedAcademicRecording(
                originalFileName: sourceURL.lastPathComponent,
                storedRelativePath: storedName,
                mimeType: Self.mimeType(for: fileExtension),
                fileExtension: fileExtension,
                fileSize: size?.int64Value ?? 0,
                duration: duration
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw AcademicFileStoreError.copyFailed
        }
    }

    func writeDemoFile(named fileName: String, data: Data) throws -> StoredAcademicFile {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let destinationURL = rootDirectory.appending(path: fileName)
        try data.write(to: destinationURL, options: .atomic)
        let size = try Self.byteSize(for: destinationURL, fileManager: fileManager)
        let fileExtension = destinationURL.pathExtension.localizedLowercase
        let contentHash = try Self.sha256Hex(for: destinationURL)
        return StoredAcademicFile(
            originalFileName: fileName,
            storedRelativePath: fileName,
            mimeType: Self.mimeType(for: fileExtension),
            fileExtension: fileExtension,
            fileSize: size,
            resourceKind: Self.resourceKind(for: fileExtension),
            contentHash: contentHash
        )
    }

    func prepareRecordingDestination(originalTitle: String, fileExtension: String = "m4a") throws -> PreparedAcademicRecording {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let sanitizedTitle = originalTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let originalName = "\(sanitizedTitle.isEmpty ? "Course recording" : sanitizedTitle).\(fileExtension)"
        let storedName = "\(UUID().uuidString).\(fileExtension)"
        return PreparedAcademicRecording(
            url: rootDirectory.appending(path: storedName),
            originalFileName: originalName,
            storedRelativePath: storedName,
            mimeType: Self.mimeType(for: fileExtension),
            fileExtension: fileExtension
        )
    }

    func savedRecording(from prepared: PreparedAcademicRecording, duration: TimeInterval) throws -> SavedAcademicRecording {
        guard fileManager.fileExists(atPath: prepared.url.path) else {
            throw AcademicFileStoreError.fileMissing
        }
        let size = try fileManager.attributesOfItem(atPath: prepared.url.path)[.size] as? NSNumber
        guard (size?.int64Value ?? 0) > 0 else {
            try? fileManager.removeItem(at: prepared.url)
            throw AcademicFileStoreError.copyFailed
        }
        return SavedAcademicRecording(
            originalFileName: prepared.originalFileName,
            storedRelativePath: prepared.storedRelativePath,
            mimeType: prepared.mimeType,
            fileExtension: prepared.fileExtension,
            fileSize: size?.int64Value ?? 0,
            duration: duration
        )
    }

    func fingerprint(for sourceURL: URL) throws -> String {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AcademicFileStoreError.sourceUnavailable
        }
        return try Self.sha256Hex(for: sourceURL)
    }

    func url(for relativePath: String) throws -> URL {
        let url = rootDirectory.appending(path: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AcademicFileStoreError.fileMissing
        }
        return url
    }

    func delete(relativePath: String) throws {
        let url = rootDirectory.appending(path: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    static func resourceKind(for fileExtension: String) -> AcademicResourceKind {
        let ext = fileExtension.localizedLowercase
        if ext == "pdf" { return .pdf }
        if ["png", "jpg", "jpeg", "heic", "gif", "tiff"].contains(ext) { return .image }
        if ["m4a", "mp3", "wav", "aac", "caf"].contains(ext) { return .audio }
        if ["mov", "mp4", "m4v"].contains(ext) { return .video }
        if ["numbers", "xlsx", "csv"].contains(ext) { return .spreadsheet }
        if ["doc", "docx", "pages", "rtf", "txt", "md"].contains(ext) { return .document }
        if ["url", "webloc"].contains(ext) { return .link }
        return .other
    }

    static func mimeType(for fileExtension: String) -> String {
        if let type = UTType(filenameExtension: fileExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }

    private static func sha256Hex(for url: URL) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw AcademicFileStoreError.sourceUnavailable
        }
        if isDirectory.boolValue {
            let files = try FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .sorted { $0.path < $1.path }
            var hasher = SHA256()
            for file in files {
                let relativePath = file.path.replacingOccurrences(of: url.path, with: "")
                hasher.update(data: Data(relativePath.utf8))
                var childIsDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: file.path, isDirectory: &childIsDirectory), childIsDirectory.boolValue {
                    hasher.update(data: Data(try sha256Hex(for: file).utf8))
                } else {
                    hasher.update(data: try Data(contentsOf: file))
                }
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func byteSize(for url: URL, fileManager: FileManager) throws -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw AcademicFileStoreError.sourceUnavailable
        }
        if !isDirectory.boolValue {
            let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            return size?.int64Value ?? 0
        }
        let files = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        return try files.reduce(Int64(0)) { total, file in
            total + (try byteSize(for: file, fileManager: fileManager))
        }
    }
}
