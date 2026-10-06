import AVFoundation
import Foundation
import Observation

enum RecordingRuntimeState {
    case idle
    case requestingPermission
    case preparing
    case recording
    case paused
    case stopping
    case saved(SavedAcademicRecording)
    case denied(String)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .recording, .paused, .requestingPermission, .preparing, .stopping:
            true
        case .idle, .saved, .denied, .failed:
            false
        }
    }
}

protocol MicrophonePermissionChecking {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess(_ completion: @escaping (Bool) -> Void)
}

struct SystemMicrophonePermissionChecker: MicrophonePermissionChecking {
    func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }
}

@Observable
@MainActor
final class CourseAudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var preparedRecording: PreparedAcademicRecording?
    private var startedAt: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var startInFlight = false
    private let permissionChecker: MicrophonePermissionChecking
    private let fileStore: AcademicFileStore

    private(set) var state: RecordingRuntimeState = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = -60

    convenience override init() {
        self.init(permissionChecker: SystemMicrophonePermissionChecker(), fileStore: AcademicFileStore())
    }

    init(permissionChecker: MicrophonePermissionChecking, fileStore: AcademicFileStore) {
        self.permissionChecker = permissionChecker
        self.fileStore = fileStore
        super.init()
    }

    func requestPermissionAndStart(title: String) {
        guard !startInFlight, !state.isActive else { return }
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            state = .failed("Microphone permission is not configured for this build. Add NSMicrophoneUsageDescription before recording.")
            return
        }
        startInFlight = true
        state = .requestingPermission

        switch permissionChecker.authorizationStatus() {
        case .authorized:
            prepareAndStart(title: title)
        case .notDetermined:
            permissionChecker.requestAccess { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.prepareAndStart(title: title)
                    } else {
                        self.startInFlight = false
                        self.state = .denied("Microphone access was denied. Enable microphone access in Settings, then try again.")
                    }
                }
            }
        case .denied, .restricted:
            startInFlight = false
            state = .denied("Microphone access is disabled for UniSaver. Enable microphone access in Settings, then try again.")
        @unknown default:
            startInFlight = false
            state = .failed("Microphone access is unavailable on this device.")
        }
    }

    func pause() {
        guard case .recording = state else { return }
        recorder?.pause()
        accumulatedDuration += Date().timeIntervalSince(startedAt ?? .now)
        startedAt = nil
        elapsed = accumulatedDuration
        state = .paused
    }

    func resume() {
        guard case .paused = state else { return }
        guard recorder?.record() == true else {
            state = .failed("The recorder could not resume.")
            return
        }
        startedAt = .now
        state = .recording
    }

    func stop() {
        switch state {
        case .recording, .paused:
            break
        default:
            return
        }
        guard let recorder, let preparedRecording else {
            state = .failed("No active recording was available to stop.")
            return
        }
        state = .stopping
        if startedAt != nil {
            accumulatedDuration += Date().timeIntervalSince(startedAt ?? .now)
        }
        recorder.stop()
        self.recorder = nil
        startedAt = nil
        elapsed = accumulatedDuration
        deactivateAudioSession()

        do {
            let saved = try fileStore.savedRecording(from: preparedRecording, duration: accumulatedDuration)
            state = .saved(saved)
        } catch {
            try? fileStore.delete(relativePath: preparedRecording.storedRelativePath)
            state = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        recorder?.stop()
        if let preparedRecording {
            try? fileStore.delete(relativePath: preparedRecording.storedRelativePath)
        }
        recorder = nil
        preparedRecording = nil
        startedAt = nil
        accumulatedDuration = 0
        elapsed = 0
        level = -60
        startInFlight = false
        deactivateAudioSession()
        state = .idle
    }

    func resetAfterSave() {
        recorder = nil
        preparedRecording = nil
        startedAt = nil
        accumulatedDuration = 0
        elapsed = 0
        level = -60
        startInFlight = false
        state = .idle
    }

    func tick() {
        guard case .recording = state else { return }
        recorder?.updateMeters()
        level = recorder?.averagePower(forChannel: 0) ?? -60
        elapsed = accumulatedDuration + Date().timeIntervalSince(startedAt ?? .now)
    }

    private func prepareAndStart(title: String) {
        state = .preparing
        do {
            try configureAudioSession()
            let prepared = try fileStore.prepareRecordingDestination(originalTitle: title)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: prepared.url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else {
                try? fileStore.delete(relativePath: prepared.storedRelativePath)
                startInFlight = false
                state = .failed("The microphone could not start recording.")
                return
            }
            self.recorder = recorder
            preparedRecording = prepared
            startedAt = .now
            accumulatedDuration = 0
            elapsed = 0
            level = -60
            startInFlight = false
            state = .recording
        } catch {
            startInFlight = false
            state = .failed("Recording could not start: \(error.localizedDescription)")
        }
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

struct AudioPlaybackController {
    private var player: AVAudioPlayer?

    var duration: TimeInterval {
        player?.duration ?? 0
    }

    var currentTime: TimeInterval {
        get { player?.currentTime ?? 0 }
        set { player?.currentTime = newValue }
    }

    mutating func load(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
    }

    mutating func play(rate: Float) {
        player?.enableRate = true
        player?.rate = rate
        player?.play()
    }

    mutating func pause() {
        player?.pause()
    }
}
