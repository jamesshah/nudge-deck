import AVFoundation
import Foundation

@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    static let maxDuration: TimeInterval = 60

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var recordingURL: URL?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start() async {
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            errorMessage = "Allow microphone access in Settings to record a voice note."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("proof-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record(forDuration: Self.maxDuration)
            self.recorder = recorder
            recordingURL = nil
            elapsed = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard let recorder else { return }
        recorder.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        let url = recorder.url
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > GameFormatting.maxProofBytes {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            elapsed = 0
            errorMessage = GameFormatting.proofFileTooLargeMessage(for: .audio)
            return
        }
        recordingURL = url
    }

    func discard() {
        if isRecording { stop() }
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        elapsed = 0
    }

    private func tick() {
        guard let recorder else { return }
        if recorder.isRecording {
            elapsed = recorder.currentTime
        } else {
            stop()
        }
    }
}

/// Plays a remote voice-note proof.
@MainActor
final class AudioProofPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }
        self.player = player
        player.play()
        isPlaying = true
    }
}
