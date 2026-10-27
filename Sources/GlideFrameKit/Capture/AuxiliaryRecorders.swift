@preconcurrency import AVFoundation
import AppKit
import Foundation
import GlideFrameKit

@MainActor
public final class PointerTracker {
    public init() {}

    private var monitor: Any?
    private var startedAt: Date?
    private var bounds = CGRect.zero
    public private(set) var events: [PointerEvent] = []
    private var lastMoveAt: TimeInterval = -1
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0

    public func start(bounds: CGRect) {
        stop()
        self.bounds = bounds
        startedAt = Date()
        events = []
        lastMoveAt = -1
        pausedAt = nil
        pausedDuration = 0
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.capture(event) }
        }
    }

    public func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        startedAt = nil
    }

    public func pause() { if pausedAt == nil { pausedAt = Date() } }
    public func resume() {
        if let pausedAt { pausedDuration += Date().timeIntervalSince(pausedAt) }
        pausedAt = nil
    }

    private func capture(_ event: NSEvent) {
        guard let startedAt, pausedAt == nil, bounds.width > 0, bounds.height > 0 else { return }
        let elapsed = Date().timeIntervalSince(startedAt) - pausedDuration
        let kind: PointerEvent.Kind = event.type == .mouseMoved ? .move : .click
        if kind == .move, elapsed - lastMoveAt < 0.05 { return }
        if kind == .move { lastMoveAt = elapsed }
        let point = NSEvent.mouseLocation
        guard bounds.contains(point) else { return }
        let normalizedX = (point.x - bounds.minX) / bounds.width
        let normalizedY = 1 - ((point.y - bounds.minY) / bounds.height)
        events.append(.init(time: elapsed, x: normalizedX, y: normalizedY, kind: kind))
    }
}

@MainActor
public final class MicrophoneRecorder {
    public init() {}

    private var recorder: AVAudioRecorder?

    public func start(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: url.pathExtension.lowercased() == "wav" ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw NSError(domain: "GlideFrame.Microphone", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone recording could not start."])
        }
        self.recorder = recorder
    }

    public func pause() { recorder?.pause() }
    public func resume() { recorder?.record() }
    public func stop() { recorder?.stop(); recorder = nil }
}

@MainActor
public final class CameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var continuation: CheckedContinuation<Void, Error>?

    public func start(url: URL) throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
            throw NSError(domain: "GlideFrame.Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera is available."])
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw NSError(domain: "GlideFrame.Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Camera recording could not be configured."])
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
        output.startRecording(to: url, recordingDelegate: self)
    }

    public func stop() async throws {
        guard output.isRecording else { session.stopRunning(); return }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            output.stopRecording()
        }
        session.stopRunning()
    }

    public func pause() { if output.isRecording { output.pauseRecording() } }
    public func resume() { if output.isRecordingPaused { output.resumeRecording() } }

    nonisolated public func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if let error { continuation?.resume(throwing: error) }
            else { continuation?.resume() }
            continuation = nil
        }
    }
}
