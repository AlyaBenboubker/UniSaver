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
            let size = try fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber
            return StoredAcademicFile(
                originalFileName: originalName,
                storedRelativePath: storedName,
                mimeType: mimeType,
                fileExtension: fileExtension,
                fileSize: size?.int64Value ?? 0,
                resourceKind: kind,
                contentHash: contentHash
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
        let size = try fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber
        let fileExtension = destinationURL.pathExtension.localizedLowercase
        let contentHash = try Self.sha256Hex(for: destinationURL)
        return StoredAcademicFile(
            originalFileName: fileName,
            storedRelativePath: fileName,
            mimeType: Self.mimeType(for: fileExtension),
            fileExtension: fileExtension,
            fileSize: size?.int64Value ?? 0,
            resourceKind: Self.resourceKind(for: fileExtension),
            contentHash: contentHash
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
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
