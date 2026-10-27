@preconcurrency import AVFoundation
import AppKit
@preconcurrency import CoreImage
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import GlideFrameKit
import GlideFrameCapture

public struct GlideFrameHelperCommand {
    public static func main() async {
        do {
            try await run()
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            throw HelperError.missingCommand
        }
        switch command {
        case "screen-capture-status":
            try printJSON(CGPreflightScreenCaptureAccess())
        case "request-screen-capture-access":
            try printJSON(CGRequestScreenCaptureAccess())
        case "list-capture-sources":
            try await printJSON(MacCaptureSourceProvider.captureSources())
        case "list-audio-devices":
            try printJSON(MacCaptureSourceProvider.audioDevices())
        case "list-camera-devices":
            try printJSON(MacCaptureSourceProvider.cameraDevices())
        case "record":
            try await record(args: Array(args.dropFirst()))
        case "validate-project":
            let arguments = try HelperArguments(Array(args.dropFirst()))
            let url = URL(filePath: try arguments.value(for: "--project-path"))
            try printJSON(await ProjectRepository().load(at: url))
        case "export-project":
            let arguments = try HelperArguments(Array(args.dropFirst()))
            let url = URL(filePath: try arguments.value(for: "--project-path"))
            let destination = URL(filePath: try arguments.value(for: "--destination"))
            let preset = try arguments.value(for: "--preset")
            var manifest = try await ProjectRepository().load(at: url)
            switch preset {
            case "hd": manifest.exportPreset = .hd
            case "ultraHD": manifest.exportPreset = .ultraHD
            case "source":
                if let screen = manifest.sources.first(where: { $0.kind == .screen }) {
                    manifest.exportPreset.width = screen.width ?? 1920
                    manifest.exportPreset.height = screen.height ?? 1080
                    manifest.canvas.padding = 0
                }
            default: throw HelperError.unsupportedCommand(preset)
            }
            try? FileManager.default.removeItem(at: destination)
            try await ExportService().export(manifest: manifest, packageURL: url, destination: destination)
            try printJSON(destination.path)
        default:
            throw HelperError.unsupportedCommand(command)
        }
    }

    @MainActor
    private static func record(args: [String]) async throws {
        let arguments = try HelperArguments(args)
        let options: HelperRecordingOptions = try decodeJSON(arguments.value(for: "--options-json"))
        let target: HelperCaptureSource = try decodeJSON(arguments.value(for: "--target-json"))
        let projectURL = URL(filePath: try arguments.value(for: "--project-path"), directoryHint: .isDirectory)
        let recorder = MacNativeRecorder()
        try await recorder.start(options: options, target: target, projectURL: projectURL)
        try writeJSON(true, to: projectURL.appending(path: "recording-ready.json"))
        await readControlStream(recorder: recorder)
        let result = try await recorder.stop()
        try writeJSON(result, to: projectURL.appending(path: "recording-result.json"))
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }

    private static func decodeJSON<T: Decodable>(_ value: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(value.utf8))
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    private static func readControlStream(recorder: MacNativeRecorder) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var paused = false
                while true {
                    let data = FileHandle.standardInput.readData(ofLength: 1)
                    guard let byte = data.first else { break }
                    if byte == Character("q").asciiValue {
                        break
                    }
                    if byte == Character("p").asciiValue {
                        paused.toggle()
                        let shouldPause = paused
                        Task { @MainActor in
                            shouldPause ? recorder.pause() : recorder.resume()
                        }
                    }
                }
                continuation.resume()
            }
        }
    }
}

enum HelperError: LocalizedError {
    case missingCommand
    case unsupportedCommand(String)
    case missingArgument(String)
    case targetMissing
    case invalidRegion
    case permissionDenied(String)
    case noSamples
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCommand: "Missing helper command."
        case .unsupportedCommand(let command): "Unsupported helper command: \(command)."
        case .missingArgument(let name): "Missing required argument: \(name)."
        case .targetMissing: "The selected screen or window is no longer available."
        case .invalidRegion: "The selected recording area is no longer valid."
        case .permissionDenied(let name): "\(name) permission is required."
        case .noSamples: "No screen frames were received. Check Screen Recording permission."
        case .writerFailed(let message): message
        }
    }
}

struct HelperArguments {
    private let values: [String: String]

    init(_ args: [String]) throws {
        var parsed: [String: String] = [:]
        var index = 0
        while index < args.count {
            let key = args[index]
            guard key.hasPrefix("--"), index + 1 < args.count else {
                throw HelperError.missingArgument(key)
            }
            parsed[key] = args[index + 1]
            index += 2
        }
        values = parsed
    }

    func value(for key: String) throws -> String {
        guard let value = values[key] else { throw HelperError.missingArgument(key) }
        return value
    }
}

struct HelperFrameRect: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum HelperCaptureSourceType: String, Codable {
    case display
    case window
    case region
}

struct HelperCaptureSource: Codable, Hashable {
    let id: String
    let sourceType: HelperCaptureSourceType
    let title: String
    let subtitle: String
    let nativeId: UInt32?
    let displayId: UInt32?
    let frame: HelperFrameRect
    let appIconPath: String?
    let previewImagePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceType = "type"
        case title
        case subtitle
        case nativeId
        case displayId
        case frame
        case appIconPath
        case previewImagePath
    }
}

struct HelperAudioDevice: Codable {
    let id: String
    let name: String
    let isDefault: Bool
    let kind: String
}

struct HelperCameraDevice: Codable {
    let id: String
    let name: String
    let isDefault: Bool
}

struct HelperRecordingOptions: Codable, Equatable {
    let targetId: String?
    let frameRate: Int
    let recordSystemAudio: Bool
    let recordMicrophone: Bool
    let recordCamera: Bool
    let countdown: Int
    let region: HelperFrameRect?
}

struct HelperRecordingResult: Codable {
    let duration: Double
    let width: Int
    let height: Int
}

enum MacCaptureSourceProvider {
    static func captureSources() async throws -> [HelperCaptureSource] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displays = content.displays.map { display in
                let screenName = screen(for: display.displayID)?.localizedName
                return HelperCaptureSource(
                    id: "display:\(display.displayID)",
                    sourceType: .display,
                    title: screenName ?? "Display \(display.displayID)",
                    subtitle: "\(display.width) x \(display.height) - ID \(display.displayID)",
                    nativeId: display.displayID,
                    displayId: display.displayID,
                    frame: HelperFrameRect(x: 0, y: 0, width: Double(display.width), height: Double(display.height)),
                    appIconPath: nil,
                    previewImagePath: previewImagePath(forDisplayID: display.displayID)
                )
            }
            let windows = content.windows
                .filter(isUsefulCaptureWindow)
                .compactMap { window -> HelperCaptureSource? in
                    guard let display = display(containing: window.frame, from: content.displays) else {
                        return nil
                    }
                    let selectionFrame = window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                    let bundleIdentifier = window.owningApplication?.bundleIdentifier
                    return HelperCaptureSource(
                        id: "window:\(window.windowID)",
                        sourceType: .window,
                        title: window.title?.isEmpty == false ? window.title! : (window.owningApplication?.applicationName ?? "Window"),
                        subtitle: window.owningApplication?.applicationName ?? "",
                        nativeId: window.windowID,
                        displayId: display.displayID,
                        frame: HelperFrameRect(
                            x: selectionFrame.minX,
                            y: selectionFrame.minY,
                            width: selectionFrame.width,
                            height: selectionFrame.height
                        ),
                        appIconPath: appIconPath(bundleIdentifier: bundleIdentifier),
                        previewImagePath: previewImagePath(forWindowID: window.windowID)
                    )
                }
            return displays + windows
        } catch {
            if isScreenCapturePermissionError(error) {
                throw HelperError.permissionDenied("Screen Recording")
            }
            throw error
        }
    }

    static func audioDevices() -> [HelperAudioDevice] {
        let microphones = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices.enumerated().map { index, device in
            HelperAudioDevice(
                id: "microphone:\(device.uniqueID)",
                name: device.localizedName,
                isDefault: index == 0,
                kind: "microphone"
            )
        }
        return [
            HelperAudioDevice(
                id: "system:default",
                name: "Default system output",
                isDefault: true,
                kind: "systemAudio"
            )
        ] + microphones
    }

    static func cameraDevices() -> [HelperCameraDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices.enumerated().map { index, device in
            HelperCameraDevice(id: "camera:\(device.uniqueID)", name: device.localizedName, isDefault: index == 0)
        }
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == displayID
        }
    }

    static func display(containing frame: CGRect, from displays: [SCDisplay]) -> SCDisplay? {
        displays.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        }.flatMap { $0.frame.intersection(frame).area > 0 ? $0 : nil }
    }

    static func isUsefulCaptureWindow(_ window: SCWindow) -> Bool {
        guard window.frame.width >= 320, window.frame.height >= 180 else { return false }
        let app = window.owningApplication
        let bundleIdentifier = app?.bundleIdentifier
        let appName = app?.applicationName ?? ""
        let windowTitle = window.title ?? ""
        if let bundleIdentifier, excludedAppBundleIdentifiers.contains(bundleIdentifier) { return false }
        if bundleIdentifier == "com.apple.notificationcenterui" { return false }
        if bundleIdentifier == "com.apple.dock" { return false }
        if bundleIdentifier == "com.apple.accessibility.universalAccessAuthWarn" { return false }
        if bundleIdentifier == "com.apple.systempreferences" && windowTitle.localizedCaseInsensitiveContains("privacy") { return false }
        if appName == "GlideFrame" { return false }
        if appName == "universalAccessAuthWarn" { return false }
        if appName == "Notification Center" || appName == "通知中心" { return false }
        if appName == "Dock" || appName == "程序坞" { return false }
        if windowTitle == "录屏" || windowTitle == "Screen Recording" { return false }
        if windowTitle.hasPrefix("Wallpaper-") { return false }
        if windowTitle.localizedCaseInsensitiveContains("backstop") { return false }
        return true
    }

    static var excludedAppBundleIdentifiers: Set<String> {
        [
            Bundle.main.bundleIdentifier,
            "com.openfnzero.glideframe.crossplatform",
            "com.openfnzero.glideframe.crossplatform.recorder-helper",
            "com.openfnzero.glideframe.desktop",
            "com.openfnzero.glideframe.desktop.recorder-helper",
            "app.glideframe.studio"
        ].compactMap { $0 }.reduce(into: Set<String>()) { result, value in
            result.insert(value)
        }
    }

    static func isScreenCapturePermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }

    static func appIconPath(bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "GlideFrame/AppIcons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let fileName = bundleIdentifier.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let destination = cacheURL.appending(path: "\(fileName).png")
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination.path
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 64, height: 64)
        guard let tiff = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        try? png.write(to: destination)
        return destination.path
    }

    static func previewImagePath(forDisplayID displayID: CGDirectDisplayID) -> String? {
        guard let image = CGDisplayCreateImage(displayID) else { return nil }
        return writePreviewImage(image, name: "display-\(displayID)")
    }

    static func previewImagePath(forWindowID windowID: CGWindowID) -> String? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else { return nil }
        return writePreviewImage(image, name: "window-\(windowID)")
    }

    static func writePreviewImage(_ image: CGImage, name: String) -> String? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "GlideFrame/Previews", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let destination = cacheURL.appending(path: "\(name).png")
        let maxEdge = 2560.0
        let scale = min(1.0, maxEdge / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let bitmap else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        NSImage(cgImage: image, size: NSSize(width: width, height: height))
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        try? png.write(to: destination)
        return destination.path
    }
}

@MainActor
final class MacNativeRecorder: NSObject, SCStreamDelegate {
    private var content: SCShareableContent?
    private var stream: SCStream?
    private var writer: CaptureWriter?
    private let microphoneRecorder = MicrophoneRecorder()
    private let cameraRecorder = CameraRecorder()
    private var started = false
    private var outputWidth = 0
    private var outputHeight = 0

    func start(options: HelperRecordingOptions, target: HelperCaptureSource, projectURL: URL) async throws {
        try await validatePermissions(options: options)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        self.content = content
        let selection = try makeFilter(for: target, content: content, region: options.region?.cgRect)
        let mediaURL = projectURL.appending(path: "media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)

        let videoURL = mediaURL.appending(path: "screen.mp4")
        let livePreviewURL = mediaURL.appending(path: "live-preview.jpg")
        let preview = LivePreviewWriter(url: livePreviewURL)
        let writer = try CaptureWriter(
            url: videoURL,
            width: selection.width,
            height: selection.height,
            frameRate: options.frameRate,
            includeAudio: options.recordSystemAudio,
            previewHandler: { image in preview.write(image) }
        )
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
        if target.sourceType == .window { configuration.ignoreShadowsSingleWindow = true }

        let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: .init(label: "app.glideframe.tauri.helper.video", qos: .userInteractive))
        if options.recordSystemAudio {
            try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: .init(label: "app.glideframe.tauri.helper.audio", qos: .userInitiated))
        }

        if options.recordMicrophone {
            try microphoneRecorder.start(url: mediaURL.appending(path: "microphone.wav"))
        }
        if options.recordCamera {
            try cameraRecorder.start(url: mediaURL.appending(path: "camera.mp4"))
        }

        self.writer = writer
        self.stream = stream
        outputWidth = selection.width
        outputHeight = selection.height
        try await stream.startCapture()
        started = true
    }

    func pause() {
        guard started else { return }
        writer?.pause()
        microphoneRecorder.pause()
        cameraRecorder.pause()
    }

    func resume() {
        guard started else { return }
        writer?.resume()
        microphoneRecorder.resume()
        cameraRecorder.resume()
    }

    func stop() async throws -> HelperRecordingResult {
        guard started, let writer else { throw HelperError.targetMissing }
        microphoneRecorder.stop()
        try? await stream?.stopCapture()
        try? await cameraRecorder.stop()
        let duration = try await writer.finish()
        let result = HelperRecordingResult(duration: duration, width: outputWidth, height: outputHeight)
        stream = nil
        self.writer = nil
        started = false
        outputWidth = 0
        outputHeight = 0
        return result
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("GlideFrame helper stream stopped: \(error.localizedDescription)\n", stderr)
    }

    private func validatePermissions(options: HelperRecordingOptions) async throws {
        if options.recordMicrophone {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { throw HelperError.permissionDenied("Microphone") }
        }
        if options.recordCamera {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else { throw HelperError.permissionDenied("Camera") }
        }
    }

    private func makeFilter(
        for target: HelperCaptureSource,
        content: SCShareableContent,
        region: CGRect?
    ) throws -> (filter: SCContentFilter, width: Int, height: Int, sourceRect: CGRect?, pointerBounds: CGRect) {
        switch target.sourceType {
        case .display, .region:
            guard let nativeID = target.nativeId,
                  let display = content.displays.first(where: { $0.displayID == nativeID }),
                  let screen = MacCaptureSourceProvider.screen(for: display.displayID)
            else { throw HelperError.targetMissing }
            let excludedApplications = content.applications.filter { app in
                MacCaptureSourceProvider.excludedAppBundleIdentifiers.contains(app.bundleIdentifier)
            }
            let filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
            let displaySize = CGSize(width: display.width, height: display.height)
            let sourceRect = region.flatMap {
                CaptureRegionGeometry.normalizedSourceRect($0, displaySize: displaySize)
            }
            if region != nil, sourceRect == nil { throw HelperError.invalidRegion }
            let sourceSize = sourceRect?.size ?? displaySize
            let outputSize = CaptureRegionGeometry.outputSize(for: sourceSize, scale: screen.backingScaleFactor)
            let pointerBounds = sourceRect.map {
                CaptureRegionGeometry.appKitScreenRect(sourceRect: $0, screenFrame: screen.frame)
            } ?? screen.frame
            return (filter, Int(outputSize.width), Int(outputSize.height), sourceRect, pointerBounds)
        case .window:
            guard let nativeID = target.nativeId,
                  let window = content.windows.first(where: { $0.windowID == nativeID }),
                  let displayID = target.displayId,
                  let screen = MacCaptureSourceProvider.screen(for: displayID)
            else { throw HelperError.targetMissing }
            let targetFrame = target.frame.cgRect
            let sourceRect = region.flatMap {
                CaptureRegionGeometry.sourceRect($0, relativeTo: targetFrame)
            }
            if region != nil, sourceRect == nil { throw HelperError.invalidRegion }
            let sourceSize = sourceRect?.size ?? window.frame.size
            let outputSize = CaptureRegionGeometry.outputSize(for: sourceSize, scale: screen.backingScaleFactor)
            let pointerBounds = CaptureRegionGeometry.appKitScreenRect(
                sourceRect: region ?? targetFrame,
                screenFrame: screen.frame
            )
            return (SCContentFilter(desktopIndependentWindow: window), Int(outputSize.width), Int(outputSize.height), sourceRect, pointerBounds)
        }
    }
}

private final class LivePreviewWriter: @unchecked Sendable {
    let url: URL
    init(url: URL) { self.url = url }

    func write(_ image: CGImage) {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        try? (data as Data).write(to: url, options: .atomic)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}
