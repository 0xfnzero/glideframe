@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
import GlideFrameKit

@MainActor
final class RecordingEngine: NSObject, ObservableObject, SCStreamDelegate {
    enum EngineError: LocalizedError {
        case targetMissing
        case permissionDenied(String)

        var errorDescription: String? {
            switch self {
            case .targetMissing: "The selected screen or window is no longer available."
            case .permissionDenied(let permission): "\(permission) permission is required."
            }
        }
    }

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var targets: [CaptureTargetDescriptor] = []

    private var content: SCShareableContent?
    private var stream: SCStream?
    private var writer: CaptureWriter?
    private let pointerTracker = PointerTracker()
    private let microphoneRecorder = MicrophoneRecorder()
    private let cameraRecorder = CameraRecorder()
    private var microphoneURL: URL?
    private var cameraURL: URL?
    private var videoURL: URL?
    private var startedAt: Date?
    private var recordingBounds = CGRect.zero

    func refreshTargets() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        self.content = content
        let displays = content.displays.map {
            CaptureTargetDescriptor(
                id: "display:\($0.displayID)",
                kind: .display,
                title: "Display \($0.displayID)",
                subtitle: "\($0.width) x \($0.height)",
                nativeID: $0.displayID
            )
        }
        let windows = content.windows
            .filter { $0.frame.width >= 320 && $0.frame.height >= 180 && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map {
                CaptureTargetDescriptor(
                    id: "window:\($0.windowID)",
                    kind: .window,
                    title: $0.title?.isEmpty == false ? $0.title! : ($0.owningApplication?.applicationName ?? "Window"),
                    subtitle: $0.owningApplication?.applicationName ?? "",
                    nativeID: $0.windowID
                )
            }
        targets = displays + windows
    }

    func start(options: RecordingOptions, packageURL: URL) async throws {
        state = .preparing
        do {
            try await validatePermissions(options: options)
            if content == nil { try await refreshTargets() }
            guard let descriptor = targets.first(where: { $0.id == options.targetID }), let content else {
                throw EngineError.targetMissing
            }

            for remaining in stride(from: options.countdown, through: 1, by: -1) {
                state = .countdown(remaining)
                try await Task.sleep(for: .seconds(1))
            }

            let selection = try makeFilter(for: descriptor, content: content, region: options.region)
            let configuration = SCStreamConfiguration()
            configuration.width = selection.width
            configuration.height = selection.height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
            configuration.queueDepth = 6
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = true
            configuration.capturesAudio = options.recordSystemAudio
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
            if let sourceRect = selection.sourceRect { configuration.sourceRect = sourceRect }

            let sources = packageURL.appending(path: "Sources", directoryHint: .isDirectory)
            let videoURL = sources.appending(path: "screen-\(Int(Date().timeIntervalSince1970)).mov")
            let writer = try CaptureWriter(
                url: videoURL,
                width: selection.width,
                height: selection.height,
                frameRate: options.frameRate,
                includeAudio: options.recordSystemAudio
            )
            let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: .init(label: "app.glideframe.capture.video", qos: .userInteractive))
            if options.recordSystemAudio {
                try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: .init(label: "app.glideframe.capture.audio", qos: .userInitiated))
            }

            if options.recordMicrophone {
                let url = sources.appending(path: "microphone.m4a")
                try microphoneRecorder.start(url: url)
                microphoneURL = url
            }
            if options.recordCamera {
                let url = sources.appending(path: "camera.mov")
                try cameraRecorder.start(url: url)
                cameraURL = url
            }

            self.writer = writer
            self.stream = stream
            self.videoURL = videoURL
            self.recordingBounds = selection.bounds
            self.startedAt = Date()
            pointerTracker.start(bounds: selection.bounds)
            try await stream.startCapture()
            state = .recording(startedAt: startedAt!)
        } catch {
            cleanupAfterFailure()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func pause() {
        guard case .recording = state else { return }
        writer?.pause()
        microphoneRecorder.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        writer?.resume()
        microphoneRecorder.resume()
        state = .recording(startedAt: startedAt ?? Date())
    }

    func stop() async throws -> (sources: [MediaSource], events: [PointerEvent], duration: TimeInterval) {
        guard state.isActive, let writer else { throw EngineError.targetMissing }
        state = .finalizing
        pointerTracker.stop()
        microphoneRecorder.stop()
        try await stream?.stopCapture()
        try? await cameraRecorder.stop()
        let duration = try await writer.finish()

        var sources: [MediaSource] = []
        if let videoURL {
            sources.append(.init(kind: .screen, relativePath: "Sources/\(videoURL.lastPathComponent)", duration: duration, width: Int(recordingBounds.width), height: Int(recordingBounds.height)))
        }
        if let microphoneURL {
            sources.append(.init(kind: .microphone, relativePath: "Sources/\(microphoneURL.lastPathComponent)", duration: duration))
        }
        if let cameraURL {
            sources.append(.init(kind: .camera, relativePath: "Sources/\(cameraURL.lastPathComponent)", duration: duration))
        }
        let events = pointerTracker.events.filter { $0.time <= duration }
        cleanup()
        state = .idle
        return (sources, events, duration)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in state = .failed(message) }
    }

    private func validatePermissions(options: RecordingOptions) async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw EngineError.permissionDenied("Screen Recording")
        }
        if options.recordMicrophone {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { throw EngineError.permissionDenied("Microphone") }
        }
        if options.recordCamera {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else { throw EngineError.permissionDenied("Camera") }
        }
    }

    private func makeFilter(
        for target: CaptureTargetDescriptor,
        content: SCShareableContent,
        region: CGRect?
    ) throws -> (filter: SCContentFilter, width: Int, height: Int, sourceRect: CGRect?, bounds: CGRect) {
        switch target.kind {
        case .display, .region:
            guard let display = content.displays.first(where: { $0.displayID == target.nativeID }) else { throw EngineError.targetMissing }
            let ownApplications = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            let rect = region
            let width = Int((rect?.width ?? CGFloat(display.width)).rounded(.down)) & ~1
            let height = Int((rect?.height ?? CGFloat(display.height)).rounded(.down)) & ~1
            return (filter, max(width, 2), max(height, 2), rect, CGRect(x: 0, y: 0, width: display.width, height: display.height))
        case .window:
            guard let window = content.windows.first(where: { $0.windowID == target.nativeID }) else { throw EngineError.targetMissing }
            let width = max(2, Int(window.frame.width * 2).roundedToEven)
            let height = max(2, Int(window.frame.height * 2).roundedToEven)
            return (SCContentFilter(desktopIndependentWindow: window), width, height, nil, window.frame)
        }
    }

    private func cleanupAfterFailure() {
        microphoneRecorder.stop()
        pointerTracker.stop()
        Task { try? await cameraRecorder.stop() }
        cleanup()
    }

    private func cleanup() {
        stream = nil
        writer = nil
        startedAt = nil
        microphoneURL = nil
        cameraURL = nil
        videoURL = nil
    }
}

private extension Int {
    var roundedToEven: Int { self & ~1 }
}
