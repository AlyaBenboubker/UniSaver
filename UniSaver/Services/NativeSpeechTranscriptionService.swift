import AVFoundation
import Foundation
import SwiftData

#if canImport(Speech)
import Speech
#endif

struct SpeechLocaleOption: Identifiable, Hashable {
    let identifier: String
    let displayName: String

    var id: String { identifier }
}

enum NativeSpeechTranscriptionError: LocalizedError {
    case speechFrameworkUnavailable
    case speechPermissionDenied
    case transcriberUnavailable
    case unsupportedLocale(String)
    case audioFileMissing
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .speechFrameworkUnavailable:
            "Apple speech transcription is not available on this OS."
        case .speechPermissionDenied:
            "Speech recognition permission was denied. Enable Speech Recognition for UniSaver in System Settings, then retry."
        case .transcriberUnavailable:
            "SpeechTranscriber is not available on this Mac. Try another Mac, update macOS, or use manual transcription."
        case .unsupportedLocale(let identifier):
            "The selected language (\(identifier)) is not supported by SpeechTranscriber on this Mac."
        case .audioFileMissing:
            "The audio file could not be found."
        case .emptyTranscription:
            "Apple Speech finished, but did not return any text for this audio."
        }
    }
}

@MainActor
struct NativeSpeechTranscriptionService {
    static let preferredLocaleIdentifiers = ["en-US", "fr-FR", "es-ES", "de-DE"]

    func preferredLocaleOptions() async -> [SpeechLocaleOption] {
        #if canImport(Speech)
        if #available(macOS 26.0, iOS 26.0, *) {
            guard Self.hasSpeechUsageDescription else { return [] }
            guard SpeechTranscriber.isAvailable else { return [] }
            var options: [SpeechLocaleOption] = []
            for identifier in Self.preferredLocaleIdentifiers {
                let requested = Locale(identifier: identifier)
                if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
                    options.append(option(for: supported))
                }
            }
            return Array(Set(options)).sorted { $0.displayName < $1.displayName }
        }
        #endif
        return []
    }

    func transcribe(
        recording: CourseRecording,
        in context: ModelContext,
        fileStore: AcademicFileStore,
        languageIdentifier: String,
        partialResult: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws {
        let existingNotes = recording.notes
        let url = try fileStore.url(for: recording.storedRelativePath)
        let text = try await transcribeAudioFile(url: url, localeIdentifier: languageIdentifier) { partial in
            partialResult(partial)
        }
        recording.notes = Self.mergedNotes(existingNotes, transcript: text)
        recording.updatedAt = .now
        try context.save()
    }

    nonisolated static func mergedNotes(_ existingNotes: String?, transcript: String) -> String {
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTranscript.isEmpty else {
            return existingNotes ?? ""
        }

        let startMarker = "Apple Speech Transcript"
        let trimmedExisting = (existingNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptSection = "\(startMarker)\n\(cleanTranscript)"

        guard !trimmedExisting.isEmpty else {
            return transcriptSection
        }

        if let markerRange = trimmedExisting.range(of: startMarker) {
            let prefix = trimmedExisting[..<markerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return prefix.isEmpty ? transcriptSection : "\(prefix)\n\n\(transcriptSection)"
        }

        return "\(trimmedExisting)\n\n\(transcriptSection)"
    }

    func requestSpeechAuthorizationIfNeeded() async throws {
        #if canImport(Speech)
        guard Self.hasSpeechUsageDescription else {
            throw NativeSpeechTranscriptionError.speechPermissionDenied
        }
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let authorized = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            if !authorized {
                throw NativeSpeechTranscriptionError.speechPermissionDenied
            }
        case .denied, .restricted:
            throw NativeSpeechTranscriptionError.speechPermissionDenied
        @unknown default:
            throw NativeSpeechTranscriptionError.speechPermissionDenied
        }
        #else
        throw NativeSpeechTranscriptionError.speechFrameworkUnavailable
        #endif
    }

    private func option(for locale: Locale) -> SpeechLocaleOption {
        let identifier = locale.identifier
        let displayName = Locale.current.localizedString(forIdentifier: identifier) ?? identifier
        return SpeechLocaleOption(identifier: identifier, displayName: displayName)
    }

    static var hasSpeechUsageDescription: Bool {
        guard let message = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String else {
            return false
        }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func transcribeAudioFile(
        url: URL,
        localeIdentifier: String,
        partialResult: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        #if canImport(Speech)
        if #available(macOS 26.0, iOS 26.0, *) {
            try await requestSpeechAuthorizationIfNeeded()
            guard SpeechTranscriber.isAvailable else {
                throw NativeSpeechTranscriptionError.transcriberUnavailable
            }
            let requestedLocale = Locale(identifier: localeIdentifier)
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
                throw NativeSpeechTranscriptionError.unsupportedLocale(localeIdentifier)
            }
            let preset = SpeechTranscriber.Preset.transcription
            let transcriber = SpeechTranscriber(locale: locale, preset: preset)
            if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installationRequest.downloadAndInstall()
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let resultTask = Task { () throws -> String in
                var text = ""
                for try await result in transcriber.results {
                    let phrase = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !phrase.isEmpty else { continue }
                    text = text.isEmpty ? phrase : "\(text)\n\(phrase)"
                    partialResult(text)
                }
                return text
            }

            let audioFile = try AVAudioFile(forReading: url)
            if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let text = try await resultTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw NativeSpeechTranscriptionError.emptyTranscription
            }
            return text
        }
        #endif
        throw NativeSpeechTranscriptionError.speechFrameworkUnavailable
    }
}
