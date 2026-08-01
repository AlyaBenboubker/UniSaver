import AVFoundation
import Foundation
import Observation

enum RecordingRuntimeState: Equatable {
    case idle
    case recording
    case paused
    case finished(URL, TimeInterval)
    case unavailable(String)
}

@Observable
final class CourseAudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var accumulatedDuration: TimeInterval = 0
    private(set) var state: RecordingRuntimeState = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                DispatchQueue.main.async {
                    if allowed {
                        self?.start()
                    } else {
                        self?.state = .unavailable("Microphone access was denied. Enable it in Settings to record course audio.")
                    }
                }
            }
        case .denied, .restricted:
            state = .unavailable("Microphone access is disabled. Enable it in Settings to record course audio.")
        @unknown default:
            state = .unavailable("Microphone access is unavailable on this device.")
        }
    }

    func start() {
        do {
            try configureAudioSession()
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            guard recorder?.record() == true else {
                state = .unavailable("The microphone could not start recording.")
                return
            }
            startedAt = .now
            accumulatedDuration = 0
            elapsed = 0
            state = .recording
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func pause() {
        guard case .recording = state else { return }
        recorder?.pause()
        accumulatedDuration += Date().timeIntervalSince(startedAt ?? .now)
        startedAt = nil
        state = .paused
    }

    func resume() {
        guard case .paused = state else { return }
        recorder?.record()
        startedAt = .now
        state = .recording
    }

    func stop() {
        guard let recorder else { return }
        if case .recording = state {
            accumulatedDuration += Date().timeIntervalSince(startedAt ?? .now)
        }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        elapsed = accumulatedDuration
        state = .finished(url, accumulatedDuration)
    }

    func cancel() {
        recorder?.stop()
        if let url = recorder?.url {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        state = .idle
        elapsed = 0
        level = 0
    }

    func tick() {
        guard case .recording = state else { return }
        recorder?.updateMeters()
        level = recorder?.averagePower(forChannel: 0) ?? -60
        elapsed = accumulatedDuration + Date().timeIntervalSince(startedAt ?? .now)
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        #endif
    }
}

struct AudioPlaybackController {
    private var player: AVAudioPlayer?

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
