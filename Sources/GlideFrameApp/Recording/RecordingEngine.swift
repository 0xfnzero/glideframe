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
        case invalidRegion
        case permissionDenied(String)

        var errorDescription: String? {
            switch self {
            case .targetMissing: "The selected screen or window is no longer available."
            case .invalidRegion: "The selected recording area is no longer valid."
            case .permissionDenied(let permission): "\(permission) permission is required."
            }
        }
    }

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var targets: [CaptureTargetDescriptor] = []
    @Published private(set) var previewImage: CGImage?

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
    private var recordingSize = CGSize.zero

    func requestScreenCaptureAccess() {
        CGRequestScreenCaptureAccess()
    }

    func clearTargets() {
        content = nil
        targets = []
    }

    func refreshTargets() async throws {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            self.content = content
            let displays = content.displays.map {
                let screenName = Self.screen(for: $0.displayID)?.localizedName
                return CaptureTargetDescriptor(
                    id: "display:\($0.displayID)",
                    kind: .display,
                    title: screenName ?? "Display \($0.displayID)",
                    subtitle: "\($0.width) x \($0.height) - ID \($0.displayID)",
                    nativeID: $0.displayID,
                    selectionDisplayID: $0.displayID,
                    selectionFrame: CGRect(x: 0, y: 0, width: $0.width, height: $0.height)
                )
            }
            let windows = content.windows
                .filter { $0.frame.width >= 320 && $0.frame.height >= 180 && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
                .compactMap { window -> CaptureTargetDescriptor? in
                    guard let display = Self.display(containing: window.frame, from: content.displays) else {
                        return nil
                    }
                    let selectionFrame = window.frame.offsetBy(
                        dx: -display.frame.minX,
                        dy: -display.frame.minY
                    )
                    return CaptureTargetDescriptor(
                        id: "window:\(window.windowID)",
                        kind: .window,
                        title: window.title?.isEmpty == false ? window.title! : (window.owningApplication?.applicationName ?? "Window"),
                        subtitle: window.owningApplication?.applicationName ?? "",
                        nativeID: window.windowID,
                        selectionDisplayID: display.displayID,
                        selectionFrame: selectionFrame
                    )
                }
            targets = displays + windows
        } catch {
            clearTargets()
            if Self.isScreenCapturePermissionError(error) {
                throw EngineError.permissionDenied("Screen Recording")
            }
            throw error
        }
    }

    func isScreenCapturePermissionError(_ error: Error) -> Bool {
        if case EngineError.permissionDenied(let permission) = error,
           permission == "Screen Recording" {
            return true
        }
        return Self.isScreenCapturePermissionError(error)
    }

    func start(options: RecordingOptions, packageURL: URL) async throws {
        state = .preparing
        previewImage = nil
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
            if descriptor.kind == .window { configuration.ignoreShadowsSingleWindow = true }

            let sources = packageURL.appending(path: "Sources", directoryHint: .isDirectory)
            let videoURL = sources.appending(path: "screen-\(Int(Date().timeIntervalSince1970)).mov")
            let writer = try CaptureWriter(
                url: videoURL,
                width: selection.width,
                height: selection.height,
                frameRate: options.frameRate,
                includeAudio: options.recordSystemAudio,
                previewHandler: { [weak self] image in
                    Task { @MainActor [weak self] in
                        guard self?.state.isActive == true else { return }
                        self?.previewImage = image
                    }
                }
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
            self.recordingSize = CGSize(width: selection.width, height: selection.height)
            self.startedAt = Date()
            pointerTracker.start(bounds: selection.pointerBounds)
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
            sources.append(.init(kind: .screen, relativePath: "Sources/\(videoURL.lastPathComponent)", duration: duration, width: Int(recordingSize.width), height: Int(recordingSize.height)))
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
        if options.recordMicrophone {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { throw EngineError.permissionDenied("Microphone") }
        }
        if options.recordCamera {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else { throw EngineError.permissionDenied("Camera") }
        }
    }

    private static func isScreenCapturePermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }

    private func makeFilter(
        for target: CaptureTargetDescriptor,
        content: SCShareableContent,
        region: CGRect?
    ) throws -> (filter: SCContentFilter, width: Int, height: Int, sourceRect: CGRect?, pointerBounds: CGRect) {
        switch target.kind {
        case .display, .region:
            guard let display = content.displays.first(where: { $0.displayID == target.nativeID }) else { throw EngineError.targetMissing }
            guard let screen = Self.screen(for: display.displayID) else { throw EngineError.targetMissing }
            let ownApplications = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            let displaySize = CGSize(width: display.width, height: display.height)
            let sourceRect = region.flatMap {
                CaptureRegionGeometry.normalizedSourceRect($0, displaySize: displaySize)
            }
            if region != nil, sourceRect == nil { throw EngineError.invalidRegion }

            let sourceSize = sourceRect?.size ?? displaySize
            let outputSize = CaptureRegionGeometry.outputSize(
                for: sourceSize,
                scale: screen.backingScaleFactor
            )
            let pointerBounds = sourceRect.map {
                CaptureRegionGeometry.appKitScreenRect(sourceRect: $0, screenFrame: screen.frame)
            } ?? screen.frame
            return (
                filter,
                Int(outputSize.width),
                Int(outputSize.height),
                sourceRect,
                pointerBounds
            )
        case .window:
            guard let window = content.windows.first(where: { $0.windowID == target.nativeID }) else { throw EngineError.targetMissing }
            guard let screen = Self.screen(for: target.selectionDisplayID) else { throw EngineError.targetMissing }
            let sourceRect = region.flatMap {
                CaptureRegionGeometry.sourceRect($0, relativeTo: target.selectionFrame)
            }
            if region != nil, sourceRect == nil { throw EngineError.invalidRegion }

            let sourceSize = sourceRect?.size ?? window.frame.size
            let outputSize = CaptureRegionGeometry.outputSize(
                for: sourceSize,
                scale: screen.backingScaleFactor
            )
            let pointerBounds = CaptureRegionGeometry.appKitScreenRect(
                sourceRect: region ?? target.selectionFrame,
                screenFrame: screen.frame
            )
            return (
                SCContentFilter(desktopIndependentWindow: window),
                Int(outputSize.width),
                Int(outputSize.height),
                sourceRect,
                pointerBounds
            )
        }
    }

    private static func display(containing frame: CGRect, from displays: [SCDisplay]) -> SCDisplay? {
        displays.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        }.flatMap { $0.frame.intersection(frame).area > 0 ? $0 : nil }
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == displayID
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
        previewImage = nil
        startedAt = nil
        microphoneURL = nil
        cameraURL = nil
        videoURL = nil
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}

private extension Int {
    var roundedToEven: Int { self & ~1 }
}
